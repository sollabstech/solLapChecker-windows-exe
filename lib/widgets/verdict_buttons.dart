import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Two big buttons for "it works" / "it does not", used by the tests that
/// need a human to judge the result (camera, speakers, microphone, display).
class VerdictButtons extends StatelessWidget {
  const VerdictButtons({
    super.key,
    required this.onPass,
    required this.onFail,
    this.passLabel = 'Works',
    this.failLabel = 'Not working',
    this.answer,
  });

  final VoidCallback? onPass;
  final VoidCallback? onFail;
  final String passLabel;
  final String failLabel;

  /// The recorded answer: true = pass, false = fail, null = none yet.
  final bool? answer;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _button(
          label: passLabel,
          icon: Icons.check_circle_rounded,
          color: AppColors.pass,
          selected: answer == true,
          onTap: onPass,
        ),
        const SizedBox(width: 10),
        _button(
          label: failLabel,
          icon: Icons.cancel_rounded,
          color: AppColors.fail,
          selected: answer == false,
          onTap: onFail,
        ),
      ],
    );
  }

  Widget _button({
    required String label,
    required IconData icon,
    required Color color,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    return selected
        ? FilledButton.icon(
            onPressed: onTap,
            style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: const Color(0xFF07152A)),
            icon: Icon(icon, size: 18),
            label: Text(label),
          )
        : OutlinedButton.icon(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color.withValues(alpha: 0.7))),
            icon: Icon(icon, size: 18),
            label: Text(label),
          );
  }
}
