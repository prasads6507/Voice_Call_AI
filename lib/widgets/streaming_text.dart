import 'package:flutter/material.dart';
import '../app_theme.dart';

class StreamingText extends StatelessWidget {
  final String text;
  final bool isGenerating;
  final TextStyle? style;

  const StreamingText({
    super.key,
    required this.text,
    this.isGenerating = false,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: style ??
            const TextStyle(
              fontSize: 17,
              height: 1.6,
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w400,
            ),
        children: [
          TextSpan(text: text),
          if (isGenerating)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: _BlinkingCursor(),
            ),
        ],
      ),
    );
  }
}

class _BlinkingCursor extends StatefulWidget {
  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _controller.value,
          child: Container(
            width: 2,
            height: 20,
            margin: const EdgeInsets.only(left: 2),
            color: AppTheme.accent,
          ),
        );
      },
    );
  }
}
