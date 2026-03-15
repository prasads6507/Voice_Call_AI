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

  static const _liveModel = 'gemini-2.0-flash-exp';
  static const _answerModel = 'gemini-2.0-flash';
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
    _setupTimer = Timer(const Duration(seconds: 15), () {
      if (!_sessionReady && _state == LlmState.connecting) {
        debugPrint('[LLM] Setup timeout reached (15s)');
        _fail('Setup Timeout. Check your API key and Internet.');
      }
    });

    final msg = jsonEncode({
      'setup': {
        'model': 'models/$_liveModel',
        'generation_config': {
          'response_modalities': ['AUDIO'],
        },
        'input_audio_transcription': {},
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
        'realtime_input': {
          'media_chunks': [
            {
              'mime_type': 'audio/pcm;rate=16000',
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
        return;
      }

      final data = jsonDecode(text) as Map<String, dynamic>;

      if (data['error'] != null) {
        final err = data['error'] as Map<String, dynamic>;
        final msg = err['message']?.toString() ?? 'Unknown Gemini Live error';
        _fail('Gemini Live error: $msg');
        return;
      }

      // ── Root-level fields (Multimodal Live API) ──────────────────
      if (data.containsKey('setupComplete') || data.containsKey('setup_complete')) {
        _setupTimer?.cancel();
        _sessionReady = true;
        _reconnects = 0;
        _state = LlmState.ready;
        debugPrint('[LLM] ✅ Session ready!');
        notifyListeners();
        return;
      }

      // Check for transcription at the root level
      final rootTranscript = (data['input_audio_transcription'] ?? data['inputAudioTranscription']) as Map<String, dynamic>?;
      if (rootTranscript != null) {
        final text = _extractTranscriptText(rootTranscript);
        if (text.isNotEmpty) {
          _handleTranscriptUpdate(text);
          return;
        }
      }

      final sc = (data['serverContent'] ?? data['server_content']) as Map<String, dynamic>?;
      if (sc != null) {
        // Check for transcription inside serverContent (fallback)
        final inputTx = (sc['input_audio_transcription'] ?? sc['inputAudioTranscription'] ?? sc['inputTranscription']) as Map<String, dynamic>?;
        if (inputTx != null) {
          final text = _extractTranscriptText(inputTx);
          if (text.isNotEmpty) _handleTranscriptUpdate(text);
        }

        if (sc['generation_complete'] == true || sc['turn_complete'] == true || 
            sc['generationComplete'] == true || sc['turnComplete'] == true) {
          _finalizeQuestion('server-flag');
        }
        return;
      }
    } catch (e) {
      debugPrint('[LLM] onMsg parse error: $e');
    }
  }

  void _handleTranscriptUpdate(String text) {
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

    // Handle nested serverContent structure if needed
    final serverContent = node['serverContent'] as Map<String, dynamic>?;
    if (serverContent != null) {
      final nested = _extractTranscriptText(serverContent);
      if (nested.isNotEmpty) return nested;
    }

    final transcript = node['transcript'] as String?;
    if (transcript != null && transcript.trim().isNotEmpty) {
      return transcript.trim();
    }

    return '';
  }

  // ══════════════════════════════════════════════════════════════
  //  STEP 2 — COACHING ANSWER (Gemini HTTP stream)
  // ══════════════════════════════════════════════════════════════

  Future<void> _generateAnswer(String question) async {
    final url = Uri.parse(
      '$_httpBase/$_answerModel:streamGenerateContent?key=$_apiKey&alt=sse',
    );

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
- Return a complete, polished paragraph, not fragments.
- Keep the answer concise, relevant, and professional.

Question:
$question

Resume context:
$_resumeText
''';

    final body = jsonEncode({
      'contents': [
        ...ctx,
        {
          'role': 'user',
          'parts': [{'text': prompt}]
        }
      ],
      'generationConfig': {
        'temperature': 0.7,
        'maxOutputTokens': 220,
      },
    });

    _lastAnswerDraft = 'Thinking...';
    onAIAnswerDraftUpdate?.call(_lastAnswerDraft);

    try {
      final req = http.Request('POST', url)
        ..headers['Content-Type'] = 'application/json'
        ..body = body;

      final resp = await http.Client().send(req);

      if (resp.statusCode != 200) {
        final err = await resp.stream.bytesToString();
        debugPrint('[LLM] Answer HTTP ${resp.statusCode}: $err');

        final visibleError =
            'Answer generation failed (${resp.statusCode}). Please retry.';
        onAIAnswerDraftUpdate?.call(visibleError);
        onTurnFinalized?.call(question, visibleError);
        return;
      }

      _lastAnswerDraft = '';
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

          final parts = cands[0]['content']?['parts'] as List?;
          for (final p in parts ?? const []) {
            final t = (p as Map)['text'] as String?;
            if (t != null && t.isNotEmpty) {
              if (_lastAnswerDraft == 'Thinking...') {
                _lastAnswerDraft = '';
              }
              _lastAnswerDraft += t;
              onAIAnswerDraftUpdate?.call(_lastAnswerDraft);
            }
          }
        } catch (e) {
          debugPrint('[LLM] SSE parse error: $e');
        }
      }

      final finalAnswer = _lastAnswerDraft.trim();
      if (finalAnswer.isNotEmpty) {
        _history.insert(0, {'question': question, 'answer': finalAnswer});
        if (_history.length > 20) _history.removeLast();
        onTurnFinalized?.call(question, finalAnswer);
      } else {
        onTurnFinalized?.call(question, 'No answer was generated.');
      }
    } catch (e) {
      debugPrint('[LLM] Answer error: $e');
      onTurnFinalized?.call(question, 'Answer generation failed. Please retry.');
    } finally {
      _lastAnswerDraft = '';
      _questionFinalizedForCurrentTurn = false;
      _state = _sessionReady ? LlmState.ready : LlmState.unloaded;
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
