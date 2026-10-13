import 'package:flutter/material.dart';

/// A vector mark keeps the repository button sharp without an icon-font dependency.
class GitHubIcon extends StatelessWidget {
  const GitHubIcon({super.key});

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.square(24),
    painter: _GitHubPainter(
      IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface,
    ),
  );
}

class _GitHubPainter extends CustomPainter {
  const _GitHubPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // GitHub's 16-unit mark, scaled with the button and coloured by its theme.
    final path = Path()
      ..moveTo(8, 0)
      ..cubicTo(3.58, 0, 0, 3.58, 0, 8)
      ..cubicTo(0, 11.54, 2.29, 14.53, 5.47, 15.59)
      ..cubicTo(5.87, 15.66, 6.02, 15.42, 6.02, 15.21)
      ..cubicTo(6.02, 15.02, 6.01, 14.39, 6.01, 13.72)
      ..cubicTo(4, 14.09, 3.48, 13.23, 3.32, 12.78)
      ..cubicTo(3.23, 12.55, 2.84, 11.84, 2.5, 11.65)
      ..cubicTo(2.22, 11.5, 1.82, 11.13, 2.49, 11.12)
      ..cubicTo(3.12, 11.11, 3.57, 11.7, 3.72, 11.94)
      ..cubicTo(4.44, 13.15, 5.59, 12.81, 6.05, 12.6)
      ..cubicTo(6.12, 12.08, 6.33, 11.73, 6.56, 11.53)
      ..cubicTo(4.78, 11.33, 2.92, 10.64, 2.92, 7.58)
      ..cubicTo(2.92, 6.71, 3.23, 5.99, 3.74, 5.43)
      ..cubicTo(3.66, 5.23, 3.38, 4.41, 3.82, 3.31)
      ..cubicTo(3.82, 3.31, 4.49, 3.1, 6.02, 4.13)
      ..cubicTo(6.66, 3.95, 7.34, 3.86, 8.02, 3.86)
      ..cubicTo(8.7, 3.86, 9.38, 3.95, 10.02, 4.13)
      ..cubicTo(11.55, 3.09, 12.22, 3.31, 12.22, 3.31)
      ..cubicTo(12.66, 4.41, 12.38, 5.23, 12.3, 5.43)
      ..cubicTo(12.81, 5.99, 13.12, 6.7, 13.12, 7.58)
      ..cubicTo(13.12, 10.65, 11.25, 11.33, 9.47, 11.53)
      ..cubicTo(9.76, 11.78, 10.01, 12.26, 10.01, 13.01)
      ..cubicTo(10.01, 14.08, 10, 14.94, 10, 15.21)
      ..cubicTo(10, 15.42, 10.15, 15.67, 10.55, 15.59)
      ..cubicTo(13.71, 14.53, 16, 11.53, 16, 8)
      ..cubicTo(16, 3.58, 12.42, 0, 8, 0)
      ..close();
    canvas.save();
    canvas.scale(size.width / 16, size.height / 16);
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GitHubPainter oldDelegate) => oldDelegate.color != color;
}
