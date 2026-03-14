import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../app_theme.dart';
import '../services/stt_service.dart';
import '../services/llm_service.dart';
import '../services/sip_service.dart';
import '../services/storage_service.dart';

/// A single chat message (question or answer)
class ChatMessage {
  final String text;
  final bool isQuestion; // true = caller question, false = AI answer
  final DateTime timestamp;
  bool isStreaming; // true while Gemini is still generating

  ChatMessage({
    required this.text,
    required this.isQuestion,
    DateTime? timestamp,
    this.isStreaming = false,
  }) : timestamp = timestamp ?? DateTime.now();
}

class ActiveCallScreen extends StatefulWidget {
  const ActiveCallScreen({super.key});

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen>
    with TickerProviderStateMixin {
  late SttService _sttService;
  late LlmService _llmService;
  late SipService _sipService;
  final ScrollController _scrollController = ScrollController();

  Timer? _durationTimer;
  Duration _callDuration = Duration.zero;
  String _resumeText = '';

  // Chat messages
  final List<ChatMessage> _messages = [];
  StreamSubscription<String>? _questionSubscription;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _startCallTimer();
    _loadResume();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sttService = Provider.of<SttService>(context, listen: false);
      _llmService = Provider.of<LlmService>(context, listen: false);
      _sipService = Provider.of<SipService>(context, listen: false);

      _initializeAI();
      _llmService.addListener(_onLlmUpdate);
      _sipService.addListener(_onSipUpdate);
    });
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _durationTimer?.cancel();
    _questionSubscription?.cancel();
    _llmService.removeListener(_onLlmUpdate);
    _sipService.removeListener(_onSipUpdate);
    _scrollController.dispose();
    super.dispose();
  }

  void _onSipUpdate() {
    if (!mounted) return;
    // If call ended externally
    if (_sipService.callState == CallState.ended ||
        _sipService.callState == CallState.idle) {
      _endCall();
    }
  }

  void _onLlmUpdate() {
    if (!mounted) return;

    // Find the last AI message (if any) and update it
    final lastAiIdx = _messages.lastIndexWhere((m) => !m.isQuestion);
    if (lastAiIdx >= 0 && _messages[lastAiIdx].isStreaming) {
      setState(() {
        _messages[lastAiIdx] = ChatMessage(
          text: _llmService.currentAnswer,
          isQuestion: false,
          timestamp: _messages[lastAiIdx].timestamp,
          isStreaming: _llmService.isGenerating,
        );
      });
    } else if (_llmService.isGenerating && _llmService.currentAnswer.isNotEmpty) {
      // New answer started
      setState(() {
        _messages.add(ChatMessage(
          text: _llmService.currentAnswer,
          isQuestion: false,
          isStreaming: true,
        ));
      });
    }

    _scrollToBottom();
  }

  Future<void> _loadResume() async {
    _resumeText = await StorageService.getResume();
  }

  Future<void> _initializeAI() async {
    await _sttService.initialize();
    await _llmService.initialize();

    // Subscribe to detected questions from STT
    _questionSubscription = _sttService.questionStream?.listen((question) {
      debugPrint('[ActiveCall] Question detected: $question');
      setState(() {
        _messages.add(ChatMessage(text: question, isQuestion: true));
      });
      _scrollToBottom();
      // Send to Gemini
      _llmService.generateAnswer(question, _resumeText);
    });

    _sttService.startListening();
    if (mounted) setState(() {});
  }

  void _startCallTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _callDuration += const Duration(seconds: 1));
      }
    });
  }

  String get _formattedDuration {
    final minutes = _callDuration.inMinutes.remainder(60);
    final seconds = _callDuration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 80), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _endCall() {
    _durationTimer?.cancel();
    _sttService.stopListening();
    _llmService.clearSession();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B14),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(),
            // Chat messages
            Expanded(child: _buildChatList()),
            // Bottom bar
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D18),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: _endCall,
            child: const Icon(Icons.arrow_back_ios, size: 18, color: AppTheme.textSecondary),
          ),
          const SizedBox(width: 10),
          // Caller avatar
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.accentGreen, AppTheme.accent],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.phone_in_talk, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          // Caller info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _sipService.callerNumber.isNotEmpty
                      ? _sipService.callerNumber
                      : 'Interview Call',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _formattedDuration,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          // Gemini status chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _llmService.isConnected
                  ? AppTheme.accentGreen.withValues(alpha: 0.15)
                  : AppTheme.accentRed.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _llmService.isConnected ? AppTheme.accentGreen : AppTheme.accentRed,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  _llmService.isConnected ? 'Gemini' : 'Offline',
                  style: TextStyle(
                    fontSize: 11,
                    color: _llmService.isConnected ? AppTheme.accentGreen : AppTheme.accentRed,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatList() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 48, color: AppTheme.textMuted.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text(
              'Listening for conversation...',
              style: TextStyle(fontSize: 15, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 4),
            Text(
              'Questions & AI answers will appear here',
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted.withValues(alpha: 0.6)),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        return _buildChatBubble(msg);
      },
    );
  }

  Widget _buildChatBubble(ChatMessage msg) {
    final isQ = msg.isQuestion;

    return Align(
      alignment: isQ ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        margin: EdgeInsets.only(
          bottom: 10,
          left: isQ ? 0 : 36,
          right: isQ ? 36 : 0,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isQ
              ? const Color(0xFF1A1A2E)
              : AppTheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isQ ? const Radius.circular(4) : const Radius.circular(16),
            bottomRight: isQ ? const Radius.circular(16) : const Radius.circular(4),
          ),
          border: Border.all(
            color: isQ
                ? Colors.white.withValues(alpha: 0.06)
                : AppTheme.primary.withValues(alpha: 0.15),
          ),
        ),
        child: Column(
          crossAxisAlignment: isQ ? CrossAxisAlignment.start : CrossAxisAlignment.start,
          children: [
            // Label
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isQ ? Icons.mic : Icons.auto_awesome,
                  size: 12,
                  color: isQ ? AppTheme.accent : AppTheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  isQ ? 'Caller' : 'Gemini',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isQ ? AppTheme.accent : AppTheme.primary,
                  ),
                ),
                if (msg.isStreaming) ...[
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: AppTheme.primary,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            // Message text
            Text(
              msg.text,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                color: isQ ? AppTheme.textPrimary : AppTheme.textPrimary,
              ),
            ),
            // Timestamp
            const SizedBox(height: 4),
            Text(
              '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 10,
                color: AppTheme.textMuted.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D18),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ControlBtn(
            icon: _sipService.isMuted ? Icons.mic_off : Icons.mic_none,
            label: _sipService.isMuted ? 'Unmute' : 'Mute',
            isActive: _sipService.isMuted,
            color: AppTheme.accentRed,
            onTap: () async {
              await _sipService.toggleMute();
              setState(() {});
            },
          ),
          _ControlBtn(
            icon: _sipService.isSpeakerOn ? Icons.volume_up : Icons.volume_off,
            label: 'Speaker',
            isActive: _sipService.isSpeakerOn,
            color: AppTheme.accent,
            onTap: () async {
              await _sipService.toggleSpeaker();
              setState(() {});
            },
          ),
          _ControlBtn(
            icon: Icons.call_end,
            label: 'End',
            isActive: true,
            color: AppTheme.accentRed,
            isEndCall: true,
            onTap: () async {
              await _sipService.endCall();
              _endCall();
            },
          ),
        ],
      ),
    );
  }
}

class _ControlBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color color;
  final VoidCallback onTap;
  final bool isEndCall;

  const _ControlBtn({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.color,
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
                      ? color.withValues(alpha: 0.2)
                      : AppTheme.surfaceDarkElevated,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isActive
                    ? color.withValues(alpha: 0.4)
                    : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Icon(
              icon,
              color: isEndCall ? Colors.white : color,
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
