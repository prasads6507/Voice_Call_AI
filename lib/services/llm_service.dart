import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'storage_service.dart';

enum LlmState {
  unloaded,
  connecting,
  ready,
  generating,
  error,
  disconnected,
}

class LlmService extends ChangeNotifier {
  LlmState _state = LlmState.unloaded;
  String _currentAnswer = '';
  String _currentQuestion = '';
  final List<Map<String, String>> _answerHistory = [];
  String _errorMessage = '';
  String _apiKey = '';

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _sessionConfigured = false;

  // Gemini Live API config
  static const String _model = 'gemini-live-2.5-flash-native-audio';
  static const String _wsBaseUrl =
      'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent';

  LlmState get state => _state;
  String get currentAnswer => _currentAnswer;
  String get currentQuestion => _currentQuestion;
  List<Map<String, String>> get answerHistory => List.unmodifiable(_answerHistory);
  String get errorMessage => _errorMessage;
  bool get isGenerating => _state == LlmState.generating;
  bool get isConnected => _state == LlmState.ready || _state == LlmState.generating;

  /// Initialize: load API key and connect WebSocket
  Future<bool> initialize() async {
    if (_state == LlmState.ready || _state == LlmState.generating) return true;

    _state = LlmState.connecting;
    notifyListeners();

    try {
      _apiKey = await StorageService.getGeminiApiKey();
      if (_apiKey.isEmpty) {
        _state = LlmState.error;
        _errorMessage = 'Gemini API key not configured';
        notifyListeners();
        return false;
      }

      await _connectWebSocket();
      return true;
    } catch (e) {
      debugPrint('[LlmService] Init error: $e');
      _state = LlmState.error;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Connect to Gemini Live API WebSocket
  Future<void> _connectWebSocket() async {
    final uri = Uri.parse('$_wsBaseUrl?key=$_apiKey');
    
    _channel = WebSocketChannel.connect(uri);
    await _channel!.ready;
    
    debugPrint('[LlmService] WebSocket connected to Gemini Live API');

    // Send session setup message
    _sendSetupMessage();

    // Listen for responses
    _subscription = _channel!.stream.listen(
      _onMessage,
      onError: _onError,
      onDone: _onDone,
    );
  }

  /// Send initial session configuration
  void _sendSetupMessage() {
    final setupMsg = {
      'setup': {
        'model': 'models/$_model',
        'generationConfig': {
          'responseModalities': ['TEXT'],
          'temperature': 0.7,
          'maxOutputTokens': 512,
        },
        'systemInstruction': {
          'parts': [
            {
              'text': 'You are a confident, articulate interview coach helping someone '
                  'answer interview questions naturally. You are silently listening to '
                  'an ongoing phone interview. When a question is detected, provide a '
                  'concise 2-3 sentence answer using the candidate\'s resume context. '
                  'Sound human, specific, and confident. Respond ONLY with the answer text, '
                  'no preamble or labels.'
            }
          ]
        },
      }
    };

    _channel?.sink.add(jsonEncode(setupMsg));
    debugPrint('[LlmService] Sent session setup message');
  }

  /// Handle incoming WebSocket messages
  void _onMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;

      // Handle setup complete
      if (data.containsKey('setupComplete')) {
        _sessionConfigured = true;
        _state = LlmState.ready;
        debugPrint('[LlmService] Gemini Live session configured');
        notifyListeners();
        return;
      }

      // Handle server content (streamed answer)
      if (data.containsKey('serverContent')) {
        final serverContent = data['serverContent'] as Map<String, dynamic>;
        final modelTurn = serverContent['modelTurn'] as Map<String, dynamic>?;
        
        if (modelTurn != null) {
          final parts = modelTurn['parts'] as List<dynamic>?;
          if (parts != null) {
            for (final part in parts) {
              final textPart = (part as Map<String, dynamic>)['text'] as String?;
              if (textPart != null) {
                _currentAnswer += textPart;
                notifyListeners();
              }
            }
          }
        }

        // Check if turn is complete
        final turnComplete = serverContent['turnComplete'] as bool? ?? false;
        if (turnComplete && _currentAnswer.isNotEmpty) {
          // Save to history
          _answerHistory.insert(0, {
            'question': _currentQuestion,
            'answer': _currentAnswer,
          });
          _state = LlmState.ready;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[LlmService] Message parse error: $e');
    }
  }

  void _onError(dynamic error) {
    debugPrint('[LlmService] WebSocket error: $error');
    _state = LlmState.error;
    _errorMessage = error.toString();
    notifyListeners();
  }

  void _onDone() {
    debugPrint('[LlmService] WebSocket closed');
    _state = LlmState.disconnected;
    _sessionConfigured = false;
    notifyListeners();
  }

  /// Generate answer for a detected interview question
  Future<void> generateAnswer(String question, String resumeText) async {
    if (!_sessionConfigured || _channel == null) {
      debugPrint('[LlmService] Cannot generate: session not configured');
      // Try to reconnect
      await initialize();
      if (!_sessionConfigured) return;
    }

    _state = LlmState.generating;
    _currentQuestion = question;
    _currentAnswer = '';
    notifyListeners();

    // Build the prompt with resume context
    final relevantContext = _searchContext(question, resumeText);
    final prompt = 'Resume Context:\n$relevantContext\n\n'
        'Interview Question: $question\n\n'
        'Provide a concise, confident 2-3 sentence answer:';

    // Send as client content
    final msg = {
      'clientContent': {
        'turns': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'turnComplete': true,
      }
    };

    _channel?.sink.add(jsonEncode(msg));
    debugPrint('[LlmService] Sent question to Gemini: $question');
  }

  /// Send raw audio to Gemini as a silent listener (base64 PCM)
  void sendAudioChunk(List<int> pcmBytes) {
    if (!_sessionConfigured || _channel == null) return;

    final msg = {
      'realtimeInput': {
        'mediaChunks': [
          {
            'mimeType': 'audio/pcm;rate=16000',
            'data': base64Encode(pcmBytes),
          }
        ]
      }
    };

    _channel?.sink.add(jsonEncode(msg));
  }

  /// Search resume for most relevant paragraphs
  String _searchContext(String question, String resumeText) {
    if (resumeText.trim().isEmpty) {
      return 'No resume context provided.';
    }

    final paragraphs = resumeText
        .split(RegExp(r'\n\s*\n'))
        .where((p) => p.trim().length > 20)
        .toList();

    if (paragraphs.isEmpty) return resumeText;

    final questionWords = question.toLowerCase().split(RegExp(r'\W+'));
    
    final scored = paragraphs.map((p) {
      final paragraphWords = p.toLowerCase().split(RegExp(r'\W+'));
      int overlap = 0;
      for (final word in questionWords) {
        if (word.length > 2 && paragraphWords.contains(word)) {
          overlap++;
        }
      }
      return MapEntry(p, overlap);
    }).toList();

    scored.sort((a, b) => b.value.compareTo(a.value));
    final topParagraphs = scored.take(2).map((e) => e.key).toList();

    return topParagraphs.join('\n\n');
  }

  /// Regenerate the last answer
  Future<void> regenerateAnswer(String resumeText) async {
    if (_currentQuestion.isEmpty) return;
    await generateAnswer(_currentQuestion, resumeText);
  }

  /// Cancel current generation
  void cancelGeneration() {
    _state = LlmState.ready;
    notifyListeners();
  }

  /// Clear history
  void clearHistory() {
    _answerHistory.clear();
    _currentAnswer = '';
    _currentQuestion = '';
    notifyListeners();
  }

  /// Disconnect WebSocket
  void disconnect() {
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _sessionConfigured = false;
    _state = LlmState.disconnected;
    notifyListeners();
  }

  /// Reconnect if disconnected
  Future<void> reconnect() async {
    disconnect();
    await initialize();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
