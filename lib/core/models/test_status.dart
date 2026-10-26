import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Result state shown next to every test in the sidebar and in the report.
enum TestStatus {
  notTested('Not tested', AppColors.muted),
  running('Running', AppColors.primary),
  pass('Pass', AppColors.pass),
  fail('Fail', AppColors.fail),
  warning('Warning', AppColors.accent);

  const TestStatus(this.label, this.color);

  final String label;
  final Color color;

  /// True once the test has produced a final verdict.
  bool get isFinished =>
      this == TestStatus.pass ||
      this == TestStatus.fail ||
      this == TestStatus.warning;
}
