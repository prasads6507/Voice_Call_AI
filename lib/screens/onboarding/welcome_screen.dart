import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../app_router.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),
              // App Icon
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.4),
                      blurRadius: 30,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.headset_mic_rounded,
                  size: 48,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 32),
              // App Name
              ShaderMask(
                shaderCallback: (bounds) => AppTheme.primaryGradient
                    .createShader(bounds),
                child: const Text(
                  'StealthAnswer',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Real-time AI answers during\nyour interview calls',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
              const Spacer(flex: 2),
              // How it works - 3 steps
              _buildSteps(),
              const Spacer(flex: 2),
              // Get Started button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamed(context, AppRouter.phoneNumber);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Get Started',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '100% free • No account needed',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSteps() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _StepItem(
          icon: Icons.phone_outlined,
          label: 'Get a free\nnumber',
          color: AppTheme.accent,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Icon(
            Icons.chevron_right,
            color: AppTheme.textMuted,
            size: 20,
          ),
        ),
        _StepItem(
          icon: Icons.mic_none_outlined,
          label: 'They call,\nyou listen',
          color: AppTheme.primary,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Icon(
            Icons.chevron_right,
            color: AppTheme.textMuted,
            size: 20,
          ),
        ),
        _StepItem(
          icon: Icons.smart_toy_outlined,
          label: 'AI answers\ninstantly',
          color: AppTheme.accentGreen,
        ),
      ],
    );
  }
}

class _StepItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StepItem({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: color.withValues(alpha: 0.3),
            ),
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.textSecondary,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}
