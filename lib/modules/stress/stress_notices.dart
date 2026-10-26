import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/module_scaffold.dart';

/// Explains why a stress test could not run, with the fix where there is one.
class StressErrorNotice extends StatelessWidget {
  const StressErrorNotice({super.key, required this.code, required this.message, this.pawnIo});

  final String? code;
  final String message;

  /// Whether the PawnIO sensor driver is installed (null if unknown).
  final bool? pawnIo;

  @override
  Widget build(BuildContext context) {
    switch (code) {
      case 'helper-missing':
        return NoticeCard(
          icon: Icons.build_circle_outlined,
          color: AppColors.fail,
          title: 'SolHelper.exe is missing',
          message: 'The hardware helper (tools\\SolHelper.exe) is not installed next to the app. '
              'Reinstall SolLapChecker, or build it with helper\\build.ps1.\n$message',
        );
      case 'no-temperature':
        return NoticeCard(
          icon: Icons.thermostat_rounded,
          color: AppColors.accent,
          title: 'No temperature sensor available',
          message: 'For safety the test will not run without a temperature reading. '
              '${pawnIo == false ? 'The PawnIO sensor driver is not installed on this PC, which most Intel and AMD laptops need to expose CPU temperatures. Install it and try again. ' : ''}'
              '$message',
        );
      default:
        return NoticeCard(
          icon: Icons.error_outline_rounded,
          color: AppColors.fail,
          title: 'The test could not run',
          message: message,
        );
    }
  }
}
