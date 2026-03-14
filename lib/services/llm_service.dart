import 'dart:async';
import 'package:flutter/foundation.dart';
import 'storage_service.dart';

enum LlmState {
  unloaded,
  loading,
  ready,
  generating,
  error,
}

class LlmService extends ChangeNotifier {
  LlmState _state = LlmState.unloaded;
  String _currentAnswer = '';
  String _currentQuestion = '';
  final List<Map<String, String>> _answerHistory = [];
  bool _cancelRequested = false;
  String _errorMessage = '';

  LlmState get state => _state;
  String get currentAnswer => _currentAnswer;
  String get currentQuestion => _currentQuestion;
  List<Map<String, String>> get answerHistory => List.unmodifiable(_answerHistory);
  String get errorMessage => _errorMessage;
  bool get isGenerating => _state == LlmState.generating;

  /// Initialize: load Gemma-3-1B 4-bit GGUF model
  Future<bool> initialize() async {
    if (_state == LlmState.ready) return true;

    _state = LlmState.loading;
    notifyListeners();

    try {
      final modelPath = await StorageService.gemmaModelPath;
      final exists = await StorageService.gemmaModelExists();
      
      if (!exists) {
        debugPrint('[LlmService] Gemma model not found at $modelPath');
        _state = LlmState.error;
        _errorMessage = 'Model file not found';
        notifyListeners();
        return false;
      }

      // Load the GGUF model using flutter_llama
      // In production: LlamaModel.load(modelPath, nCtx: 2048, nGpuLayers: 32)
      _state = LlmState.ready;
      debugPrint('[LlmService] Gemma model loaded from $modelPath');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[LlmService] Init error: $e');
      _state = LlmState.error;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Generate answer for a detected interview question
  Future<void> generateAnswer(String question, String resumeText) async {
    if (_state != LlmState.ready && _state != LlmState.generating) return;

    // Cancel any in-progress generation
    if (_state == LlmState.generating) {
      _cancelRequested = true;
      await Future.delayed(const Duration(milliseconds: 100));
    }

    _cancelRequested = false;
    _state = LlmState.generating;
    _currentQuestion = question;
    _currentAnswer = '';
    notifyListeners();

    try {
      // Step 1: Context search — find most relevant resume paragraphs
      final relevantContext = _searchContext(question, resumeText);

      // Step 2: Build prompt
      final prompt = _buildPrompt(question, relevantContext);

      // Step 3: Simulate streaming generation
      // In production, this would call flutter_llama's generate method
      // with streaming callback for token-by-token output
      await _simulateStreaming(prompt);

      if (!_cancelRequested) {
        // Save to history
        _answerHistory.insert(0, {
          'question': question,
          'answer': _currentAnswer,
        });

        _state = LlmState.ready;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[LlmService] Generation error: $e');
      _state = LlmState.ready;
      _currentAnswer = 'Error generating answer. Please try again.';
      notifyListeners();
    }
  }

  /// Search resume for most relevant paragraphs using word overlap
  String _searchContext(String question, String resumeText) {
    if (resumeText.trim().isEmpty) {
      return 'No resume context provided.';
    }

    // Split resume into paragraphs
    final paragraphs = resumeText
        .split(RegExp(r'\n\s*\n'))
        .where((p) => p.trim().length > 20)
        .toList();

    if (paragraphs.isEmpty) return resumeText;

    // Score each paragraph against the question
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

    // Sort by score and take top 2
    scored.sort((a, b) => b.value.compareTo(a.value));
    final topParagraphs = scored.take(2).map((e) => e.key).toList();

    return topParagraphs.join('\n\n');
  }

  /// Build the LLM prompt
  String _buildPrompt(String question, String context) {
    return '''You are a confident, articulate interview coach helping someone answer interview questions naturally. Using ONLY the context below, write a 2-3 sentence answer. Sound human, specific, and confident. Do not add information not in the context.

Context:
$context

Interview Question: $question

Answer:''';
  }

  /// Simulate streaming output for demo purposes
  /// In production, this calls the actual LLM inference
  Future<void> _simulateStreaming(String prompt) async {
    // Demo response based on the question
    const demoResponse = 
        "At my previous role, I tackled a similar challenge by breaking it down "
        "into manageable components and leveraging my experience with the relevant "
        "technologies. I collaborated closely with my team to deliver a solution "
        "that exceeded expectations, resulting in measurable improvements in "
        "performance and user satisfaction. This experience reinforced my ability "
        "to work effectively under pressure while maintaining high code quality.";

    final words = demoResponse.split(' ');
    for (final word in words) {
      if (_cancelRequested) return;
      
      _currentAnswer += '${_currentAnswer.isEmpty ? '' : ' '}$word';
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 60));
    }
  }

  /// Regenerate the last answer
  Future<void> regenerateAnswer(String resumeText) async {
    if (_currentQuestion.isEmpty) return;
    await generateAnswer(_currentQuestion, resumeText);
  }

  /// Cancel current generation
  void cancelGeneration() {
    _cancelRequested = true;
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

  @override
  void dispose() {
    _cancelRequested = true;
    super.dispose();
  }
}
