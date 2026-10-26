import 'package:flutter/material.dart';

import '../app/theme.dart';
import 'glass_card.dart';

/// Line chart for a live series sampled once per second. The x-axis always
/// spans the whole planned run so the line grows from left to right.
class LiveChart extends StatelessWidget {
  const LiveChart({
    super.key,
    required this.title,
    required this.values,
    required this.totalSeconds,
    required this.minY,
    required this.maxY,
    required this.color,
    this.unit = '',
    this.current,
    this.threshold,
    this.thresholdLabel,
    this.height = 170,
  });

  final String title;

  /// Value per second, index 0 = second 1. Null entries leave a gap.
  final List<double?> values;
  final int totalSeconds;
  final double minY;
  final double maxY;
  final Color color;
  final String unit;
  final String? current;

  /// Optional horizontal limit line (e.g. the 95 °C safety limit).
  final double? threshold;
  final String? thresholdLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const Spacer(),
              if (current != null)
                Text(current!, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: color)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: height,
            child: CustomPaint(
              size: Size.infinite,
              painter: _ChartPainter(
                values: values,
                totalSeconds: totalSeconds <= 0 ? 60 : totalSeconds,
                minY: minY,
                maxY: maxY,
                color: color,
                unit: unit,
                threshold: threshold,
                thresholdLabel: thresholdLabel,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.values,
    required this.totalSeconds,
    required this.minY,
    required this.maxY,
    required this.color,
    required this.unit,
    this.threshold,
    this.thresholdLabel,
  });

  final List<double?> values;
  final int totalSeconds;
  final double minY;
  final double maxY;
  final Color color;
  final String unit;
  final double? threshold;
  final String? thresholdLabel;

  static const _left = 44.0;
  static const _bottom = 18.0;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTWH(_left, 4, size.width - _left - 4, size.height - _bottom - 4);
    final span = (maxY - minY) <= 0 ? 1.0 : (maxY - minY);

    double xOf(int i) => plot.left + plot.width * ((i + 1) / totalSeconds).clamp(0.0, 1.0);
    double yOf(double v) => plot.bottom - plot.height * ((v - minY) / span).clamp(0.0, 1.0);

    // grid + y labels
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final v = minY + span * i / 4;
      final y = yOf(v);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      _text(canvas, '${v.round()}', Offset(plot.left - 6, y), align: _Align.right);
    }

    // x labels: start, middle, end
    for (final f in [0.0, 0.5, 1.0]) {
      final secs = (totalSeconds * f).round();
      _text(
        canvas,
        _mmss(secs),
        Offset(plot.left + plot.width * f, plot.bottom + 4),
        align: f == 0 ? _Align.left : (f == 1 ? _Align.right : _Align.center),
        below: true,
      );
    }

    // threshold line
    if (threshold != null && threshold! >= minY && threshold! <= maxY) {
      final y = yOf(threshold!);
      final dash = Paint()
        ..color = AppColors.fail.withValues(alpha: 0.8)
        ..strokeWidth = 1.2;
      for (var x = plot.left; x < plot.right; x += 8) {
        canvas.drawLine(Offset(x, y), Offset((x + 4).clamp(plot.left, plot.right), y), dash);
      }
      if (thresholdLabel != null) {
        _text(canvas, thresholdLabel!, Offset(plot.right - 2, y - 2),
            align: _Align.right, color: AppColors.fail, above: true);
      }
    }

    // series: break the path at null samples
    final line = Path();
    final fill = Path();
    var open = false;
    double? firstX;
    double? lastX;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) {
        if (open) _closeFill(fill, lastX!, plot.bottom);
        open = false;
        continue;
      }
      final p = Offset(xOf(i), yOf(v));
      if (!open) {
        line.moveTo(p.dx, p.dy);
        fill.moveTo(p.dx, plot.bottom);
        fill.lineTo(p.dx, p.dy);
        firstX = p.dx;
        open = true;
      } else {
        line.lineTo(p.dx, p.dy);
        fill.lineTo(p.dx, p.dy);
      }
      lastX = p.dx;
    }
    if (open && lastX != null) _closeFill(fill, lastX, plot.bottom);

    if (firstX != null) {
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0.0)],
          ).createShader(plot),
      );
      canvas.drawPath(
        line,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _closeFill(Path fill, double x, double bottom) {
    fill
      ..lineTo(x, bottom)
      ..close();
  }

  void _text(
    Canvas canvas,
    String s,
    Offset at, {
    _Align align = _Align.left,
    Color color = AppColors.muted,
    bool below = false,
    bool above = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: color, fontSize: 10.5, fontFamily: 'Inter')),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = switch (align) {
      _Align.left => at.dx,
      _Align.center => at.dx - tp.width / 2,
      _Align.right => at.dx - tp.width,
    };
    final dy = below ? at.dy : (above ? at.dy - tp.height : at.dy - tp.height / 2);
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.values.length != values.length ||
      old.totalSeconds != totalSeconds ||
      old.minY != minY ||
      old.maxY != maxY ||
      old.color != color ||
      (values.isNotEmpty && old.values.isNotEmpty && old.values.last != values.last);
}

enum _Align { left, center, right }

String _mmss(int seconds) => '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

/// "m:ss" helper shared with the stress panel.
String formatMmSs(int seconds) => _mmss(seconds);
