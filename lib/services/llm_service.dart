import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'storage_service.dart';

enum LlmState { unloaded, connecting, ready, transcribing, generating, error }

/// ══════════════════════════════════════════════════════════════════
///  GEMINI LIVE  — confirmed working config as of March 2026
/// ══════════════════════════════════════════════════════════════════
///
///  ENDPOINT  : v1beta  (official docs URL — NOT v1alpha)
///              v1alpha only needed for experimental features like
///              affective dialog; the 09-2025 model throws 1008 on
///              v1alpha with "model not found for this API version"
///
///  LIVE MODEL: gemini-2.5-flash-native-audio-preview-12-2025
///              (09-2025 model is deprecated, removed March 19 2026)
///
///  STRATEGY  : Same two-step as Cheating Daddy
///    Step 1 — Gemini Live WS → inputAudioTranscription events
///    Step 2 — Gemini HTTP generateContentStream → coaching answer
/// ══════════════════════════════════════════════════════════════════
class LlmService extends ChangeNotifier {
  LlmState _state = LlmState.unloaded;
  String _error = '';
  String _apiKey = '';
  String _resumeText = '';

  WebSocketChannel? _ws;
  StreamSubscription? _wsSub;
  bool _sessionReady = false;
  bool _closedByUser = false;
  int _reconnects = 0;
  static const _maxReconnects = 3;

  String _turnText = ''; // accumulates caller speech this turn
  final List<Map<String, String>> _history = []; // last 10 Q&A

  // ── Callbacks ──────────────────────────────────────────────────
  Function(String)? onCallerSpeechUpdate;
  Function(String)? onAIAnswerStreaming;
  Function(String, String)? onTurnComplete;
  Function(String)? onQuestionComplete; // legacy compat

  // ── API constants ──────────────────────────────────────────────
  //
  // ✅ CORRECT: v1beta  — this is what Google's official docs show
  // ❌ WRONG:   v1alpha — causes 1008 "model not found" for native audio models
  static const _wsUrl =
      'wss://generativelanguage.googleapis.com/ws/'
      'google.ai.generativelanguage.v1beta'
      '.GenerativeService.BidiGenerateContent';

  // ✅ 12-2025 model — current, works on v1beta
  // ❌ 09-2025 model — deprecated, throws 1008 on v1alpha, removed March 19 2026
  static const _liveModel = 'gemini-2.5-flash-native-audio-preview-12-2025';

  // Fast text model for coaching answers
  static const _answerModel = 'gemini-2.0-flash-lite';
  static const _httpBase = 'https://generativelanguage.googleapis.com/v1beta/models';

  // ── Getters ────────────────────────────────────────────────────
  LlmState get state => _state;
  String get errorMessage => _error;
  String get currentTranscription => _turnText;
  bool get isConnected =>
      _state == LlmState.ready ||
      _state == LlmState.transcribing ||
      _state == LlmState.generating;

  // ══════════════════════════════════════════════════════════════
  //  INITIALIZE
  // ══════════════════════════════════════════════════════════════

  Future<bool> initialize({String resumeText = ''}) async {
    if (_sessionReady) return true;
    if (_state == LlmState.connecting) return false;

    _state = LlmState.connecting;
    _resumeText = resumeText;
    _turnText = '';
    _closedByUser = false;
    _reconnects = 0;
    notifyListeners();

    _apiKey = await StorageService.getGeminiApiKey();
    if (_apiKey.isEmpty) {
      _fail('No Gemini API key found. Go to Settings → Add API Key.');
      return false;
    }

    debugPrint('[LLM] API key loaded (${_apiKey.length} chars). Connecting…');
    return _connect();
  }

  // ══════════════════════════════════════════════════════════════
  //  WEBSOCKET
  // ══════════════════════════════════════════════════════════════

  Future<bool> _connect() async {
    try {
      final uri = Uri.parse('$_wsUrl?key=$_apiKey');
      debugPrint('[LLM] Connecting to: $_wsUrl');
      _ws = WebSocketChannel.connect(uri);
      await _ws!.ready;
      debugPrint('[LLM] ✓ WS open. Sending setup…');
      _sendSetup();
      _wsSub = _ws!.stream.listen(_onMsg, onError: _onWsErr, onDone: _onWsDone);
      return true;
    } catch (e) {
      _fail('WebSocket failed: $e\nCheck your internet connection and API key.');
      return false;
    }
  }

