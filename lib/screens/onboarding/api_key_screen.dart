import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../app_router.dart';
import '../../services/storage_service.dart';

class ApiKeyScreen extends StatefulWidget {
  const ApiKeyScreen({super.key});

  @override
  State<ApiKeyScreen> createState() => _ApiKeyScreenState();
}

class _ApiKeyScreenState extends State<ApiKeyScreen> {
  final _keyController = TextEditingController();
  bool _isValidating = false;
  String? _error;
  bool _obscureKey = true;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _saveApiKey() async {
    final key = _keyController.text.trim();
    
    if (key.isEmpty) {
      setState(() => _error = 'Please enter your Gemini API key');
      return;
    }

    if (key.length < 20) {
      setState(() => _error = 'API key seems too short. Check and try again.');
      return;
    }

    setState(() {
      _isValidating = true;
      _error = null;
    });

    try {
      // Save the key
      await StorageService.saveGeminiApiKey(key);
      
      if (mounted) {
        // Navigate to next onboarding step or home
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRouter.home,
          (route) => false,
        );
      }
    } catch (e) {
      setState(() {
        _isValidating = false;
        _error = 'Failed to save key: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              
              // Header icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primary.withValues(alpha: 0.2),
                      AppTheme.accent.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.key_rounded,
                  color: AppTheme.accent,
                  size: 36,
                ),
              ),
              
              const SizedBox(height: 24),
              
              const Text(
                'Connect to\nGemini AI',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  height: 1.2,
                ),
              ),
              
              const SizedBox(height: 8),
              
              Text(
                'Enter your Google AI API key to enable real-time AI answers during calls.',
                style: TextStyle(
                  fontSize: 15,
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
              
              const SizedBox(height: 32),
              
              // API Key Input
              TextField(
                controller: _keyController,
                obscureText: _obscureKey,
                decoration: InputDecoration(
                  hintText: 'AIza...',
                  labelText: 'Gemini API Key',
                  prefixIcon: const Icon(Icons.vpn_key_outlined, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureKey ? Icons.visibility_off : Icons.visibility,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscureKey = !_obscureKey),
                  ),
                  errorText: _error,
                ),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                ),
              ),
              
              const SizedBox(height: 12),
              
              // Help text
              InkWell(
                onTap: () {
                  // Could open aistudio.google.com in browser
                },
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: AppTheme.accent),
                    const SizedBox(width: 6),
                    Text(
                      'Get a free key at aistudio.google.com',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.accent,
                      ),
                    ),
                  ],
                ),
              ),
              
              const Spacer(),
              
              // Continue button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _isValidating ? null : _saveApiKey,
                  icon: _isValidating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle, size: 20),
                  label: Text(
                    _isValidating ? 'Validating...' : 'Continue',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Skip option
              Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      AppRouter.home,
                      (route) => false,
                    );
                  },
                  child: Text(
                    'Skip for now',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
