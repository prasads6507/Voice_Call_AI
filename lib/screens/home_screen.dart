import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../app_theme.dart';
import '../app_router.dart';
import '../services/sip_service.dart';
import '../services/storage_service.dart';
import '../widgets/status_indicator.dart';
import '../widgets/pulsing_dot.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SipService _sipService = SipService();
  String _gvNumber = '';
  bool _hasApiKey = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _sipService.addListener(_onSipUpdate);
  }

  @override
  void dispose() {
    _sipService.removeListener(_onSipUpdate);
    super.dispose();
  }

  void _onSipUpdate() {
    setState(() {});
    // Handle incoming call — show answer dialog
    if (_sipService.callState == CallState.incoming) {
      _showIncomingCallDialog();
    }
  }

  void _showIncomingCallDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceDarkElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '📞 Incoming Call',
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 20),
        ),
        content: Text(
          _sipService.callerNumber.isNotEmpty
              ? _sipService.callerNumber
              : 'Unknown Caller',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await _sipService.rejectCall();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text('Decline', style: TextStyle(color: AppTheme.accentRed, fontSize: 16)),
          ),
          ElevatedButton(
            onPressed: () async {
              await _sipService.answerCall();
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                Navigator.pushNamed(context, AppRouter.activeCall);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentGreen),
            child: const Text('Answer', style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Future<void> _loadData() async {
    _gvNumber = await StorageService.getGvNumber();
    _hasApiKey = await StorageService.hasGeminiApiKey();
    setState(() {});

    // Auto-register SIP
    await _sipService.initialize();
    await _sipService.registerFromStorage();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ShaderMask(
          shaderCallback: (bounds) =>
              AppTheme.primaryGradient.createShader(bounds),
          child: const Text(
            'StealthAnswer',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 24),
            onPressed: () async {
              await Navigator.pushNamed(context, AppRouter.settings);
              _loadData(); // Reload data after settings
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Interview Number Card
              _buildPhoneNumberCard(),
              const SizedBox(height: 16),

              // SIP Status
              _buildStatusCard(
                title: 'SIP Status',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSipStatus(),
                    if (_sipService.sipAddress.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'sip: ${_sipService.sipAddress}',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textMuted,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // AI Status
              _buildStatusCard(
                title: 'AI Status',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: AppTheme.accentGreen,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Moonshine STT (on-device)',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.accentGreen,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          _hasApiKey ? Icons.check_circle : Icons.circle_outlined,
                          color: _hasApiKey
                              ? AppTheme.accentGreen
                              : AppTheme.textMuted,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Gemini Live ${_hasApiKey ? "connected" : "API key needed"}',
                          style: TextStyle(
                            fontSize: 14,
                            color: _hasApiKey
                                ? AppTheme.accentGreen
                                : AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                    if (!_hasApiKey) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pushNamed(context, AppRouter.apiKey);
                          },
                          icon: const Icon(Icons.key, size: 16),
                          label: const Text('Add API Key'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primary,
                            side: BorderSide(
                              color: AppTheme.primary.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Edit Resume
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pushNamed(context, AppRouter.resume);
                  },
                  icon: const Icon(Icons.edit_note, size: 20),
                  label: const Text('Edit Resume'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),

              const SizedBox(height: 48),

              // Waiting for call
              Center(
                child: Column(
                  children: [
                    PulsingDot(
                      size: 20,
                      color: _sipService.connectionState ==
                              SipConnectionState.connected
                          ? AppTheme.accent
                          : AppTheme.textMuted,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _sipService.connectionState ==
                              SipConnectionState.connected
                          ? 'Waiting for call...'
                          : 'Connect SIP to receive calls',
                      style: TextStyle(
                        fontSize: 17,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Demo button (for testing)
              Center(
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.pushNamed(context, AppRouter.activeCall);
                  },
                  icon: Icon(Icons.play_circle_outline,
                      size: 18, color: AppTheme.textMuted),
                  label: Text(
                    'Demo Active Call',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneNumberCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withValues(alpha: 0.15),
            AppTheme.accent.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your Interview Number',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _gvNumber.isNotEmpty ? _gvNumber : 'Not set — add in Settings',
            style: TextStyle(
              fontSize: _gvNumber.isNotEmpty ? 24 : 16,
              fontWeight: FontWeight.w700,
              color: _gvNumber.isNotEmpty
                  ? AppTheme.textPrimary
                  : AppTheme.textMuted,
              letterSpacing: _gvNumber.isNotEmpty ? 1 : 0,
            ),
          ),
          if (_gvNumber.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.copy,
                    label: 'Copy',
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: _gvNumber));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Number copied!'),
                          backgroundColor: AppTheme.surfaceDarkElevated,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.share,
                    label: 'Share',
                    onTap: () {
                      SharePlus.instance.share(
                        ShareParams(text: 'Call me at $_gvNumber for the interview'),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDarkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildSipStatus() {
    switch (_sipService.connectionState) {
      case SipConnectionState.connected:
        return StatusIndicator.connected('Connected & Listening');
      case SipConnectionState.connecting:
        return StatusIndicator.connecting('Connecting...');
      case SipConnectionState.reconnecting:
        return StatusIndicator.connecting('Reconnecting...');
      case SipConnectionState.error:
        return StatusIndicator.disconnected(_sipService.statusMessage);
      case SipConnectionState.disconnected:
        return StatusIndicator.disconnected('Disconnected');
    }
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: AppTheme.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
