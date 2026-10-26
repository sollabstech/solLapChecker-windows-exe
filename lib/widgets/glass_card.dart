import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Translucent "glass" panel with a soft gradient fill and hairline border.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 18,
    this.glow,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Optional colour for a soft outer glow.
  final Color? glow;

  @override
  Widget build(BuildContext context) {
    final tint = glow;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        // Opaque base so a glow shadow only shows outside the card, never through it.
        color: AppColors.navy,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            (tint ?? Colors.white).withValues(alpha: tint == null ? 0.07 : 0.09),
            (tint ?? Colors.white).withValues(alpha: tint == null ? 0.02 : 0.03),
          ],
        ),
        border: Border.all(color: (tint ?? Colors.white).withValues(alpha: tint == null ? 0.09 : 0.35)),
        boxShadow: tint == null
            ? null
            : [BoxShadow(color: tint.withValues(alpha: 0.22), blurRadius: 30, spreadRadius: -6)],
      ),
      child: child,
    );
  }
}
