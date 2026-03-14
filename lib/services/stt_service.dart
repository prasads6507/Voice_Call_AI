import 'dart:async';

import 'package:flutter/foundation.dart';

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

  // sherpa_onnx recognizer placeholder
  // In production: OnlineRecognizer from sherpa_onnx
  dynamic _recognizer;

  bool get isInitialized => _isInitialized;
  bool get isListening => _isListening;
  String get currentTranscription => _currentTranscription;
  String get fullTranscription => _fullTranscription;
  List<String> get recentSentences => List.unmodifiable(_recentSentences);
  Stream<String>? get questionStream => _questionController?.stream;

  /// Initialize Moonshine STT model (bundled, no download needed)
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      // TODO: Initialize sherpa_onnx OnlineRecognizer with Moonshine v2 model
      // The model files will be bundled as Flutter assets
      // Example:
      // final config = OnlineRecognizerConfig(
      //   model: OnlineModelConfig(
      //     moonshine: OnlineMoonshineModelConfig(
      //       preprocessor: 'assets/models/moonshine-tiny-preprocess.onnx',
      //       encoder: 'assets/models/moonshine-tiny-encode.onnx',
      //       uncachedDecoder: 'assets/models/moonshine-tiny-uncached-decode.onnx',
      //       cachedDecoder: 'assets/models/moonshine-tiny-cached-decode.onnx',
      //     ),
      //     tokens: 'assets/models/tokens.txt',
      //   ),
      //   enableEndpoint: true,
      // );
      // _recognizer = OnlineRecognizer(config);

      _isInitialized = true;
      _questionController = StreamController<String>.broadcast();
      debugPrint('[SttService] Moonshine STT initialized (on-device)');
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
    
    debugPrint('[SttService] Moonshine transcription started');
  }

  /// Feed PCM audio samples to Moonshine recognizer
  /// [samples] should be 16kHz, 16-bit PCM as Float32List
  void feedAudioSamples(List<double> samples) {
    if (!_isInitialized || !_isListening) return;

    // TODO: Feed samples to sherpa_onnx recognizer
    // _recognizer.acceptWaveform(samples, sampleRate: 16000);
    // 
    // // Check for partial/final results
    // while (_recognizer.isReady()) {
    //   _recognizer.decode();
    // }
    // final result = _recognizer.getResult();
    // if (result.text.isNotEmpty) {
    //   processTranscription(result.text);
    //   if (_recognizer.isEndpoint()) {
    //     _recognizer.reset();
    //   }
    // }
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
    final sentences = _splitSentences(text);
    if (sentences.isEmpty) return text.trim();
    
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
    // TODO: _recognizer?.free();
    super.dispose();
  }
}
