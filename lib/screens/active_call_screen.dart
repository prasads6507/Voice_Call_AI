import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app_theme.dart';
import '../services/llm_service.dart';
import '../services/sip_service.dart';
import '../services/storage_service.dart';
import '../services/audio_tunnel_service.dart';

class ChatMessage {
  final String text;
  final bool isAiCoach; // true = AI Coach output
  final DateTime timestamp;
  bool isStreaming;

  ChatMessage({
    required this.text,
    required this.isAiCoach,
    DateTime? timestamp,
    this.isStreaming = false,
  }) : timestamp = timestamp ?? DateTime.now();
}

class ActiveCallScreen extends StatefulWidget {
  const ActiveCallScreen({super.key});

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  late LlmService _transcriptionEngine;
  late SipService _sipService;
  final AudioTunnelService _audioTunnel = AudioTunnelService();
  final ScrollController _scrollController = ScrollController();

  Timer? _durationTimer;
  Duration _callDuration = Duration.zero;
  String _resumeText = '';

  // Chat messages
  final List<ChatMessage> _messages = [];

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _startCallTimer();
    _loadResume();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _transcriptionEngine = Provider.of<LlmService>(context, listen: false);
      _sipService = Provider.of<SipService>(context, listen: false);

      _initializeAI();
      _transcriptionEngine.addListener(_onTranscriptionUpdate);
      _sipService.addListener(_onSipUpdate);
    });
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _durationTimer?.cancel();
    _audioTunnel.stopTunnel();
    _audioTunnel.dispose();
    _transcriptionEngine.removeListener(_onTranscriptionUpdate);
    _sipService.removeListener(_onSipUpdate);
    _scrollController.dispose();
    super.dispose();
  }

  void _onSipUpdate() {
    if (!mounted) return;
    if (_sipService.callState == CallState.ended ||
        _sipService.callState == CallState.idle) {
      _endCall();
    }
  }

  void _onTranscriptionUpdate() {
    if (!mounted) return;
    
    final currentTrans = _transcriptionEngine.currentTranscription;
    if (currentTrans.isNotEmpty) {
      if (_messages.isEmpty || !_messages.last.isStreaming) {
        setState(() {
          _messages.add(ChatMessage(
            text: currentTrans,
            isAiCoach: true,
            isStreaming: true,
          ));
        });
      } else {
        setState(() {
          _messages[_messages.length - 1] = ChatMessage(
            text: currentTrans,
            isAiCoach: true,
            timestamp: _messages.last.timestamp,
            isStreaming: _transcriptionEngine.state == LlmState.transcribing,
          );
        });
      }
      _scrollToBottom();
    }
  }

  void _onQuestionComplete(String fullQuestion) {
    if (!mounted) return;
    
    setState(() {
      if (_messages.isNotEmpty && _messages.last.isStreaming) {
        _messages.last.isStreaming = false;
      }
    });
  }

  Future<void> _loadResume() async {
    _resumeText = await StorageService.getResume();
  }

  Future<void> _initializeAI() async {
    await _transcriptionEngine.initialize(resumeText: _resumeText);
    
    // Wire up completion callback
    _transcriptionEngine.onQuestionComplete = _onQuestionComplete;

    // Start Audio Tunnel
    await _audioTunnel.startTunnel((pcmChunk) {
      _transcriptionEngine.sendAudioChunk(pcmChunk);
    });

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
    _audioTunnel.stopTunnel();
    _transcriptionEngine.clearSession();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildChatList()),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _endCall,
            child: const Icon(Icons.arrow_back_ios, size: 20, color: AppTheme.textSecondary),
          ),
          const SizedBox(width: 12),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.phone_in_talk, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _sipService.callerNumber.isNotEmpty
                      ? _sipService.callerNumber
                      : 'Interview Call',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _formattedDuration,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textMuted,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          // Tunnel Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _audioTunnel.isRecording
                  ? AppTheme.accentGreen.withOpacity(0.12)
                  : AppTheme.accentRed.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _audioTunnel.isRecording ? AppTheme.accentGreen : AppTheme.accentRed,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _audioTunnel.isRecording ? 'Listening' : 'Muted',
                  style: TextStyle(
                    fontSize: 12,
                    color: _audioTunnel.isRecording ? AppTheme.accentGreen : AppTheme.accentRed,
                    fontWeight: FontWeight.bold,
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
            Icon(Icons.forum_outlined, size: 56, color: AppTheme.textMuted.withOpacity(0.3)),
            const SizedBox(height: 16),
            const Text(
              'Listening for conversation...',
              style: TextStyle(fontSize: 16, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 6),
            Text(
              'Questions will be transcribed securely.',
              style: TextStyle(fontSize: 14, color: AppTheme.textMuted.withOpacity(0.8)),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        return _buildChatBubble(msg);
      },
    );
  }

  Widget _buildChatBubble(ChatMessage msg) {
    // All AI Coach messages rendered as AI on the right, but spanning most of width
    final isQ = !msg.isAiCoach;

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        margin: const EdgeInsets.only(
          bottom: 12,
          left: 16,
          right: 0,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.primary.withOpacity(0.08),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.0),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(
            color: AppTheme.primary.withOpacity(0.15),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.auto_awesome,
                  size: 14,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 6),
                const Text(
                  'Interview Coach',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
                if (msg.isStreaming) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primary,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              msg.text,
              style: const TextStyle(
                fontSize: 16,
                height: 1.4,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.textMuted.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
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
            color: AppTheme.primary,
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
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isEndCall
                  ? AppTheme.accentRed
                  : isActive
                      ? color.withOpacity(0.1)
                      : AppTheme.surfaceLightElevated,
              shape: BoxShape.circle,
              border: Border.all(
                color: isEndCall 
                    ? AppTheme.accentRed 
                    : isActive
                        ? color.withOpacity(0.3)
                        : Colors.transparent,
                width: 2,
              ),
            ),
            child: Icon(
              icon,
              color: isEndCall ? Colors.white : (isActive ? color : AppTheme.textSecondary),
              size: 26,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isEndCall ? AppTheme.accentRed : AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
