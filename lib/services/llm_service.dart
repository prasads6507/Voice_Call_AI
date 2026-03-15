import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'storage_service.dart';

enum LlmState { unloaded, connecting, ready, transcribing, generating, error }

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

  String _liveDraft = '';
  String _lastFinalizedQuestion = '';
  String _lastAnswerDraft = '';
  bool _questionFinalizedForCurrentTurn = false;
  final List<Map<String, String>> _history = [];

  Timer? _silenceTimer;
  Timer? _setupTimer;

  // ── Callbacks ──────────────────────────────────────────────────
  void Function(String text)? onCallerDraftUpdate;
  void Function(String question)? onCallerQuestionFinalized;
  void Function(String text)? onAIAnswerDraftUpdate;
  void Function(String question, String answer)? onTurnFinalized;

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
    _liveDraft = '';
    _lastFinalizedQuestion = '';
    _lastAnswerDraft = '';
    _questionFinalizedForCurrentTurn = false;
    _closedByUser = false;
    _reconnects = 0;
    notifyListeners();

    _apiKey = await StorageService.getGeminiApiKey();
    debugPrint('[LLM] Loaded Gemini key length: ${_apiKey.length}');
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
      debugPrint('[LLM] WS connecting to: $_wsUrl');
      _ws = WebSocketChannel.connect(uri);
      await _ws!.ready;
      debugPrint('[LLM] WebSocket open. Sending setup…');
      _sendSetup();
      _wsSub = _ws!.stream.listen(_onMsg, onError: _onWsErr, onDone: _onWsDone);
      return true;
    } catch (e) {
      _fail('WebSocket failed: $e');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  SETUP
  // ══════════════════════════════════════════════════════════════
  void _sendSetup() {
    _setupTimer?.cancel();
    _setupTimer = Timer(const Duration(seconds: 8), () {
      if (!_sessionReady && _state == LlmState.connecting) {
        debugPrint('[LLM] Setup timeout reached (8s)');
        _fail('Gemini Live did not become ready. Check setup payload and raw server response.');
      }
    });

    final msg = jsonEncode({
      'setup': {
        'model': 'models/$_liveModel',
        'generationConfig': {
          'responseModalities': ['AUDIO'],
        },
        'inputAudioTranscription': {},
        'outputAudioTranscription': {},
        'systemInstruction': {
          'parts': [
            {
              'text': 'You are a professional real-time interview assistant.\n\n'
                  'Rules:\n'
                  '- Always transcribe the caller\'s speech into English only.\n'
                  '- Even if the caller speaks in Telugu or any other language, output the transcription in English only.\n'
                  '- Caller question transcription is for UI display only.\n'
                  '- AI answers must be generated separately and must always be in English.\n'
                  '- Keep interview answers professional, relevant, and concise.\n'
                  'Resume context:\n$_resumeText'
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

  void sendAudioChunk(List<int> chunk) {
    if (!_sessionReady || _ws == null) {
      debugPrint('[LLM] Dropping audio chunk: session not ready yet');
      return;
    }

    try {
      final b64 = base64Encode(chunk);
      _ws!.sink.add(jsonEncode({
        'realtimeInput': {
          'mediaChunks': [
            {
              'mimeType': 'audio/pcm;rate=16000',
              'data': b64,
            }
          ]
        }
      }));
    } catch (e) {
      debugPrint('[LLM] sendAudioChunk error: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  MESSAGE HANDLER
  // ══════════════════════════════════════════════════════════════

  void _onMsg(dynamic raw) {
    try {
      String text;
      if (raw is String) {
        text = raw;
      } else if (raw is Uint8List) {
        text = utf8.decode(raw);
      } else {
        debugPrint('[LLM] Unknown message type: ${raw.runtimeType}');
        return;
      }

      final data = jsonDecode(text) as Map<String, dynamic>;

      if (data['error'] != null) {
        final err = data['error'] as Map<String, dynamic>;
        final msg = err['message']?.toString() ?? 'Unknown Gemini Live error';
        _fail('Gemini Live setup failed: $msg');
        return;
      }

      // Session ready
      if (data.containsKey('setupComplete')) {
        _setupTimer?.cancel();
        _sessionReady = true;
        _reconnects = 0;
        _state = LlmState.ready;
        debugPrint('[LLM] ✅ Session ready! Audio streaming live.');
        notifyListeners();
        return;
      }

      final sc = data['serverContent'] as Map<String, dynamic>?;
      if (sc == null) return;

      // 1. Handle Caller (inputTranscription)
      final inputTx = sc['inputTranscription'] as Map<String, dynamic>?;
      if (inputTx != null) {
        final text = _extractTranscriptText(inputTx);
        if (text.isNotEmpty) {
          _liveDraft = _mergeTranscript(_liveDraft, text);
          if (_state != LlmState.generating) {
            _state = LlmState.transcribing;
          }
          _questionFinalizedForCurrentTurn = false;
          debugPrint('[LLM] 🎤 Caller Draft: "$_liveDraft"');
          onCallerDraftUpdate?.call(_liveDraft);
          _restartSilenceTimer();
          notifyListeners();
        }
      }

      // 2. Handle AI (modelTurn / outputTranscription)
      String aiText = '';
      final modelTurn = sc['modelTurn'] as Map<String, dynamic>?;
      if (modelTurn != null) {
        aiText = _extractTranscriptText(modelTurn);
      }
      if (aiText.isEmpty) {
        final outputTx = sc['outputTranscription'] as Map<String, dynamic>?;
        if (outputTx != null) {
          aiText = _extractTranscriptText(outputTx);
        }
      }

      if (aiText.isNotEmpty) {
        debugPrint('[LLM] 🤖 AI Draft: "$aiText"');
        onAIAnswerDraftUpdate?.call(aiText);
      }

      // ── generationComplete → finalize ─────────
      if (sc['generationComplete'] == true) {
        debugPrint('[LLM] ⚡ generationComplete seen');
        _finalizeQuestion('generationComplete');
      }

      // ── turnComplete → finalize ─────────────────────────────────
      if (sc['turnComplete'] == true) {
        debugPrint('[LLM] ⚡ turnComplete seen');
        _finalizeQuestion('turnComplete');
      }
    } catch (e, st) {
      debugPrint('[LLM] onMsg error: $e\n$st');
    }
  }

  String _mergeTranscript(String existing, String incoming) {
    if (existing.isEmpty) return incoming;
    if (incoming.startsWith(existing)) return incoming;
    if (existing.endsWith(incoming)) return existing;
    return '$existing $incoming'.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  void _restartSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(const Duration(milliseconds: 1400), () {
      _finalizeQuestion('silence-timeout');
    });
  }

  String _cleanTranscript(String input) {
    return input
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(' .', '.')
        .replaceAll(' ,', ',')
        .trim();
  }

  void _finalizeQuestion(String source) {
    final question = _cleanTranscript(_liveDraft);
    if (question.isEmpty) {
      if (_state == LlmState.transcribing) {
        _state = LlmState.ready;
        notifyListeners();
      }
      return;
    }
    if (_questionFinalizedForCurrentTurn) return;
    if (question == _lastFinalizedQuestion) return;

    _questionFinalizedForCurrentTurn = true;
    _lastFinalizedQuestion = question;
    _liveDraft = '';

    debugPrint('[LLM] Finalizing question from $source → "$question"');
    _silenceTimer?.cancel();
    
    onCallerQuestionFinalized?.call(question);

    _state = LlmState.generating;
    notifyListeners();
    _generateAnswer(question);
  }

  String _extractTranscriptText(Map<String, dynamic> node) {
    final direct = node['text'] as String?;
    if (direct != null && direct.trim().isNotEmpty) {
      return direct.trim();
    }

    final parts = node['parts'] as List<dynamic>?;
    if (parts != null) {
      final buffer = StringBuffer();
      for (final item in parts) {
        if (item is Map<String, dynamic>) {
          final t = item['text'] as String?;
          if (t != null && t.trim().isNotEmpty) {
            if (buffer.isNotEmpty) buffer.write(' ');
            buffer.write(t.trim());
          }
        }
      }
      if (buffer.isNotEmpty) {
        return buffer.toString();
      }
    }

    final candidates = node['candidates'] as List<dynamic>?;
    if (candidates != null) {
      for (final c in candidates) {
        if (c is Map<String, dynamic>) {
          final content = c['content'] as Map<String, dynamic>?;
          if (content != null) {
            final nested = _extractTranscriptText(content);
            if (nested.isNotEmpty) return nested;
          }
        }
      }
    }

    final content = node['content'] as Map<String, dynamic>?;
    if (content != null) {
      final nested = _extractTranscriptText(content);
      if (nested.isNotEmpty) return nested;
    }

    return '';
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

    final prompt = '''
You are a professional interview coaching assistant.

Rules:
- Respond only in English.
- Even if the user question originates from another language or contains non-English terms, answer only in English.
- Rewrite the spoken question into clean, professional English understanding internally.
- Return a complete, polished paragraph, not fragments.
- Keep the answer concise, relevant, and professional.
- Do not return bullet fragments unless explicitly requested.

Question:
$question

Resume context:
$_resumeText
''';

    final body = jsonEncode({
      'contents': [
        ...ctx,
        {'role': 'user', 'parts': [{'text': prompt}]},
      ],
      'generationConfig': {'temperature': 0.7, 'maxOutputTokens': 200},
    });

    _lastAnswerDraft = '';

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

      debugPrint('[LLM] Answer stream started…');

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
              _lastAnswerDraft += t;
              onAIAnswerDraftUpdate?.call(_lastAnswerDraft);
            }
          }
        } catch (_) {}
      }

      if (_lastAnswerDraft.trim().isNotEmpty) {
        debugPrint('[LLM] Answer stream completed. Length: ${_lastAnswerDraft.length}');
        _history.insert(0, {'question': question, 'answer': _lastAnswerDraft.trim()});
        if (_history.length > 20) _history.removeLast();
        
        onTurnFinalized?.call(question, _lastAnswerDraft.trim());
      }
      _lastAnswerDraft = '';
      _questionFinalizedForCurrentTurn = false;
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

    String closeInfo = code != null ? ' (code $code${reason != null && reason.isNotEmpty ? ": $reason" : ""})' : '';

    if (code == 4000 || (reason != null && reason.contains('setup'))) {
      _fail('Gemini Live rejected setup$closeInfo.\nCheck setup payload.');
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
    _liveDraft = '';
    _lastFinalizedQuestion = '';
    _lastAnswerDraft = '';
    _questionFinalizedForCurrentTurn = false;
    _state = _sessionReady ? LlmState.ready : LlmState.unloaded;
    notifyListeners();
  }

  void disconnect() {
    _closedByUser = true;
    _silenceTimer?.cancel();
    _setupTimer?.cancel();
    _wsSub?.cancel();
    _wsSub = null;
    _ws?.sink.close();
    _ws = null;
    _sessionReady = false;
    _liveDraft = '';
    _state = LlmState.unloaded;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
