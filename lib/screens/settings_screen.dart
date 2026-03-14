import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../app_router.dart';
import '../services/storage_service.dart';
import '../services/sip_service.dart';


class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _gvNumberController = TextEditingController();
  final _sipUsernameController = TextEditingController();
  final _sipPasswordController = TextEditingController();
  final _sipDomainController = TextEditingController();
  String _resumePreview = '';
  bool _whisperReady = false;
  bool _gemmaReady = false;
  bool _testing = false;
  bool? _testResult;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _gvNumberController.text = await StorageService.getGvNumber();
    final sipCreds = await StorageService.getSipCredentials();
    _sipUsernameController.text = sipCreds['username']!;
    _sipPasswordController.text = sipCreds['password']!;
    _sipDomainController.text = sipCreds['domain']!;
    
    final resume = await StorageService.getResume();
    _resumePreview = resume.length > 100 ? '${resume.substring(0, 100)}...' : resume;
    
    _whisperReady = await StorageService.isWhisperReady();
    _gemmaReady = await StorageService.isGemmaReady();
    setState(() {});
  }

  @override
  void dispose() {
    _gvNumberController.dispose();
    _sipUsernameController.dispose();
    _sipPasswordController.dispose();
    _sipDomainController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Your Number
            _SectionHeader(title: 'YOUR NUMBER', icon: Icons.phone_outlined),
            const SizedBox(height: 12),
            _buildCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Google Voice Number',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _gvNumberController,
                    decoration: const InputDecoration(
                      hintText: '+1 (555) 123-4567',
                      prefixIcon: Icon(Icons.phone, size: 18),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the Google Voice number you set up',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saveGvNumber,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Save Number', style: TextStyle(fontSize: 14)),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // SIP Connection
            _SectionHeader(title: 'SIP CONNECTION', icon: Icons.dns_outlined),
            const SizedBox(height: 12),
            _buildCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('SIP Username', style: TextStyle(fontSize: 13, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _sipUsernameController,
                    decoration: const InputDecoration(hintText: 'Username', prefixIcon: Icon(Icons.person_outline, size: 18)),
                  ),
                  const SizedBox(height: 16),
                  const Text('SIP Password', style: TextStyle(fontSize: 13, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _sipPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(hintText: 'Password', prefixIcon: Icon(Icons.lock_outline, size: 18)),
                  ),
                  const SizedBox(height: 16),
                  const Text('SIP Server', style: TextStyle(fontSize: 13, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _sipDomainController,
                    decoration: const InputDecoration(hintText: 'sip2sip.info', prefixIcon: Icon(Icons.dns_outlined, size: 18)),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _testing ? null : _testSipConnection,
                          icon: _testing
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent))
                              : const Icon(Icons.wifi_tethering, size: 16),
                          label: Text(_testing ? 'Testing...' : 'Test'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.accent,
                            side: BorderSide(color: AppTheme.accent.withValues(alpha: 0.5)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _saveSipCredentials,
                          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                          child: const Text('Save', style: TextStyle(fontSize: 14)),
                        ),
                      ),
                    ],
                  ),
                  if (_testResult != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          _testResult! ? Icons.check_circle : Icons.error,
                          color: _testResult! ? AppTheme.accentGreen : AppTheme.accentRed,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _testResult! ? 'Connected!' : 'Connection failed',
                          style: TextStyle(fontSize: 13, color: _testResult! ? AppTheme.accentGreen : AppTheme.accentRed),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 28),

            // AI Models
            _SectionHeader(title: 'AI MODELS', icon: Icons.smart_toy_outlined),
            const SizedBox(height: 12),
            _buildCard(
              child: Column(
                children: [
                  _ModelRow(
                    name: 'Whisper Tiny',
                    status: _whisperReady ? 'Ready' : 'Not downloaded',
                    size: '~75 MB',
                    isReady: _whisperReady,
                    onRedownload: () => Navigator.pushNamed(context, AppRouter.modelDownload),
                  ),
                  Divider(height: 20, color: Colors.white.withValues(alpha: 0.06)),
                  _ModelRow(
                    name: 'Gemma-3 1B',
                    status: _gemmaReady ? 'Ready' : 'Not downloaded',
                    size: '~800 MB',
                    isReady: _gemmaReady,
                    onRedownload: () => Navigator.pushNamed(context, AppRouter.modelDownload),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // Resume
            _SectionHeader(title: 'RESUME / CONTEXT', icon: Icons.description_outlined),
            const SizedBox(height: 12),
            _buildCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _resumePreview.isNotEmpty ? _resumePreview : 'No resume added',
                    style: TextStyle(fontSize: 14, color: AppTheme.textSecondary, height: 1.4),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pushNamed(context, AppRouter.resume),
                          icon: const Icon(Icons.edit, size: 16),
                          label: const Text('Edit'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.textSecondary,
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _clearResume,
                          icon: Icon(Icons.delete_outline, size: 16, color: AppTheme.accentRed),
                          label: Text('Clear', style: TextStyle(color: AppTheme.accentRed)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: AppTheme.accentRed.withValues(alpha: 0.3)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // App
            _SectionHeader(title: 'APP', icon: Icons.info_outline),
            const SizedBox(height: 12),
            _buildCard(
              child: Column(
                children: [
                  _SettingsRow(
                    label: 'How it works',
                    icon: Icons.help_outline,
                    onTap: () => Navigator.pushNamed(context, AppRouter.setupGuide),
                  ),
                  Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
                  _SettingsRow(
                    label: 'Version',
                    icon: Icons.code,
                    trailing: Text('1.0.0', style: TextStyle(color: AppTheme.textMuted, fontSize: 14)),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDarkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: child,
    );
  }

  Future<void> _saveGvNumber() async {
    await StorageService.saveGvNumber(_gvNumberController.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Number saved!'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _saveSipCredentials() async {
    await StorageService.saveSipCredentials(
      username: _sipUsernameController.text.trim(),
      password: _sipPasswordController.text,
      domain: _sipDomainController.text.trim(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Credentials saved!'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _testSipConnection() async {
    setState(() { _testing = true; _testResult = null; });
    try {
      final sip = SipService();
      await sip.initialize();
      final success = await sip.registerAccount(
        username: _sipUsernameController.text.trim(),
        password: _sipPasswordController.text,
        domain: _sipDomainController.text.trim(),
      );
      setState(() { _testing = false; _testResult = success; });
      if (success) await sip.unregister();
    } catch (e) {
      setState(() { _testing = false; _testResult = false; });
    }
  }

  void _clearResume() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceDarkElevated,
        title: const Text('Clear Resume?'),
        content: const Text('This will remove all your resume/context data.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              await StorageService.saveResume('');
              if (!mounted) return;
              setState(() => _resumePreview = '');
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
            },
            child: Text('Clear', style: TextStyle(color: AppTheme.accentRed)),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.textMuted),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppTheme.textMuted,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

class _ModelRow extends StatelessWidget {
  final String name;
  final String status;
  final String size;
  final bool isReady;
  final VoidCallback onRedownload;

  const _ModelRow({
    required this.name,
    required this.status,
    required this.size,
    required this.isReady,
    required this.onRedownload,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          isReady ? Icons.check_circle : Icons.circle_outlined,
          color: isReady ? AppTheme.accentGreen : AppTheme.textMuted,
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
              Text('$status • $size', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            ],
          ),
        ),
        TextButton(
          onPressed: onRedownload,
          child: Text('Re-download', style: TextStyle(fontSize: 12, color: AppTheme.primary)),
        ),
      ],
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _SettingsRow({required this.label, required this.icon, this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppTheme.textSecondary),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary))),
            trailing ?? Icon(Icons.chevron_right, size: 18, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }
}
