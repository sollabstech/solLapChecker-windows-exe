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

  /// Input without a device handle (precision-touchpad cursor, clicks and
  /// gestures) is believed when no external mouse has been active for this long...
  static const externalQuiet = Duration(seconds: 1);

  /// ...or, once the precision touchpad's own contact reports have been seen,
  /// when a finger touched the pad this recently.
  static const touchWindow = Duration(seconds: 1);

  final actions = <PadAction, ActionState>{for (final a in PadAction.values) a: ActionState.pending}.obs;
  final mice = <int, SeenMouse>{}.obs;
  final ignoredEvents = 0.obs;

  final listening = false.obs;
  final error = RxnString();
  final finished = false.obs;

  StreamSubscription<InputEvent>? _sub;
  var _moveAccum = 0;
  DateTime _lastExternal = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastTouch = DateTime.fromMillisecondsSinceEpoch(0);
  bool _touchReportsSeen = false;

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
    final now = _clock();

    // Contact reports from a precision touchpad: not cursor input themselves,
    // but they show a finger is on the built-in pad right now.
    if (p is RawHidPacket) {
      if (!e.device.isTouchpadDigitizer) return;
      final pad = _seen(e.device);
      if (pad.counted) {
        _touchReportsSeen = true;
        _lastTouch = now;
      }
      return;
    }
    if (p is! RawMousePacket) return;

    // No device handle: synthesized input. A precision touchpad's cursor
    // movement, clicks, taps and scrolling all arrive this way, so they count
    // when the pad was just touched (or, if its contact reports cannot be
    // read, when no external mouse is active).
    if (e.device.handle == 0) {
      final fromPad = _touchReportsSeen
          ? now.difference(_lastTouch) <= touchWindow
          : now.difference(_lastExternal) > externalQuiet;
      if (fromPad) _apply(p, 0, now);
      return;
    }

    final mouse = _seen(e.device);
    if (!mouse.counted) {
      _lastExternal = now;
      ignoredEvents.value++;
      return;
    }
    _apply(p, e.device.handle, now);
  }

  SeenMouse _seen(InputDevice device) {
    final mouse = mice.putIfAbsent(device.handle, () => SeenMouse(device, counted: device.countedByDefault));
    mouse.events++;
    mice.refresh();
    return mouse;
  }

  /// Ticks the actions one counted mouse packet shows.
  void _apply(RawMousePacket p, int handle, DateTime now) {
    if (p.moved) {
      _moveAccum += p.isAbsolute ? 20 : p.dx.abs() + p.dy.abs();
      if (_moveAccum >= moveThreshold) _detect(PadAction.move);
    }
    if (p.leftDown) _detect(PadAction.leftClick);
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

  /// Overrides the automatic decision for a device. External mice cannot be counted.
  void setCounted(int handle, bool counted) {
    final m = mice[handle];
    if (m == null || (counted && !m.device.canBeCounted)) return;
    m.counted = counted;
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
    // In the guided run, a touchpad with every action working finishes by itself.
    if (_app.wizardActive.value && listening.value && doneCount == PadAction.values.length) finish();
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
