import 'dart:async';

import 'package:get/get.dart';

import '../../app/app_modules.dart';
import '../../controllers/app_controller.dart';
import '../../core/input/input_device.dart';
import '../../core/input/raw_input_event.dart';
import '../../core/input/raw_input_service.dart';
import '../../core/models/test_status.dart';

enum PadAction {
  move('Move the cursor', 'Slide one finger across the touchpad'),
  leftClick('Left click', 'Press the left side or lower-left corner'),
  rightClick('Right click', 'Press the right side or lower-right corner'),
  tap('Tap to click', 'Touch the pad lightly and lift, without pressing down'),
  scroll('Two-finger scroll', 'Slide two fingers up and down on the pad');

  const PadAction(this.title, this.hint);
  final String title;
  final String hint;
}

enum ActionState { pending, detected, manualPass, failed }

class SeenMouse {
  SeenMouse(this.device, {required this.counted});

  final InputDevice device;
  bool counted;
  int events = 0;
}

/// Built-in touchpad test. Raw Input tells which device produced each event,
/// so an external USB or Bluetooth mouse never ticks an action.
class TouchpadController extends GetxController {
  TouchpadController(this._input, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final RawInputService _input;
  final DateTime Function() _clock;

  /// Raw mouse counts of movement before "move" counts as detected.
  static const moveThreshold = 400;

  /// A left press shorter than this is treated as a tap rather than a press.
  /// Tap-to-click and a very quick physical click look alike; the manual
  /// buttons cover the rare mix-up.
  static const tapMax = Duration(milliseconds: 80);

  /// Wheel input without a device handle (precision-touchpad gestures) is only
  /// believed when no external mouse has been active for this long.
  static const externalQuiet = Duration(seconds: 1);

  final actions = <PadAction, ActionState>{for (final a in PadAction.values) a: ActionState.pending}.obs;
  final mice = <int, SeenMouse>{}.obs;
  final ignoredEvents = 0.obs;

  final listening = false.obs;
  final error = RxnString();
  final finished = false.obs;

  StreamSubscription<InputEvent>? _sub;
  var _moveAccum = 0;
  final _downAt = <int, DateTime>{};
  DateTime _lastExternal = DateTime.fromMillisecondsSinceEpoch(0);

  AppController get _app => Get.find<AppController>();

  int get doneCount => actions.values.where((s) => s == ActionState.detected || s == ActionState.manualPass).length;
  int get failedCount => actions.values.where((s) => s == ActionState.failed).length;

  Future<void> start() async {
    if (listening.value) return;
    error.value = null;
    try {
      await _input.acquire();
    } catch (e) {
      error.value = '$e';
      return;
    }
    _sub = _input.events.listen(_onEvent);
    listening.value = true;
    if (!finished.value) _app.setStatus(ModuleId.touchpad, TestStatus.running);
  }

  void stop() {
    if (!listening.value) return;
    _sub?.cancel();
    _sub = null;
    _input.release();
    listening.value = false;
    if (!finished.value) _app.setStatus(ModuleId.touchpad, TestStatus.notTested);
  }

  void _onEvent(InputEvent e) {
    final p = e.packet;
    if (p is! RawMousePacket) return;
    final now = _clock();

    // No device handle: synthesized input. That includes precision-touchpad
    // scroll gestures, so accept wheel events unless an external mouse is active.
    if (e.device.handle == 0) {
      if (p.wheel && now.difference(_lastExternal) > externalQuiet) _detect(PadAction.scroll);
      return;
    }

    final mouse = mice.putIfAbsent(e.device.handle, () => SeenMouse(e.device, counted: e.device.countedByDefault));
    mouse.events++;
    mice.refresh();

    if (!mouse.counted) {
      _lastExternal = now;
      ignoredEvents.value++;
      return;
    }

    if (p.moved) {
      _moveAccum += p.isAbsolute ? 20 : p.dx.abs() + p.dy.abs();
      if (_moveAccum >= moveThreshold) _detect(PadAction.move);
    }
    if (p.leftDown) {
      _downAt[e.device.handle] = now;
      _detect(PadAction.leftClick);
    }
    if (p.leftUp) {
      final down = _downAt.remove(e.device.handle);
      if (down != null && now.difference(down) <= tapMax) _detect(PadAction.tap);
    }
    if (p.rightDown) _detect(PadAction.rightClick);
    if (p.wheel) _detect(PadAction.scroll);
  }

  /// A scroll gesture seen by Flutter in the test area. Believed only if no
  /// external mouse was active around then (checked after a short delay,
  /// since the raw event for an external wheel can arrive just after).
  void onFlutterScroll() {
    Timer(const Duration(milliseconds: 150), () {
      if (_clock().difference(_lastExternal) > externalQuiet) _detect(PadAction.scroll);
    });
  }

  void _detect(PadAction a) {
    if (actions[a] == ActionState.pending || actions[a] == ActionState.failed) {
      actions[a] = ActionState.detected;
      _afterChange();
    }
  }

  void setCounted(int handle, bool counted) {
    mice[handle]?.counted = counted;
    mice.refresh();
  }

  void markWorking(PadAction a) {
    if (actions[a] != ActionState.detected) actions[a] = ActionState.manualPass;
    _afterChange();
  }

  void markNotWorking(PadAction a) {
    actions[a] = ActionState.failed;
    _afterChange();
  }

  void reset() {
    for (final a in PadAction.values) {
      actions[a] = ActionState.pending;
    }
    _moveAccum = 0;
    _downAt.clear();
    ignoredEvents.value = 0;
    finished.value = false;
    _app.setStatus(ModuleId.touchpad, listening.value ? TestStatus.running : TestStatus.notTested);
  }

  void finish() {
    finished.value = true;
    _app.setStatus(ModuleId.touchpad, verdict());
  }

  /// Fail if any action was marked not working; warning if some were never seen.
  TestStatus verdict() {
    if (failedCount > 0) return TestStatus.fail;
    if (doneCount < PadAction.values.length) return TestStatus.warning;
    return TestStatus.pass;
  }

  void _afterChange() {
    if (finished.value) {
      finished.value = false;
      if (listening.value) _app.setStatus(ModuleId.touchpad, TestStatus.running);
    }
  }

  Map<String, dynamic> toJson() => {
        for (final a in PadAction.values) a.name: actions[a]!.name,
        'ignoredExternalEvents': ignoredEvents.value,
        'devices': [
          for (final m in mice.values)
            {'device': m.device.description, 'bus': m.device.bus.label, 'counted': m.counted, 'events': m.events},
        ],
      };

  @override
  void onClose() {
    stop();
    super.onClose();
  }
}
