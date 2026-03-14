import 'dart:async';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../app_theme.dart';

import '../services/stt_service.dart';
import '../services/llm_service.dart';
import '../services/storage_service.dart';
import '../widgets/streaming_text.dart';

class ActiveCallScreen extends StatefulWidget {
  const ActiveCallScreen({super.key});

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  final SttService _sttService = SttService();
  final LlmService _llmService = LlmService();
  final ScrollController _transcriptionScrollController = ScrollController();
  final ScrollController _answerScrollController = ScrollController();

  Timer? _durationTimer;
  Duration _callDuration = Duration.zero;
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  final String _callerNumber = '+1 (415) 234 5678';
  String _resumeText = '';

  // Transcription state
  final List<String> _transcriptionSegments = [];
  String _currentTranscription = '';

  // Demo mode
  final bool _demoMode = true;
  int _demoStep = 0;
  Timer? _demoTimer;
  
  final List<String> _demoQuestions = [
    'Can you walk me through a time you had to debug a complex production issue under pressure?',
    'What is your experience with microservices architecture?',
    'How would you handle a situation where you disagree with your team lead on a technical decision?',
  ];

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _startCallTimer();
    _loadResume();
    _initializeAI();
    
    // Start demo after a brief delay
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _demoMode) _runDemo();
    });

    _llmService.addListener(_onLlmUpdate);
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _durationTimer?.cancel();
    _demoTimer?.cancel();
    _llmService.removeListener(_onLlmUpdate);
    _transcriptionScrollController.dispose();
    _answerScrollController.dispose();
    super.dispose();
  }

  void _onLlmUpdate() {
    setState(() {});
    _scrollToBottom(_answerScrollController);
  }

  Future<void> _loadResume() async {
    _resumeText = await StorageService.getResume();
  }

  Future<void> _initializeAI() async {
    await _sttService.initialize();
    await _llmService.initialize();
  }

  void _startCallTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _callDuration += const Duration(seconds: 1);
      });
    });
  }

  String get _formattedDuration {
    final hours = _callDuration.inHours;
    final minutes = _callDuration.inMinutes.remainder(60);
    final seconds = _callDuration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _runDemo() {
    if (_demoStep >= _demoQuestions.length) return;
    
    final question = _demoQuestions[_demoStep];
    final words = question.split(' ');
    int wordIndex = 0;

    _demoTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (wordIndex < words.length) {
        setState(() {
          _currentTranscription += '${wordIndex == 0 ? '' : ' '}${words[wordIndex]}';
        });
        _scrollToBottom(_transcriptionScrollController);
        wordIndex++;
      } else {
        timer.cancel();
        // Question complete — add to segments and generate answer
        _transcriptionSegments.add(_currentTranscription);
        _currentTranscription = '';
        
        // Generate AI answer
        _llmService.generateAnswer(question, _resumeText);
        
        // Schedule next demo question
        _demoStep++;
        if (_demoStep < _demoQuestions.length) {
          Future.delayed(const Duration(seconds: 8), () {
            if (mounted) _runDemo();
          });
        }
      }
    });
  }

  void _scrollToBottom(ScrollController controller) {
    if (controller.hasClients) {
      Future.delayed(const Duration(milliseconds: 50), () {
        controller.animateTo(
          controller.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080810),
      body: SafeArea(
        child: Column(
          children: [
            // Call Header
            _buildCallHeader(),
            // Control Buttons
            _buildControls(),
            const Divider(height: 1, color: Color(0xFF1A1A2E)),
            // Transcription Panel
            Expanded(flex: 4, child: _buildTranscriptionPanel()),
            const Divider(height: 1, color: Color(0xFF1A1A2E)),
            // Answer Panel
            Expanded(flex: 5, child: _buildAnswerPanel()),
          ],
        ),
      ),
    );
  }

  Widget _buildCallHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      color: const Color(0xFF0A0A16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.accentGreen.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.phone_in_talk,
              color: AppTheme.accentGreen,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Interview Call',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  _callerNumber,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.surfaceDarkElevated,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '⏱ $_formattedDuration',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: const Color(0xFF0A0A16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ControlButton(
            icon: _isMuted ? Icons.mic_off : Icons.mic_none,
            label: _isMuted ? 'Unmute' : 'Mute',
            isActive: _isMuted,
            activeColor: AppTheme.accentRed,
            onTap: () => setState(() => _isMuted = !_isMuted),
          ),
          _ControlButton(
            icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_off,
            label: 'Speaker',
            isActive: _isSpeakerOn,
            activeColor: AppTheme.accent,
            onTap: () => setState(() => _isSpeakerOn = !_isSpeakerOn),
          ),
          _ControlButton(
            icon: Icons.call_end,
            label: 'End',
            isActive: true,
            activeColor: AppTheme.accentRed,
            isEndCall: true,
            onTap: () {
              _demoTimer?.cancel();
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptionPanel() {
    return Container(
      width: double.infinity,
      color: const Color(0xFF0D0D18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(Icons.mic, size: 16, color: AppTheme.accent),
                const SizedBox(width: 6),
                Text(
                  'INTERVIEWER',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.accent,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: _transcriptionScrollController,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                // Previous segments (dimmer)
                for (int i = 0; i < _transcriptionSegments.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '"${_transcriptionSegments[i]}"',
                      style: TextStyle(
                        fontSize: 17,
                        height: 1.5,
                        color: i == _transcriptionSegments.length - 1
                            ? AppTheme.textPrimary
                            : AppTheme.textMuted,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                // Current live transcription
                if (_currentTranscription.isNotEmpty)
                  Text(
                    '"$_currentTranscription"',
                    style: const TextStyle(
                      fontSize: 17,
                      height: 1.5,
                      color: AppTheme.textPrimary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                if (_transcriptionSegments.isEmpty &&
                    _currentTranscription.isEmpty)
                  Text(
                    'Listening for questions...',
                    style: TextStyle(
                      fontSize: 15,
                      color: AppTheme.textMuted,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerPanel() {
    return Container(
      width: double.infinity,
      color: const Color(0xFF0A0A14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(Icons.smart_toy, size: 16, color: AppTheme.primary),
                const SizedBox(width: 6),
                Text(
                  'YOUR ANSWER',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                if (_llmService.isGenerating)
                  Row(
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'generating...',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.primary.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: _answerScrollController,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                // Answer history
                for (final entry in _llmService.answerHistory.reversed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Q: ${entry['question']}',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textMuted,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          entry['answer'] ?? '',
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.5,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        Divider(
                          height: 20,
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                      ],
                    ),
                  ),
                // Current answer (streaming)
                if (_llmService.currentAnswer.isNotEmpty)
                  StreamingText(
                    text: _llmService.currentAnswer,
                    isGenerating: _llmService.isGenerating,
                  ),
                if (_llmService.currentAnswer.isEmpty &&
                    _llmService.answerHistory.isEmpty)
                  Text(
                    'AI answers will appear here as questions are detected...',
                    style: TextStyle(
                      fontSize: 15,
                      color: AppTheme.textMuted,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),

          // Regenerate button
          if (_llmService.currentAnswer.isNotEmpty && !_llmService.isGenerating)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    _llmService.regenerateAnswer(_resumeText);
                  },
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Regenerate Answer'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: BorderSide(
                      color: AppTheme.primary.withValues(alpha: 0.3),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onTap;
  final bool isEndCall;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
    this.isEndCall = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isEndCall
                  ? AppTheme.accentRed
                  : isActive
                      ? activeColor.withValues(alpha: 0.2)
                      : AppTheme.surfaceDarkElevated,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isActive
                    ? activeColor.withValues(alpha: 0.4)
                    : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Icon(
              icon,
              color: isEndCall ? Colors.white : activeColor,
              size: 24,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isEndCall ? AppTheme.accentRed : AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
