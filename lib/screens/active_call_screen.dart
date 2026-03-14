import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app_theme.dart';
import '../services/llm_service.dart';
import '../services/sip_service.dart';
import '../services/storage_service.dart';
import '../services/audio_tunnel_service.dart';

enum _MsgType { callerQuestion, aiAnswer }

class _Msg {
  final _MsgType type;
  String text;
  final DateTime ts;
  bool streaming;
  _Msg({required this.type, required this.text, this.streaming = false})
      : ts = DateTime.now();
}

class ActiveCallScreen extends StatefulWidget {
  const ActiveCallScreen({super.key});
  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  LlmService? _llm;
  SipService? _sip;
  final AudioTunnelService _audio = AudioTunnelService();
  final ScrollController _scroll = ScrollController();

  Timer? _timer;
  Duration _elapsed = Duration.zero;
  String _resume = '';
  final List<_Msg> _msgs = [];

  // Prevents double Navigator.pop → black screen crash
  bool _didHangUp = false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _startTimer();
    _loadAndStart();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _timer?.cancel();
    _audio.stopTunnel();
    _audio.dispose();
    _scroll.dispose();
    if (_llm != null) {
      _llm!.onCallerSpeechUpdate = null;
      _llm!.onAIAnswerStreaming = null;
      _llm!.onTurnComplete = null;
      _llm!.removeListener(_onLlmChange);
    }
    _sip?.removeListener(_onSipChange);
    super.dispose();
  }

  // ── Init ────────────────────────────────────────────────────────

  Future<void> _loadAndStart() async {
    _resume = await StorageService.getResume();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _llm = Provider.of<LlmService>(context, listen: false);
      _sip = Provider.of<SipService>(context, listen: false);
      _sip!.addListener(_onSipChange);
      _llm!.addListener(_onLlmChange);
      _wireCallbacks();
      await _llm!.initialize(resumeText: _resume);
      await _audio.startTunnel((chunk) => _llm?.sendAudioChunk(chunk));
      if (mounted) setState(() {});
    });
  }

  // Retry without ending the call
  Future<void> _retryConnection() async {
    if (_llm == null) return;
    _msgs.clear();
    _llm!.disconnect();
    await Future.delayed(const Duration(milliseconds: 300));
    await _llm!.initialize(resumeText: _resume);
    if (mounted) setState(() {});
  }

  void _wireCallbacks() {
    if (_llm == null) return;

    _llm!.onCallerSpeechUpdate = (String text) {
      if (!mounted) return;
      setState(() {
        final last = _msgs.isNotEmpty ? _msgs.last : null;
        if (last != null && last.streaming && last.type == _MsgType.callerQuestion) {
          last.text = text;
        } else {
          _msgs.add(_Msg(type: _MsgType.callerQuestion, text: text, streaming: true));
        }
      });
      _scrollDown();
    };

    _llm!.onAIAnswerStreaming = (String text) {
      if (!mounted) return;
      setState(() {
        if (_msgs.isNotEmpty && _msgs.last.streaming &&
            _msgs.last.type == _MsgType.callerQuestion) {
          _msgs.last.streaming = false;
        }
        if (_msgs.isNotEmpty && _msgs.last.streaming &&
            _msgs.last.type == _MsgType.aiAnswer) {
          _msgs.last.text = text;
        } else {
          _msgs.add(_Msg(type: _MsgType.aiAnswer, text: text, streaming: true));
        }
      });
      _scrollDown();
    };

    _llm!.onTurnComplete = (_, __) {
      if (!mounted) return;
      setState(() {
        if (_msgs.isNotEmpty && _msgs.last.streaming) {
          _msgs.last.streaming = false;
        }
      });
    };
  }

  // ── Listeners ───────────────────────────────────────────────────

  void _onSipChange() {
    if (!mounted) return;
    setState(() {});
    final cs = _sip?.callState;
    if (cs == CallState.ended || cs == CallState.idle) _hangUp();
  }

  void _onLlmChange() {
    if (mounted) setState(() {});
  }

  // ── Timer ────────────────────────────────────────────────────────

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  String get _dur {
    final m = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _scrollDown() {
    if (!_scroll.hasClients) return;
    Future.delayed(const Duration(milliseconds: 60), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  // ── Hang up (double-pop safe) ───────────────────────────────────

  void _hangUp() {
    if (_didHangUp) return;
    _didHangUp = true;
    _timer?.cancel();
    _audio.stopTunnel();
    _llm?.clearSession();
    if (mounted) Navigator.of(context).pop();
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      body: SafeArea(
        child: Column(children: [
          _header(),
          Expanded(child: _chat()),
          _controls(),
        ]),
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────

  Widget _header() {
    final s = _llm?.state ?? LlmState.connecting;
    Color badgeColor;
    String badgeLabel;
    bool spin;
    switch (s) {
      case LlmState.error:
        badgeColor = AppTheme.accentRed;
        badgeLabel = 'Error';
        spin = false;
      case LlmState.generating:
        badgeColor = AppTheme.primary;
        badgeLabel = 'Coaching…';
        spin = true;
      case LlmState.transcribing:
        badgeColor = Colors.orange;
        badgeLabel = 'Hearing…';
        spin = true;
      case LlmState.ready:
        badgeColor = AppTheme.accentGreen;
        badgeLabel = 'Listening';
        spin = false;
      default:
        badgeColor = AppTheme.textMuted;
        badgeLabel = 'Connecting…';
        spin = true;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Row(children: [
        GestureDetector(
          onTap: () => showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Leave call view?'),
              content: const Text('AI coaching pauses. The call continues. Use End Call to fully hang up.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Stay')),
                TextButton(onPressed: () { Navigator.pop(context); if (mounted) Navigator.pop(context); }, child: const Text('Leave')),
              ],
            ),
          ),
          child: const Icon(Icons.arrow_back_ios, size: 20, color: AppTheme.textSecondary),
        ),
        const SizedBox(width: 12),
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(gradient: AppTheme.primaryGradient, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.phone_in_talk, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              _sip?.callerNumber.isNotEmpty == true ? _sip!.callerNumber : 'Interview Call',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
            Text(_dur, style: const TextStyle(fontSize: 13, color: AppTheme.textMuted, fontFamily: 'monospace')),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: badgeColor.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            spin
                ? SizedBox(width: 8, height: 8, child: CircularProgressIndicator(strokeWidth: 1.5, color: badgeColor))
                : Container(width: 6, height: 6, decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(badgeLabel, style: TextStyle(fontSize: 12, color: badgeColor, fontWeight: FontWeight.bold)),
          ]),
        ),
      ]),
    );
  }

  // ── Chat ─────────────────────────────────────────────────────────

  Widget _chat() {
    if (_msgs.isEmpty) {
      final s = _llm?.state ?? LlmState.connecting;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.hearing_outlined, size: 56, color: AppTheme.textMuted.withOpacity(0.3)),
            const SizedBox(height: 16),
            const Text('Listening for the interviewer…',
                style: TextStyle(fontSize: 16, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Questions appear here as they\'re asked.\nYour AI coach responds instantly.',
              style: TextStyle(fontSize: 14, color: AppTheme.textMuted.withOpacity(0.7), height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (s == LlmState.connecting)
              Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary.withOpacity(0.5))),
                const SizedBox(width: 8),
                Text('Connecting AI…', style: TextStyle(fontSize: 13, color: AppTheme.textMuted.withOpacity(0.8))),
              ]),
            if (s == LlmState.error) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.accentRed.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.accentRed.withOpacity(0.2)),
                ),
                child: Column(children: [
                  Text(
                    _llm?.errorMessage ?? 'Unknown error',
                    style: const TextStyle(fontSize: 13, color: AppTheme.accentRed, height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _retryConnection,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Retry Connection'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ]),
              ),
            ],
          ]),
        ),
      );
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: _msgs.length,
      itemBuilder: (_, i) => _bubble(_msgs[i]),
    );
  }

  Widget _bubble(_Msg msg) {
    final isCaller = msg.type == _MsgType.callerQuestion;
    final accent = isCaller ? AppTheme.textMuted : AppTheme.primary;
    return Align(
      alignment: isCaller ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
        margin: EdgeInsets.only(bottom: 10, left: isCaller ? 0 : 20, right: isCaller ? 20 : 0),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: isCaller ? AppTheme.surfaceLightElevated : AppTheme.primary.withOpacity(0.08),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16), topRight: const Radius.circular(16),
            bottomLeft: isCaller ? const Radius.circular(4) : const Radius.circular(16),
            bottomRight: isCaller ? const Radius.circular(16) : const Radius.circular(4),
          ),
          border: Border.all(color: isCaller ? Colors.black.withOpacity(0.06) : AppTheme.primary.withOpacity(0.18)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(isCaller ? Icons.person_outline : Icons.auto_awesome, size: 12, color: accent),
            const SizedBox(width: 4),
            Text(isCaller ? 'Interviewer' : 'AI Coach',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accent)),
            if (msg.streaming) ...[
              const SizedBox(width: 6),
              SizedBox(width: 9, height: 9, child: CircularProgressIndicator(strokeWidth: 1.5, color: accent)),
            ],
          ]),
          const SizedBox(height: 6),
          Text(msg.text, style: TextStyle(
            fontSize: 15, height: 1.45,
            color: isCaller ? AppTheme.textSecondary : AppTheme.textPrimary,
            fontWeight: isCaller ? FontWeight.w400 : FontWeight.w500,
          )),
          const SizedBox(height: 4),
          Text(
            '${msg.ts.hour.toString().padLeft(2, '0')}:${msg.ts.minute.toString().padLeft(2, '0')}',
            style: TextStyle(fontSize: 10, color: AppTheme.textMuted.withOpacity(0.6)),
          ),
        ]),
      ),
    );
  }

  // ── Controls ─────────────────────────────────────────────────────

  Widget _controls() {
    final sip = _sip;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, -4))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _Btn(icon: sip?.isMuted == true ? Icons.mic_off : Icons.mic_none, label: sip?.isMuted == true ? 'Unmute' : 'Mute',
              active: sip?.isMuted == true, color: AppTheme.accentRed,
              onTap: () async { await sip?.toggleMute(); if (mounted) setState(() {}); }),
          _Btn(icon: sip?.isSpeakerOn == true ? Icons.volume_up : Icons.volume_off, label: 'Speaker',
              active: sip?.isSpeakerOn == true, color: AppTheme.primary,
              onTap: () async { await sip?.toggleSpeaker(); if (mounted) setState(() {}); }),
          _Btn(icon: Icons.call_end, label: 'End', active: true, color: AppTheme.accentRed, isEnd: true,
              onTap: () async { await sip?.endCall(); _hangUp(); }),
        ],
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  final bool isEnd;
  const _Btn({required this.icon, required this.label, required this.active,
      required this.color, required this.onTap, this.isEnd = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: isEnd ? AppTheme.accentRed : active ? color.withOpacity(0.12) : AppTheme.surfaceLightElevated,
            shape: BoxShape.circle,
            border: Border.all(
              color: isEnd ? AppTheme.accentRed : active ? color.withOpacity(0.3) : Colors.transparent,
              width: 2,
            ),
          ),
          child: Icon(icon, color: isEnd ? Colors.white : active ? color : AppTheme.textSecondary, size: 26),
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
            color: isEnd ? AppTheme.accentRed : AppTheme.textSecondary)),
      ]),
    );
  }
}