  // ──────────────────────────────────────────────────────────────
  //  SETUP MESSAGE
  //
  //  Key points confirmed by official Google docs (March 2026):
  //  • responseModalities: ["AUDIO"] — required for native audio pipeline
  //  • inputAudioTranscription: {}   — enables transcription events
  //  • All keys camelCase            — snake_case silently ignored
  // ──────────────────────────────────────────────────────────────
  void _sendSetup() {
    final msg = jsonEncode({
      'setup': {
        'model': 'models/$_liveModel',
        'generationConfig': {
          'responseModalities': ['AUDIO'],
          'inputAudioTranscription': {
            'enableSpeakerDiarization': true,
            'minSpeakerCount': 2,
            'maxSpeakerCount': 2,
          },
        },
        'systemInstruction': {
          'parts': [
            {
              'text': 'You are a silent listener. Do not respond. '
                  'Just process the audio input for transcription.'
            }
          ]
        },
      }
    });
    _ws?.sink.add(msg);
    debugPrint('[LLM] Setup sent. Waiting for setupComplete…');
  }

  // ══════════════════════════════════════════════════════════════
  //  AUDIO INPUT
  // ══════════════════════════════════════════════════════════════

  void sendAudioChunk(List<int> pcmBytes) {
    if (!_sessionReady || _ws == null) return;
    _ws!.sink.add(jsonEncode({
      'realtimeInput': {
        'mediaChunks': [
          {'mimeType': 'audio/pcm;rate=16000', 'data': base64Encode(pcmBytes)}
        ]
      }
    }));
  }

  // ══════════════════════════════════════════════════════════════
  //  MESSAGE HANDLER
  // ══════════════════════════════════════════════════════════════

