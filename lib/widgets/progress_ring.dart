import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Circular progress indicator that animates smoothly whenever [value]
/// (0..1) changes. [child] is drawn in the centre.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    this.size = 140,
    this.strokeWidth = 12,
    this.color = AppColors.primary,
    this.endColor = AppColors.pass,
    this.child,
  });

  final double value;
  final double size;
  final double strokeWidth;
  final Color color;

  /// Colour at the leading edge of the arc (the gradient runs color -> endColor).
  final Color endColor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.clamp(0, 1)),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(v, strokeWidth, color, endColor),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.stroke, this.color, this.endColor);

  final double value;
  final double stroke;
  final Color color;
  final Color endColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inset = rect.deflate(stroke / 2);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = Colors.white.withValues(alpha: 0.08);
    canvas.drawArc(inset, 0, math.pi * 2, false, track);

    if (value <= 0) return;
    // Rotate so the arc starts at 12 o'clock; the gradient then runs along
    // the arc itself (blue at the start, green at the leading edge).
    final sweep = math.pi * 2 * value;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke
      ..shader = SweepGradient(
        endAngle: math.max(sweep, 0.01),
        colors: [color, endColor],
      ).createShader(rect);
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..rotate(-math.pi / 2)
      ..translate(-size.width / 2, -size.height / 2)
      ..drawArc(inset, 0, sweep, false, arc)
      ..restore();
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value ||
      old.stroke != stroke ||
      old.color != color ||
      old.endColor != endColor;
}
