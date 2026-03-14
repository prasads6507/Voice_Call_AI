import 'package:flutter/material.dart';
import '../app_theme.dart';

class PulsingDot extends StatefulWidget {
  final double size;
  final Color color;
  final String? label;

  const PulsingDot({
    super.key,
    this.size = 14,
    this.color = AppTheme.accent,
    this.label,
  });

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _opacityAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Opacity(
                opacity: _opacityAnimation.value,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.5),
                        blurRadius: 12 * _scaleAnimation.value,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        if (widget.label != null) ...[
          const SizedBox(width: 12),
          Text(
            widget.label!,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}