  void _onMsg(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;

      // ── Session ready ──────────────────────────────────────────
      if (data.containsKey('setupComplete')) {
        _sessionReady = true;
        _reconnects = 0;
        _state = LlmState.ready;
        debugPrint('[LLM] ✅ setupComplete — session ready!');
        notifyListeners();
        return;
      }

      final sc = data['serverContent'] as Map<String, dynamic>?;
      if (sc == null) return;

      // ── Input transcription (caller speech) ───────────────────
      //
      // With diarization ON, path is:
      //   serverContent.inputTranscription.results[].transcript
      //   serverContent.inputTranscription.results[].speakerId
      //
      // Without diarization, path is:
      //   serverContent.inputTranscription.text  (plain string)
      //
      final inputTx = sc['inputTranscription'] as Map<String, dynamic>?;
      if (inputTx != null) {
        String chunk = '';

        // Path 1 — diarized results
        final results = inputTx['results'] as List<dynamic>?;
        if (results != null && results.isNotEmpty) {
          for (final r in results) {
            final m = r as Map<String, dynamic>;
            final t = m['transcript'] as String? ?? '';
            if (t.trim().isEmpty) continue;
            final sid = m['speakerId'] as int?;
            chunk += '[${sid == 1 ? "Interviewer" : "Candidate"}]: $t\n';
          }
        }

        // Path 2 — plain text fallback
        if (chunk.isEmpty) {
          final t = inputTx['text'] as String? ?? '';
          if (t.trim().isNotEmpty) chunk = t;
        }

        if (chunk.isNotEmpty) {
          _turnText += chunk;
          if (_state != LlmState.generating) _state = LlmState.transcribing;
          debugPrint('[LLM] 🎤 "$chunk"');
          onCallerSpeechUpdate?.call(_turnText);
          notifyListeners();
        }
      }

      // ── generationComplete = AI done processing audio turn ────
      // This is the trigger to generate the coaching answer.
      if (sc['generationComplete'] == true) {
        final question = _turnText.trim();
        _turnText = '';
        debugPrint('[LLM] ⚡ generationComplete. Question: "$question"');
        if (question.isNotEmpty) {
          _state = LlmState.generating;
          notifyListeners();
          _generateAnswer(question);
        }
      }

      // ── turnComplete ──────────────────────────────────────────
      if (sc['turnComplete'] == true && _state != LlmState.generating) {
        _state = LlmState.ready;
        notifyListeners();
      }
    } catch (e, st) {
      debugPrint('[LLM] Parse error: $e\n$st');
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  STEP 2 — GENERATE COACHING ANSWER (Gemini HTTP)
  // ══════════════════════════════════════════════════════════════

  Future<void> _generateAnswer(String question) async {
    final url = Uri.parse(
        '$_httpBase/$_answerModel:streamGenerateContent?key=$_apiKey&alt=sse');

    // Build context from recent history
    final ctx = <Map<String, dynamic>>[];
    for (final t in _history.take(8)) {
      ctx
        ..add({'role': 'user', 'parts': [{'text': t['question']}]})
        ..add({'role': 'model', 'parts': [{'text': t['answer']}]});
    }

    final body = jsonEncode({
      'system_instruction': {
        'parts': [
          {
            'text': '''You are a stealth real-time interview coach.
The candidate is on a live phone interview RIGHT NOW and needs help.

When given what the interviewer said, produce a suggested answer the candidate can say.

FORMAT — output ONLY this, nothing else:
💡 [2-3 sentence natural answer]

Rules: Natural speech, under 60 words, draw from resume when relevant, no preamble.

Candidate resume:
$_resumeText'''
          }
        ]
      },
      'contents': [
        ...ctx,
        {'role': 'user', 'parts': [{'text': question}]},
      ],
      'generationConfig': {'temperature': 0.7, 'maxOutputTokens': 200},
    });

    String full = '';
    try {
      final req = http.Request('POST', url)
        ..headers['Content-Type'] = 'application/json'
        ..body = body;

      final resp = await http.Client().send(req);

      if (resp.statusCode != 200) {
        final err = await resp.stream.bytesToString();
        debugPrint('[LLM] HTTP ${resp.statusCode}: $err');
        // Don't crash — just show the error and stay ready
        _state = LlmState.error;
        _error = 'Answer API error ${resp.statusCode}. '
            'Check API key has Gemini API access.';
        notifyListeners();
        return;
      }

      await for (final line in resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (!line.startsWith('data: ')) continue;
        final payload = line.substring(6).trim();
        if (payload.isEmpty || payload == '[DONE]') continue;
        try {
          final j = jsonDecode(payload) as Map<String, dynamic>;
          final cands = j['candidates'] as List?;
          if (cands == null || cands.isEmpty) continue;
          final parts = (cands[0]['content']?['parts']) as List?;
          for (final p in parts ?? []) {
            final t = (p as Map)['text'] as String?;
            if (t != null && t.isNotEmpty) {
              full += t;
              onAIAnswerStreaming?.call(full);
            }
          }
        } catch (_) {}
      }

      if (full.trim().isNotEmpty) {
        _history.insert(0, {'question': question, 'answer': full.trim()});
        if (_history.length > 20) _history.removeLast();
        onTurnComplete?.call(question, full.trim());
        onQuestionComplete?.call(question);
      }

      _state = LlmState.ready;
      notifyListeners();
    } catch (e) {
      debugPrint('[LLM] HTTP error: $e');
      _state = LlmState.ready; // recover, don't get stuck
      notifyListeners();
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  WS ERROR / CLOSE + AUTO RECONNECT
  // ══════════════════════════════════════════════════════════════

  void _onWsErr(dynamic e) {
    debugPrint('[LLM] WS error: $e');
    _fail('Connection error: $e');
  }

  void _onWsDone() {
    final closeCode = _ws?.closeCode;
    final closeReason = _ws?.closeReason;
    debugPrint('[LLM] WS closed. code=$closeCode reason=$closeReason '
        'userClosed=$_closedByUser reconnects=$_reconnects/$_maxReconnects');
    _sessionReady = false;
    if (_closedByUser) {
      _state = LlmState.unloaded;
      notifyListeners();
      return;
    }
    if (_reconnects < _maxReconnects) {
      _reconnects++;
      _state = LlmState.connecting;
      debugPrint('[LLM] Reconnecting $_reconnects/$_maxReconnects in 2s…');
      notifyListeners();
      Future.delayed(const Duration(seconds: 2), () {
        if (!_closedByUser) _connect();
      });
    } else {
      _fail('Lost connection after $_maxReconnects retries. End call and try again.');
    }
  }

  void _fail(String msg) {
    _state = LlmState.error;
    _error = msg;
    debugPrint('[LLM] ❌ $msg');
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════
  //  CONTROL
  // ══════════════════════════════════════════════════════════════

  void clearSession() {
    _turnText = '';
    _state = _sessionReady ? LlmState.ready : LlmState.unloaded;
    notifyListeners();
  }

  void disconnect() {
    _closedByUser = true;
    _wsSub?.cancel();
    _wsSub = null;
    _ws?.sink.close();
    _ws = null;
    _sessionReady = false;
    _turnText = '';
    _state = LlmState.unloaded;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
