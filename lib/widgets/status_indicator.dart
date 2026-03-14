import 'package:flutter/material.dart';
import '../app_theme.dart';

class StatusIndicator extends StatelessWidget {
  final String label;
  final Color color;
  final bool pulsing;

  const StatusIndicator({
    super.key,
    required this.label,
    required this.color,
    this.pulsing = false,
  });

  factory StatusIndicator.connected(String label) => StatusIndicator(
        label: label,
        color: AppTheme.accentGreen,
      );

  factory StatusIndicator.disconnected(String label) => StatusIndicator(
        label: label,
        color: AppTheme.accentRed,
      );

  factory StatusIndicator.connecting(String label) => StatusIndicator(
        label: label,
        color: AppTheme.accentOrange,
        pulsing: true,
      );

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (pulsing)
          _PulsingDot(color: color)
        else
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
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
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Opacity(
          opacity: _animation.value,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.4),
                  blurRadius: 6 * _animation.value,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
