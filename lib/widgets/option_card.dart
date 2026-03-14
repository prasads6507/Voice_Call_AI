import 'package:flutter/material.dart';
import '../app_theme.dart';

class OptionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String body;
  final String? buttonText;
  final VoidCallback? onButtonPressed;
  final bool isRecommended;
  final Widget? trailing;

  const OptionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.body,
    this.buttonText,
    this.onButtonPressed,
    this.isRecommended = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceDarkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isRecommended
              ? AppTheme.primary.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.08),
          width: isRecommended ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isRecommended
                  ? AppTheme.primary.withValues(alpha: 0.1)
                  : Colors.white.withValues(alpha: 0.03),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isRecommended
                        ? AppTheme.primary.withValues(alpha: 0.2)
                        : AppTheme.surfaceDarkElevated,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: isRecommended ? AppTheme.primary : AppTheme.accent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          if (isRecommended) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Recommended',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.primaryLight,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              body,
              style: const TextStyle(
                fontSize: 14,
                height: 1.6,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          // Button
          if (buttonText != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onButtonPressed,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(buttonText!),
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                        isRecommended ? AppTheme.primary : AppTheme.accent,
                    side: BorderSide(
                      color: isRecommended
                          ? AppTheme.primary.withValues(alpha: 0.5)
                          : AppTheme.accent.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ),
          if (trailing != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: trailing!,
            ),
        ],
      ),
    );
  }
}
