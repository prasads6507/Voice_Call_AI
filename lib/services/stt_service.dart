import 'dart:async';

import 'package:flutter/foundation.dart';
import 'storage_service.dart';

/// Question detection keywords
const List<String> questionKeywords = [
  'tell me about',
  'describe a time',
  'how would you',
  'what is your',
  'explain how',
  'walk me through',
  'what experience',
  'can you describe',
  'why did you',
  'how do you',
  'what are your',
  'give me an example',
  'when have you',
  'what would you do',
  'how did you',
];

class SttService extends ChangeNotifier {
  bool _isInitialized = false;
  bool _isListening = false;
  String _currentTranscription = '';
  String _fullTranscription = '';
  List<String> _recentSentences = [];
  StreamController<String>? _questionController;

  bool get isInitialized => _isInitialized;
  bool get isListening => _isListening;
  String get currentTranscription => _currentTranscription;
  String get fullTranscription => _fullTranscription;
  List<String> get recentSentences => List.unmodifiable(_recentSentences);
  Stream<String>? get questionStream => _questionController?.stream;

  /// Initialize Whisper model
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      final modelPath = await StorageService.whisperModelPath;
      final exists = await StorageService.whisperModelExists();
      
      if (!exists) {
        debugPrint('[SttService] Whisper model not found at $modelPath');
        return false;
      }

      // Initialize whisper_flutter_new
      // Note: Actual Whisper initialization depends on the package API
      // The model file is loaded from the local path
      _isInitialized = true;
      _questionController = StreamController<String>.broadcast();
      debugPrint('[SttService] Whisper initialized from $modelPath');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[SttService] Init error: $e');
      return false;
    }
  }

  /// Start listening to audio stream from call
  void startListening() {
    if (!_isInitialized) return;
    _isListening = true;
    _currentTranscription = '';
    _fullTranscription = '';
    _recentSentences = [];
    notifyListeners();
    
    // In a real implementation, this would:
    // 1. Capture audio from the SIP call's incoming audio stream
    // 2. Buffer 2-second chunks
    // 3. Send chunks to Whisper in a separate isolate
    // 4. Receive transcribed text back
    _startTranscriptionLoop();
  }

  void _startTranscriptionLoop() {
    // Simulated loop - in production, this feeds audio buffers to Whisper
    debugPrint('[SttService] Transcription loop started');
  }

  /// Process a transcribed text segment
  void processTranscription(String text) {
    if (text.isEmpty) return;

    _currentTranscription += ' $text';
    _currentTranscription = _currentTranscription.trim();
    _fullTranscription += ' $text';
    _fullTranscription = _fullTranscription.trim();

    // Update recent sentences (keep last 4)
    final sentences = _splitSentences(_currentTranscription);
    if (sentences.length > 4) {
      _recentSentences = sentences.sublist(sentences.length - 4);
    } else {
      _recentSentences = sentences;
    }

    // Check for question trigger
    _detectQuestion(text);
    notifyListeners();
  }

  void _detectQuestion(String text) {
    final lowerText = _currentTranscription.toLowerCase();
    
    bool isQuestion = false;

    // Check: ends with ?
    if (lowerText.trimRight().endsWith('?')) {
      isQuestion = true;
    }

    // Check: contains question keywords
    if (!isQuestion) {
      for (final keyword in questionKeywords) {
        if (lowerText.contains(keyword)) {
          isQuestion = true;
          break;
        }
      }
    }

    // Check: 10+ words and ends with a natural pause
    if (!isQuestion) {
      final words = _currentTranscription.trim().split(' ');
      if (words.length >= 10) {
        // Natural pause detection would use audio silence detection
        // For now, check if the sentence seems complete
        final lastChar = _currentTranscription.trim();
        if (lastChar.endsWith('.') || lastChar.endsWith(',')) {
          isQuestion = true;
        }
      }
    }

    if (isQuestion && _currentTranscription.trim().length > 15) {
      final question = _extractLastQuestion(_currentTranscription);
      if (question.isNotEmpty) {
        _questionController?.add(question);
        debugPrint('[SttService] Question detected: $question');
        // Reset current transcription for next question
        _currentTranscription = '';
      }
    }
  }

  String _extractLastQuestion(String text) {
    // Find the last complete sentence/question
    final sentences = _splitSentences(text);
    if (sentences.isEmpty) return text.trim();
    
    // Return the last meaningful sentence
    for (int i = sentences.length - 1; i >= 0; i--) {
      if (sentences[i].trim().length > 10) {
        return sentences[i].trim();
      }
    }
    return sentences.last.trim();
  }

  List<String> _splitSentences(String text) {
    return text
        .split(RegExp(r'[.!?]+'))
        .where((s) => s.trim().isNotEmpty)
        .map((s) => s.trim())
        .toList();
  }

  /// Stop listening
  void stopListening() {
    _isListening = false;
    notifyListeners();
  }

  /// Clear all transcription data
  void clear() {
    _currentTranscription = '';
    _fullTranscription = '';
    _recentSentences = [];
    notifyListeners();
  }

  @override
  void dispose() {
    _questionController?.close();
    super.dispose();
  }
}
