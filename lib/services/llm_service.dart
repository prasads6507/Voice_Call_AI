import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'storage_service.dart';

enum LlmState { unloaded, connecting, ready, transcribing, generating, error }

/// ═══════════════════════════════════════════════════════════════════
///  THE BUG — confirmed by the on-screen error message:
///
///  "Unknown name "inputAudioTranscription" at
///   'setup.generation_config': Cannot find field."
///
///  inputAudioTranscription is a field of BidiGenerateContentSetup,
///  NOT a field of GenerationConfig. It must sit at the TOP LEVEL of
///  the "setup" object, alongside "generationConfig" — not inside it.
///
///  ❌ WRONG (what we were sending every time):
///  {
///    "setup": {
///      "generationConfig": {
///        "responseModalities": ["AUDIO"],
///        "inputAudioTranscription": {}   ← WRONG nesting level
///      }
///    }
///  }
///
///  ✅ CORRECT (this is the fix):
///  {
///    "setup": {
///      "generationConfig": {
///        "responseModalities": ["AUDIO"]
///      },
///      "inputAudioTranscription": {}     ← TOP level of setup
///    }
///  }
/// ═══════════════════════════════════════════════════════════════════
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

  String _turnText = '';
  final List<Map<String, String>> _history = [];

  // ── Callbacks ──────────────────────────────────────────────────
  Function(String)? onCallerSpeechUpdate;
  Function(String)? onAIAnswerStreaming;
  Function(String, String)? onTurnComplete;
  Function(String)? onQuestionComplete;

  // ── API constants ──────────────────────────────────────────────
  static const _wsUrl =
      'wss://generativelanguage.googleapis.com/ws/'
      'google.ai.generativelanguage.v1beta'
      '.GenerativeService.BidiGenerateContent';

  static const _liveModel =
      'gemini-2.5-flash-native-audio-preview-12-2025';

  static const _answerModel = 'gemini-2.0-flash-lite';
  static const _httpBase =
      'https://generativelanguage.googleapis.com/v1beta/models';

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
      _fail('No Gemini API key found.\nGo to Settings → Add API Key.');
      return false;
    }
    debugPrint('[LLM] Key loaded (${_apiKey.length} chars). Running preflight…');

    // Verify key before WebSocket attempt
    final preflightError = await _checkApiKey();
    if (preflightError != null) {
      _fail(preflightError);
      return false;
    }

    return _connect();
  }

  Future<String?> _checkApiKey() async {
    try {
      final resp = await http
          .get(Uri.parse('$_httpBase?key=$_apiKey'))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) return null;
      try {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final msg = body['error']?['message'] as String? ?? resp.body;
        return 'API key error (${resp.statusCode}): $msg';
      } catch (_) {
        return 'API key error: HTTP ${resp.statusCode}';
      }
    } on TimeoutException {
      return 'Network timeout. Check your internet connection.';
    } catch (e) {
      return 'Network error: $e';
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  WEBSOCKET
  // ══════════════════════════════════════════════════════════════

  Future<bool> _connect() async {
    try {
      final uri = Uri.parse('$_wsUrl?key=$_apiKey');
      debugPrint('[LLM] WS connecting…');
      _ws = WebSocketChannel.connect(uri);
      await _ws!.ready;
      debugPrint('[LLM] WS open. Sending setup…');
      _sendSetup();
      _wsSub = _ws!.stream.listen(_onMsg, onError: _onWsErr, onDone: _onWsDone);
      return true;
    } catch (e) {
      _fail('WebSocket failed: $e');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  SETUP — THE FIX IS HERE
  //
  //  BidiGenerateContentSetup proto fields:
  //    setup.model                   ← model name
  //    setup.generationConfig        ← GenerationConfig (responseModalities etc)
  //    setup.systemInstruction       ← system prompt
  //    setup.inputAudioTranscription ← AudioTranscriptionConfig (TOP LEVEL)
  //    setup.outputAudioTranscription← AudioTranscriptionConfig (TOP LEVEL)
  //    setup.tools                   ← tools array
  //
  //  inputAudioTranscription is NOT inside generationConfig.
  //  It is a sibling of generationConfig under setup.
  // ══════════════════════════════════════════════════════════════
  void _sendSetup() {
    final msg = jsonEncode({
      'setup': {
        'model': 'models/$_liveModel',

        // GenerationConfig — only contains response modalities
        'generationConfig': {
          'responseModalities': ['AUDIO'],
        },

        // ✅ TOP LEVEL of setup — NOT inside generationConfig
        'inputAudioTranscription': {},

        'systemInstruction': {
          'parts': [
            {
              'text': 'You are a silent listener. '
                  'Do not generate any responses. '
                  'Just transcribe the audio input.'
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
      debugPrint('[LLM] ← ${raw.toString().substring(0, raw.toString().length.clamp(0, 120))}');

      // Session ready
      if (data.containsKey('setupComplete')) {
        _sessionReady = true;
        _reconnects = 0;
        _state = LlmState.ready;
        debugPrint('[LLM] ✅ Session ready! Audio streaming live.');
        notifyListeners();
        return;
      }

      final sc = data['serverContent'] as Map<String, dynamic>?;
      if (sc == null) return;

      // ── Caller speech transcription ───────────────────────────
      final inputTx = sc['inputTranscription'] as Map<String, dynamic>?;
      if (inputTx != null) {
        String chunk = '';

        // Plain text (standard path with empty inputAudioTranscription config)
        final txt = inputTx['text'] as String? ?? '';
        if (txt.trim().isNotEmpty) chunk = txt;

        // Parts array fallback
        if (chunk.isEmpty) {
          final parts = inputTx['parts'] as List<dynamic>?;
          for (final p in parts ?? []) {
            final t = (p as Map<String, dynamic>)['text'] as String?;
            if (t != null && t.trim().isNotEmpty) chunk += t;
          }
        }

        if (chunk.isNotEmpty) {
          _turnText += chunk;
          if (_state != LlmState.generating) _state = LlmState.transcribing;
          debugPrint('[LLM] 🎤 "$chunk"');
          onCallerSpeechUpdate?.call(_turnText);
          notifyListeners();
        }
      }

      // ── generationComplete → generate coaching answer ─────────
      if (sc['generationComplete'] == true) {
        final question = _turnText.trim();
        _turnText = '';
        debugPrint('[LLM] ⚡ generationComplete → "$question"');
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
      debugPrint('[LLM] onMsg error: $e\n$st');
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  STEP 2 — COACHING ANSWER (Gemini HTTP stream)
  // ══════════════════════════════════════════════════════════════

  Future<void> _generateAnswer(String question) async {
    final url = Uri.parse(
        '$_httpBase/$_answerModel:streamGenerateContent?key=$_apiKey&alt=sse');

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
            'text': 'You are a stealth real-time interview coach.\n'
                'The candidate is on a live phone interview right now.\n'
                'Given what the interviewer said, provide a short suggested answer.\n'
                'FORMAT: Start with 💡 then 2-3 natural sentences. Under 60 words. No preamble.\n'
                'Resume:\n$_resumeText'
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
        debugPrint('[LLM] Answer HTTP ${resp.statusCode}: $err');
        _state = LlmState.ready;
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
      debugPrint('[LLM] Answer error: $e');
      _state = LlmState.ready;
      notifyListeners();
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  WS ERROR / CLOSE
  // ══════════════════════════════════════════════════════════════

  void _onWsErr(dynamic e) {
    debugPrint('[LLM] WS error: $e');
    _fail('$e');
  }

  void _onWsDone() {
    final code = _ws?.closeCode;
    final reason = _ws?.closeReason;
    debugPrint('[LLM] WS closed. code=$code reason=$reason');
    _sessionReady = false;

    if (_closedByUser) {
      _state = LlmState.unloaded;
      notifyListeners();
      return;
    }

    if (_reconnects < _maxReconnects) {
      _reconnects++;
      _state = LlmState.connecting;
      debugPrint('[LLM] Reconnecting $_reconnects/$_maxReconnects…');
      notifyListeners();
      Future.delayed(const Duration(seconds: 2), () {
        if (!_closedByUser) _connect();
      });
    } else {
      String closeInfo = code != null ? ' (code $code${reason != null ? ": $reason" : ""})' : '';
      _fail('Connection failed$closeInfo.\n\n'
          'Check:\n'
          '• API key is valid (Settings → API Key)\n'
          '• Internet connection is stable\n'
          '• AI Studio key has Gemini API enabled');
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
