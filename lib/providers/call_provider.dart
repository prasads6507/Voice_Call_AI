import 'dart:async';
import 'package:flutter/foundation.dart';

class CallProvider extends ChangeNotifier {
  // Call state
  bool _isActive = false;
  String _callerNumber = '';
  Duration _callDuration = Duration.zero;
  Timer? _durationTimer;

  // Transcription
  String _liveTranscription = '';
  final List<String> _transcriptionHistory = [];

  // AI Answer
  String _currentAnswer = '';
  String _currentQuestion = '';
  bool _isGenerating = false;
  final List<Map<String, String>> _answerHistory = [];

  // Getters
  bool get isActive => _isActive;
  String get callerNumber => _callerNumber;
  Duration get callDuration => _callDuration;
  String get liveTranscription => _liveTranscription;
  List<String> get transcriptionHistory => List.unmodifiable(_transcriptionHistory);
  String get currentAnswer => _currentAnswer;
  String get currentQuestion => _currentQuestion;
  bool get isGenerating => _isGenerating;
  List<Map<String, String>> get answerHistory => List.unmodifiable(_answerHistory);

  String get formattedDuration {
    final hours = _callDuration.inHours;
    final minutes = _callDuration.inMinutes.remainder(60);
    final seconds = _callDuration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void startCall(String number) {
    _isActive = true;
    _callerNumber = number;
    _callDuration = Duration.zero;
    _liveTranscription = '';
    _currentAnswer = '';
    _currentQuestion = '';
    _isGenerating = false;
    _transcriptionHistory.clear();
    _answerHistory.clear();

    _durationTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        _callDuration += const Duration(seconds: 1);
        notifyListeners();
      },
    );
    notifyListeners();
  }

  void endCall() {
    _isActive = false;
    _durationTimer?.cancel();
    notifyListeners();
  }

  void updateTranscription(String text) {
    _liveTranscription = text;
    notifyListeners();
  }

  void addTranscriptionSegment(String segment) {
    _transcriptionHistory.add(segment);
    if (_transcriptionHistory.length > 20) {
      _transcriptionHistory.removeAt(0);
    }
    _liveTranscription = segment;
    notifyListeners();
  }

  void updateAnswer(String answer) {
    _currentAnswer = answer;
    notifyListeners();
  }

  void setQuestion(String question) {
    _currentQuestion = question;
    notifyListeners();
  }

  void setGenerating(bool generating) {
    _isGenerating = generating;
    notifyListeners();
  }

  void addAnswerToHistory(String question, String answer) {
    _answerHistory.insert(0, {
      'question': question,
      'answer': answer,
    });
    notifyListeners();
  }

  void reset() {
    _isActive = false;
    _callerNumber = '';
    _callDuration = Duration.zero;
    _durationTimer?.cancel();
    _liveTranscription = '';
    _currentAnswer = '';
    _currentQuestion = '';
    _isGenerating = false;
    _transcriptionHistory.clear();
    _answerHistory.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    super.dispose();
  }
}
