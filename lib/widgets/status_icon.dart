import 'package:flutter/material.dart';

import '../core/models/test_status.dart';

/// Animated status glyph: hollow dot, spinner, green tick, red cross or
/// gold warning. Changing [status] cross-fades with a small pop.
class StatusIcon extends StatelessWidget {
  const StatusIcon({super.key, required this.status, this.size = 20});

  final TestStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.elasticOut,
      // elasticOut overshoots 1.0, so the fade must not run through another
      // curve (that asserts); FadeTransition clamps opacity on its own.
      transitionBuilder: (child, anim) => ScaleTransition(
        scale: anim,
        child: FadeTransition(opacity: anim, child: child),
      ),
      child: SizedBox(
        key: ValueKey(status),
        width: size,
        height: size,
        child: _glyph(),
      ),
    );
  }

  Widget _glyph() {
    switch (status) {
      case TestStatus.notTested:
        return DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: status.color.withValues(alpha: 0.6), width: 1.6),
          ),
        );
      case TestStatus.running:
        return Padding(
          padding: const EdgeInsets.all(2),
          child: CircularProgressIndicator(strokeWidth: 2.4, color: status.color),
        );
      case TestStatus.pass:
        return _filled(Icons.check_rounded);
      case TestStatus.fail:
        return _filled(Icons.close_rounded);
      case TestStatus.warning:
        return _filled(Icons.priority_high_rounded);
    }
  }

  Widget _filled(IconData icon) => DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: status.color,
          boxShadow: [BoxShadow(color: status.color.withValues(alpha: 0.6), blurRadius: 10)],
        ),
        child: Icon(icon, size: size * 0.7, color: const Color(0xFF07152A)),
      );
}
