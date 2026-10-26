import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/app_modules.dart';
import '../../controllers/app_controller.dart';
import '../../core/media/window_control.dart';
import '../../core/models/test_status.dart';

class DisplayColor {
  const DisplayColor(this.name, this.color, this.hint);

  final String name;
  final Color color;

  /// What this colour is best at revealing.
  final String hint;
}

/// Display test: the screen is filled with solid colours so dead, stuck or
/// discoloured pixels stand out; the user then reports what they saw.
class DisplayController extends GetxController {
  DisplayController(this._window);

  final WindowControl _window;

  static const colors = <DisplayColor>[
    DisplayColor('Red', Color(0xFFFF0000), 'stuck or dead red/green/blue sub-pixels'),
    DisplayColor('Green', Color(0xFF00FF00), 'dead or dark pixels'),
    DisplayColor('Blue', Color(0xFF0000FF), 'dead or dark pixels'),
    DisplayColor('White', Color(0xFFFFFFFF), 'dark dots, stains and uneven brightness'),
    DisplayColor('Black', Color(0xFF000000), 'bright (stuck) pixels and backlight bleed'),
  ];

  /// True while the fullscreen colour page is showing.
  final active = false.obs;
  final index = 0.obs;

  /// The user went through every colour (rather than leaving early).
  final sequenceCompleted = false.obs;

  /// true = display is fine, false = problems seen, null = not answered.
  final answer = RxnBool();

  AppController get _app => Get.find<AppController>();

  DisplayColor get current => colors[index.value];

  Future<void> begin() async {
    index.value = 0;
    sequenceCompleted.value = false;
    active.value = true;
    _app.setStatus(ModuleId.display, TestStatus.running);
    await _window.setFullScreen(true);
  }

  /// Next colour; after the last one the sequence is complete and fullscreen ends.
  Future<void> next() async {
    if (!active.value) return;
    if (index.value >= colors.length - 1) {
      sequenceCompleted.value = true;
      await exit();
    } else {
      index.value++;
    }
  }

  void previous() {
    if (active.value && index.value > 0) index.value--;
  }

  /// Leaves fullscreen. Leaving before the last colour leaves the test unfinished.
  Future<void> exit() async {
    if (!active.value) return;
    active.value = false;
    await _window.setFullScreen(false);
    if (!sequenceCompleted.value && answer.value == null) {
      _app.setStatus(ModuleId.display, TestStatus.notTested);
    }
  }

  void setAnswer(bool fine) {
    answer.value = fine;
    _app.setStatus(ModuleId.display, fine ? TestStatus.pass : TestStatus.fail);
  }

  void reset() {
    answer.value = null;
    sequenceCompleted.value = false;
    _app.setStatus(ModuleId.display, TestStatus.notTested);
  }

  Map<String, dynamic> toJson() => {
        'colorsChecked': sequenceCompleted.value ? colors.map((c) => c.name).toList() : <String>[],
        'result': answer.value == null ? null : (answer.value! ? 'no problems' : 'problems seen'),
      };
}
