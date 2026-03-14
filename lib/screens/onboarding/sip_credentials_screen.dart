import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app_theme.dart';
import '../../app_router.dart';
import '../../services/storage_service.dart';
import '../../services/sip_service.dart';

class SipCredentialsScreen extends StatefulWidget {
  const SipCredentialsScreen({super.key});

  @override
  State<SipCredentialsScreen> createState() => _SipCredentialsScreenState();
}

class _SipCredentialsScreenState extends State<SipCredentialsScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _domainController = TextEditingController(text: 'sip2sip.info');
  bool _obscurePassword = true;
  bool _testing = false;
  bool? _testResult;
  String _testMessage = '';

  String get _sipAddress {
    final user = _usernameController.text.trim();
    final domain = _domainController.text.trim();
    if (user.isEmpty) return '';
    return '$user@$domain';
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _domainController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SIP Credentials'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Connect your\nSIP address',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter the credentials from your SIP provider.',
                style: TextStyle(
                  fontSize: 15,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 32),

              // SIP Username
              const Text(
                'SIP Username',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _usernameController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'e.g. johnsmith2024',
                  prefixIcon: Icon(Icons.person_outline, size: 20),
                ),
                keyboardType: TextInputType.text,
                autocorrect: false,
              ),
              const SizedBox(height: 20),

              // SIP Password
              const Text(
                'SIP Password',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  hintText: 'Your SIP password',
                  prefixIcon: const Icon(Icons.lock_outline, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // SIP Domain
              const Text(
                'SIP Domain',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _domainController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'sip2sip.info',
                  prefixIcon: Icon(Icons.dns_outlined, size: 20),
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
              ),
              const SizedBox(height: 8),
              Text(
                'Default: sip2sip.info • For Telnyx: sip.telnyx.com',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                ),
              ),

              // SIP Address Preview
              if (_sipAddress.isNotEmpty) ...[
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceLightElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your SIP Address',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _sipAddress,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Test Connection
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _testing ? null : _testConnection,
                  icon: _testing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.accent,
                          ),
                        )
                      : const Icon(Icons.wifi_tethering, size: 20),
                  label: Text(_testing ? 'Testing...' : 'Test Connection'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accent,
                    side: BorderSide(
                      color: AppTheme.accent.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),

              // Test Result
              if (_testResult != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _testResult!
                        ? AppTheme.accentGreen.withValues(alpha: 0.1)
                        : AppTheme.accentRed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _testResult!
                          ? AppTheme.accentGreen.withValues(alpha: 0.3)
                          : AppTheme.accentRed.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _testResult! ? Icons.check_circle : Icons.error,
                        color: _testResult!
                            ? AppTheme.accentGreen
                            : AppTheme.accentRed,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _testMessage,
                          style: TextStyle(
                            fontSize: 14,
                            color: _testResult!
                                ? AppTheme.accentGreen
                                : AppTheme.accentRed,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // Continue button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _canContinue ? _saveAndContinue : null,
                  style: ElevatedButton.styleFrom(
                    disabledBackgroundColor:
                        AppTheme.primary.withValues(alpha: 0.3),
                    disabledForegroundColor:
                        Colors.white.withValues(alpha: 0.3),
                  ),
                  child: const Text('Continue', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  bool get _canContinue =>
      _usernameController.text.trim().isNotEmpty &&
      _passwordController.text.isNotEmpty &&
      _domainController.text.trim().isNotEmpty;

  Future<void> _testConnection() async {
    if (_usernameController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      setState(() {
        _testResult = false;
        _testMessage = 'Please fill in username and password first.';
      });
      return;
    }

    setState(() {
      _testing = true;
      _testResult = null;
    });

    try {
      final sipService = Provider.of<SipService>(context, listen: false);
      await sipService.initialize();
      final success = await sipService.registerAccount(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        domain: _domainController.text.trim(),
      );

      setState(() {
        _testing = false;
        _testResult = success;
        _testMessage = success
            ? 'Connected! Your number is active.'
            : 'Connection failed. Check your credentials.';
      });

      if (success) {
        await sipService.unregister();
      }
    } catch (e) {
      setState(() {
        _testing = false;
        _testResult = false;
        _testMessage = 'Error: ${e.toString().substring(0, 80)}';
      });
    }
  }

  Future<void> _saveAndContinue() async {
    await StorageService.saveSipCredentials(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      domain: _domainController.text.trim(),
    );

    if (mounted) {
      Navigator.pushNamed(context, AppRouter.resume);
    }
  }
}
