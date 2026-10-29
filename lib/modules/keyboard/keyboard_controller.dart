import 'dart:async';

import 'package:get/get.dart';

import '../../app/app_modules.dart';
import '../../controllers/app_controller.dart';
import '../../core/input/input_device.dart';
import '../../core/input/raw_input_event.dart';
import '../../core/input/raw_input_service.dart';
import '../../core/models/test_status.dart';
import 'keyboard_layout.dart';

enum KeyState {
  untested,

  /// Seen on the built-in keyboard.
  pressed,

  /// Confirmed working by hand (Fn and other keys that send no scan code).
  manualPass,
  failed,
}

/// A keyboard Raw Input has reported, and whether its presses count.
class SeenKeyboard {
  SeenKeyboard(this.device, {required this.counted});

  final InputDevice device;
  bool counted;
  int events = 0;
}

/// Built-in keyboard test: every key must be pressed (or confirmed by hand),
/// counting only the laptop's own keyboard.
class KeyboardController extends GetxController {
  KeyboardController(this._input);

  final RawInputService _input;

  final keys = <String, KeyState>{for (final k in KeyboardLayout.all) k.id: KeyState.untested}.obs;
  final keyboards = <int, SeenKeyboard>{}.obs;

  /// Key presses from keyboards that are not being counted.
  final ignoredPresses = 0.obs;

  /// Scan codes pressed that are not on the layout (e.g. a numeric keypad).
  final otherKeys = <String>{}.obs;
  final lastKeyId = RxnString();

  /// The Fn combination that proved Fn works, e.g. "Volume up".
  final fnSignal = RxnString();

  final listening = false.obs;
  final error = RxnString();
  final finished = false.obs;

  StreamSubscription<InputEvent>? _sub;

  AppController get _app => Get.find<AppController>();

  int get total => KeyboardLayout.total;
  int get testedCount => keys.values.where((s) => s == KeyState.pressed || s == KeyState.manualPass).length;
  int get failedCount => keys.values.where((s) => s == KeyState.failed).length;
  int get untestedCount => total - testedCount - failedCount;

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
    if (!finished.value) _app.setStatus(ModuleId.keyboard, TestStatus.running);
  }

  /// Stops listening (leaving the screen). Progress is kept; an unfinished
  /// test goes back to "Not tested" rather than showing a spinner forever.
  void stop() {
    if (!listening.value) return;
    _sub?.cancel();
    _sub = null;
    _input.release();
    listening.value = false;
    if (!finished.value) _app.setStatus(ModuleId.keyboard, TestStatus.notTested);
  }

  void _onEvent(InputEvent e) {
    final p = e.packet;

    // Media / airplane / sleep buttons arrive as their own HID collections.
    // From the laptop itself they can only come from Fn + a function key.
    if (p is RawHidPacket) {
      if (e.device.isFunctionKeySource && e.device.countedByDefault && p.hasActivity) {
        _fnDetected(switch ((e.device.usagePage, e.device.usage)) {
          (hidPageGenericDesktop, hidUsageRadioControls) => 'Airplane mode',
          (hidPageGenericDesktop, hidUsageSystemControl) => 'Sleep / power',
          _ => 'Media / volume key',
        });
      }
      return;
    }
    if (p is! RawKeyPacket || e.device.kind != InputDeviceKind.keyboard) return;
    if (p.isBreak || p.isE1) return; // key-up, and Pause (E1 sequence)
    if (p.vKey == 0xFF) return; // fake scan codes Windows injects (e.g. around PrintScreen)

    final handle = e.device.handle;
    final kb = keyboards.putIfAbsent(
      handle,
      () => SeenKeyboard(e.device, counted: e.device.countedByDefault),
    );
    kb.events++;
    keyboards.refresh();

    if (!kb.counted) {
      ignoredPresses.value++;
      return;
    }

    final def = KeyboardLayout.find(p.makeCode, extended: p.isExtended);
    if (def == null) {
      final fn = KeyboardLayout.fnSignalName(p.makeCode, extended: p.isExtended, vKey: p.vKey);
      if (fn != null) {
        _fnDetected(fn);
        return;
      }
      otherKeys.add('0x${p.makeCode.toRadixString(16).toUpperCase().padLeft(2, '0')}${p.isExtended ? ' (E0)' : ''}');
      return;
    }
    lastKeyId.value = def.id;
    // A key that physically works clears a manual "not working" mark.
    keys[def.id] = KeyState.pressed;
    _afterChange();
  }

  void _fnDetected(String via) {
    fnSignal.value = via;
    lastKeyId.value = KeyboardLayout.fnId;
    keys[KeyboardLayout.fnId] = KeyState.pressed;
    _afterChange();
  }

  /// Include or exclude a keyboard from the test (overrides the automatic decision).
  /// External keyboards cannot be counted.
  void setCounted(int handle, bool counted) {
    final kb = keyboards[handle];
    if (kb == null || (counted && !kb.device.canBeCounted)) return;
    kb.counted = counted;
    keyboards.refresh();
  }

  void markWorking(String id) {
    if (keys[id] != KeyState.pressed) keys[id] = KeyState.manualPass;
    _afterChange();
  }

  void markNotWorking(String id) {
    keys[id] = KeyState.failed;
    _afterChange();
  }

  void clearKey(String id) {
    keys[id] = KeyState.untested;
    _afterChange();
  }

  void reset() {
    for (final k in keys.keys.toList()) {
      keys[k] = KeyState.untested;
    }
    ignoredPresses.value = 0;
    otherKeys.clear();
    lastKeyId.value = null;
    fnSignal.value = null;
    finished.value = false;
    _app.setStatus(ModuleId.keyboard, listening.value ? TestStatus.running : TestStatus.notTested);
  }

  /// Ends the test and publishes the verdict.
  void finish() {
    finished.value = true;
    _app.setStatus(ModuleId.keyboard, verdict());
  }

  /// Fail if any key was marked not working; warning if keys were never tried.
  TestStatus verdict() {
    if (failedCount > 0) return TestStatus.fail;
    if (untestedCount > 0) return TestStatus.warning;
    return TestStatus.pass;
  }

  void _afterChange() {
    // Editing after finishing reopens the test.
    if (finished.value) {
      finished.value = false;
      if (listening.value) _app.setStatus(ModuleId.keyboard, TestStatus.running);
    }
    // In the guided run, a keyboard with every key working finishes by itself.
    if (_app.wizardActive.value && listening.value && testedCount == total) finish();
  }

  /// Lists of key labels for the report (Phase 6).
  Map<String, dynamic> toJson() => {
        'total': total,
        'tested': testedCount,
        'failed': [for (final k in KeyboardLayout.all) if (keys[k.id] == KeyState.failed) k.label],
        'untested': [for (final k in KeyboardLayout.all) if (keys[k.id] == KeyState.untested) k.label],
        'manuallyConfirmed': [for (final k in KeyboardLayout.all) if (keys[k.id] == KeyState.manualPass) k.label],
        'fnDetectedVia': fnSignal.value,
        'ignoredExternalPresses': ignoredPresses.value,
        'devices': [
          for (final kb in keyboards.values)
            {'device': kb.device.description, 'bus': kb.device.bus.label, 'counted': kb.counted, 'presses': kb.events},
        ],
      };

  @override
  void onClose() {
    stop();
    super.onClose();
  }
}
