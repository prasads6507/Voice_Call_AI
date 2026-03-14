import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'storage_service.dart';

enum LlmState {
  unloaded,
  connecting,
  ready,
  transcribing,
  error,
  disconnected,
}

class LlmService extends ChangeNotifier {
  LlmState _state = LlmState.unloaded;
  String _currentTranscription = '';
  String _errorMessage = '';
  String _apiKey = '';
  String _resumeText = '';

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _sessionConfigured = false;

  // Triggered when Gemini finishes transcribing a full question turn
  Function(String)? onQuestionComplete;

  // Gemini Live API config (Native Audio model for transcription)
  static const String _model = 'gemini-2.0-flash-exp';
  static const String _wsBaseUrl =
      'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent';

  LlmState get state => _state;
  String get currentTranscription => _currentTranscription;
  String get errorMessage => _errorMessage;
  bool get isConnected => _state == LlmState.ready || _state == LlmState.transcribing;

  /// Initialize: load API key and connect WebSocket
  Future<bool> initialize({String resumeText = ''}) async {
    if (_state == LlmState.ready || _state == LlmState.transcribing) return true;

    _state = LlmState.connecting;
    _resumeText = resumeText;
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

  void _sendSetupMessage() {
    final setupMsg = {
      'setup': {
        'model': 'models/$_model',
        'generationConfig': {
          'responseModalities': ['TEXT'],
        },
        'systemInstruction': {
          'parts': [
            {
              'text': 'You are an expert interview coach listening to a live phone screen. '
                  'The candidate\'s resume context is below.\n'
                  'When the interviewer finishes asking a question, immediately provide the transcribed question and a concise 2-3 sentence answer using the context.\n'
                  'Format EXACTLY like this:\n'
                  'Question: [transcript of the question]\n'
                  'Answer: [your suggested answer]\n\n'
                  'Resume Context:\n$_resumeText'
            }
          ]
        },
      }
    };

    _channel?.sink.add(jsonEncode(setupMsg));
    debugPrint('[LlmService] Sent session setup message (Coach mode)');
  }

  /// Feed raw PCM audio from the AudioTunnel
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

  void _onMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;

      if (data.containsKey('setupComplete')) {
        _sessionConfigured = true;
        _state = LlmState.ready;
        debugPrint('[LlmService] Gemini Live session configured');
        notifyListeners();
        return;
      }

      if (data.containsKey('serverContent')) {
        final serverContent = data['serverContent'] as Map<String, dynamic>;
        
        // Handle model turn text (we treat Gemini's "answers" to our system prompt as pure transcription)
        final modelTurn = serverContent['modelTurn'] as Map<String, dynamic>?;
        if (modelTurn != null) {
          final parts = modelTurn['parts'] as List<dynamic>?;
          if (parts != null) {
            for (final part in parts) {
              final textPart = (part as Map<String, dynamic>)['text'] as String?;
              if (textPart != null) {
                _state = LlmState.transcribing;
                _currentTranscription += textPart;
                notifyListeners();
              }
            }
          }
        }

        // Handle specific inputTranscription field if provided by this model version
        final inputTranscription = serverContent['inputTranscription'] as Map<String, dynamic>?;
        if (inputTranscription != null) {
           final parts = inputTranscription['parts'] as List<dynamic>?;
           if (parts != null) {
              for (final part in parts) {
                final textPart = (part as Map<String, dynamic>)['text'] as String?;
                if (textPart != null) {
                  _state = LlmState.transcribing;
                  _currentTranscription += textPart;
                  notifyListeners();
                }
              }
           }
        }

        final turnComplete = serverContent['turnComplete'] as bool? ?? false;
        if (turnComplete && _currentTranscription.trim().isNotEmpty) {
          debugPrint('[LlmService] Question complete: $_currentTranscription');
          onQuestionComplete?.call(_currentTranscription.trim());
          
          // Reset transcription for the next turn
          _currentTranscription = '';
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

  void clearSession() {
    _currentTranscription = '';
    _state = _sessionConfigured ? LlmState.ready : LlmState.unloaded;
    notifyListeners();
  }

  void disconnect() {
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _state = LlmState.unloaded;
    _sessionConfigured = false;
    notifyListeners();
  }
}
