import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sollapchecker/app/app_modules.dart';
import 'package:sollapchecker/controllers/app_controller.dart';
import 'package:sollapchecker/core/input/input_device.dart';
import 'package:sollapchecker/core/input/raw_input_event.dart';
import 'package:sollapchecker/core/models/test_status.dart';
import 'package:sollapchecker/modules/keyboard/keyboard_controller.dart';
import 'package:sollapchecker/modules/keyboard/keyboard_layout.dart';
import 'package:sollapchecker/modules/touchpad/touchpad_controller.dart';

import 'helpers/fake_raw_input.dart';

Future<void> tick() => Future<void>.delayed(Duration.zero);

void main() {
  setUp(() {
    Get.reset();
    Get.put(AppController());
  });
  tearDown(Get.reset);

  group('KeyboardLayout', () {
    test('has 84 keys with unique ids and unique (scan, E0) codes', () {
      expect(KeyboardLayout.total, 84);
      expect(KeyboardLayout.all.map((k) => k.id).toSet(), hasLength(84));

      final codes = [for (final k in KeyboardLayout.all) if (k.scan != null) (k.scan, k.extended)];
      expect(codes.toSet(), hasLength(codes.length));
    });

    test('left and right Alt/Ctrl are told apart by the E0 prefix', () {
      expect(KeyboardLayout.find(0x38, extended: false)!.id, 'lalt');
      expect(KeyboardLayout.find(0x38, extended: true)!.id, 'ralt');
      expect(KeyboardLayout.find(0x1D, extended: false)!.id, 'lctrl');
      expect(KeyboardLayout.find(0x1D, extended: true)!.id, 'rctrl');
      expect(KeyboardLayout.find(0x1E, extended: false)!.label, 'A');
      expect(KeyboardLayout.find(0x4B, extended: true)!.id, 'left');
      expect(KeyboardLayout.find(0x4B, extended: false), isNull); // numpad 4: not on the layout
    });

    test('only Fn is manual-only', () {
      expect(KeyboardLayout.all.where((k) => k.manualOnly).map((k) => k.id), ['fn']);
    });
  });

  group('KeyboardController', () {
    late FakeRawInput input;
    late KeyboardController kb;
    late AppController app;

    setUp(() async {
      input = FakeRawInput();
      kb = KeyboardController(input);
      app = Get.find<AppController>();
      await kb.start();
    });

    test('start listens and marks the test running; stop returns it to Not tested', () async {
      expect(input.started, isTrue);
      expect(app.statusOf(ModuleId.keyboard), TestStatus.running);
      kb.stop();
      expect(input.started, isFalse);
      expect(app.statusOf(ModuleId.keyboard), TestStatus.notTested);
    });

    test('keys pressed on the built-in keyboard turn green', () async {
      input.send(keyEvent(internalKeyboard, 0x1E)); // A
      input.send(keyEvent(internalKeyboard, 0x4D, extended: true)); // right arrow
      await tick();

      expect(kb.keys['key_A'], KeyState.pressed);
      expect(kb.keys['right'], KeyState.pressed);
      expect(kb.testedCount, 2);
      expect(kb.lastKeyId.value, 'right');
    });

    test('an external USB keyboard is ignored and counted', () async {
      input.send(keyEvent(usbKeyboard, 0x1E));
      input.send(keyEvent(usbKeyboard, 0x1F));
      input.send(keyEvent(internalKeyboard, 0x20)); // D, built-in
      await tick();

      expect(kb.testedCount, 1);
      expect(kb.keys['key_A'], KeyState.untested);
      expect(kb.ignoredPresses.value, 2);
      expect(kb.keyboards.keys, containsAll([100, 200]));
      expect(kb.keyboards[200]!.counted, isFalse);
      expect(kb.keyboards[100]!.counted, isTrue);
    });

    test('an unidentified USB keyboard can be switched on by hand (e.g. the laptop\'s own)', () async {
      const unsure = InputDevice(
        handle: 210,
        kind: InputDeviceKind.keyboard,
        path: r'\\?\HID#VID_1038&PID_1122&MI_00#7&1&0&0000#{884b96c3-56ef-11d1-bc8c-00a0c9014b0f}',
        bus: DeviceBus.usbUnknown,
      );
      input.send(keyEvent(unsure, 0x1E));
      await tick();
      expect(kb.keys['key_A'], KeyState.untested);
      kb.setCounted(210, true);
      input.send(keyEvent(unsure, 0x1E));
      await tick();
      expect(kb.keys['key_A'], KeyState.pressed);
    });

    test('an external keyboard is always ignored: it cannot be switched on', () async {
      input.send(keyEvent(usbKeyboard, 0x1E));
      await tick();
      kb.setCounted(200, true);
      input.send(keyEvent(usbKeyboard, 0x1E));
      await tick();
      expect(kb.keyboards[200]!.counted, isFalse);
      expect(kb.keys['key_A'], KeyState.untested);
    });

    test('releases, Windows fake scan codes and Pause are not key presses', () async {
      input.send(keyEvent(internalKeyboard, 0x1E, up: true));
      input.send(keyEvent(internalKeyboard, 0x2A, extended: true, vKey: 0xFF)); // fake shift around PrintScreen
      input.send(InputEvent(
        internalKeyboard,
        const RawKeyPacket(deviceHandle: 100, inForeground: true, makeCode: 0x1D, flags: riKeyE1, vKey: 0x13),
      ));
      await tick();
      expect(kb.testedCount, 0);
    });

    test('keys that are not on the layout are listed separately', () async {
      input.send(keyEvent(internalKeyboard, 0x4B)); // numpad 4 (no E0)
      await tick();
      expect(kb.testedCount, 0);
      expect(kb.otherKeys, {'0x4B'});
    });

    test('Fn is detected through Fn + a media key on the built-in keyboard (HID media collection)', () async {
      input.send(hidEvent(mediaKeys, [1, 0, 0])); // release frame: nothing pressed
      await tick();
      expect(kb.keys['fn'], KeyState.untested);

      input.send(hidEvent(mediaKeys, [1, 0xE9, 0])); // volume up
      await tick();
      expect(kb.keys['fn'], KeyState.pressed);
      expect(kb.fnSignal.value, 'Media / volume key');
      expect(kb.lastKeyId.value, 'fn');
      expect(kb.toJson()['fnDetectedVia'], 'Media / volume key');
    });

    test('Fn is detected through the airplane-mode button', () async {
      input.send(hidEvent(airplaneButton, [1, 1]));
      await tick();
      expect(kb.keys['fn'], KeyState.pressed);
      expect(kb.fnSignal.value, 'Airplane mode');
    });

    test('Fn is detected through a media key the keyboard reports as a keystroke', () async {
      input.send(keyEvent(internalKeyboard, 0x30, extended: true, vKey: 0xAF)); // E0 30 = volume up
      await tick();
      expect(kb.keys['fn'], KeyState.pressed);
      expect(kb.fnSignal.value, 'Volume up');
      expect(kb.otherKeys, isEmpty);
    });

    test('media keys from an external keyboard do not count as Fn', () async {
      input.send(hidEvent(externalMediaKeys, [1, 0xE9, 0]));
      input.send(keyEvent(usbKeyboard, 0x30, extended: true, vKey: 0xAF));
      await tick();
      expect(kb.keys['fn'], KeyState.untested);
      expect(kb.fnSignal.value, isNull);
    });

    test('touchpad contact reports are not keyboard input', () async {
      input.send(hidEvent(precisionTouchpad, [1, 3, 0x10, 0x20]));
      await tick();
      expect(kb.keys['fn'], KeyState.untested);
    });

    test('manual marks: Fn can be confirmed, any key can be failed, a real press overrides', () async {
      kb.markWorking('fn');
      expect(kb.keys['fn'], KeyState.manualPass);
      expect(kb.testedCount, 1);

      kb.markNotWorking('key_Q');
      expect(kb.failedCount, 1);

      input.send(keyEvent(internalKeyboard, 0x10)); // Q works after all
      await tick();
      expect(kb.keys['key_Q'], KeyState.pressed);
      expect(kb.failedCount, 0);

      kb.clearKey('fn');
      expect(kb.keys['fn'], KeyState.untested);
    });

    test('verdict: untested keys warn, failed keys fail, everything tested passes', () async {
      kb.finish();
      expect(app.statusOf(ModuleId.keyboard), TestStatus.warning);

      kb.markNotWorking('key_Q');
      kb.finish();
      expect(app.statusOf(ModuleId.keyboard), TestStatus.fail);

      kb.clearKey('key_Q');
      for (final k in KeyboardLayout.all) {
        if (k.manualOnly) {
          kb.markWorking(k.id);
        } else {
          input.send(keyEvent(internalKeyboard, k.scan!, extended: k.extended));
        }
      }
      await tick();
      expect(kb.testedCount, 84);
      kb.finish();
      expect(app.statusOf(ModuleId.keyboard), TestStatus.pass);
    });

    test('changing a key after finishing reopens the test', () async {
      kb.finish();
      kb.markNotWorking('key_A');
      expect(kb.finished.value, isFalse);
      expect(app.statusOf(ModuleId.keyboard), TestStatus.running);
    });

    test('reset clears everything', () async {
      input.send(keyEvent(internalKeyboard, 0x1E));
      input.send(keyEvent(usbKeyboard, 0x1E));
      await tick();
      kb.reset();
      expect(kb.testedCount, 0);
      expect(kb.ignoredPresses.value, 0);
    });

    test('report data lists failed, untested and ignored', () async {
      kb.markNotWorking('key_Z');
      input.send(keyEvent(usbKeyboard, 0x1E));
      await tick();
      final j = kb.toJson();
      expect(j['failed'], ['Z']);
      expect(j['ignoredExternalPresses'], 1);
      expect(j['total'], 84);
    });
  });

  test('a failure to start Raw Input is reported, not thrown', () async {
    final kb = KeyboardController(FakeRawInput(failStart: 'no window'));
    await kb.start();
    expect(kb.error.value, contains('no window'));
    expect(kb.listening.value, isFalse);
  });

  group('TouchpadController', () {
    late FakeRawInput input;
    late TouchpadController pad;
    late AppController app;
    late DateTime now;

    setUp(() async {
      input = FakeRawInput();
      now = DateTime(2026, 1, 1, 12);
      pad = TouchpadController(input, clock: () => now);
      app = Get.find<AppController>();
      await pad.start();
    });

    ActionState state(PadAction a) => pad.actions[a]!;

    test('movement counts only once enough has accumulated', () async {
      input.send(mouseEvent(touchpad, dx: 30, dy: 20));
      await tick();
      expect(state(PadAction.move), ActionState.pending);

      for (var i = 0; i < 10; i++) {
        input.send(mouseEvent(touchpad, dx: 25, dy: -15));
      }
      await tick();
      expect(state(PadAction.move), ActionState.detected);
    });

    test('left and right clicks from the touchpad tick; an external mouse does not', () async {
      input.send(mouseEvent(usbMouse, buttons: riMouseLeftDown));
      input.send(mouseEvent(usbMouse, dx: 900, dy: 900));
      await tick();
      expect(state(PadAction.leftClick), ActionState.pending);
      expect(state(PadAction.move), ActionState.pending);
      expect(pad.ignoredEvents.value, 2);

      input.send(mouseEvent(touchpad, buttons: riMouseLeftDown));
      input.send(mouseEvent(touchpad, buttons: riMouseRightDown));
      await tick();
      expect(state(PadAction.leftClick), ActionState.detected);
      expect(state(PadAction.rightClick), ActionState.detected);
    });

    test('the touchpad test has four actions: tap to click is gone', () {
      expect(PadAction.values.map((a) => a.name), ['move', 'leftClick', 'rightClick', 'scroll']);
    });

    test('an external mouse cannot be switched on', () async {
      input.send(mouseEvent(usbMouse, buttons: riMouseLeftDown));
      await tick();
      pad.setCounted(usbMouse.handle, true);
      input.send(mouseEvent(usbMouse, buttons: riMouseLeftDown));
      await tick();
      expect(pad.mice[usbMouse.handle]!.counted, isFalse);
      expect(state(PadAction.leftClick), ActionState.pending);
    });

    test('wheel from the touchpad scrolls; an external wheel is ignored', () async {
      input.send(mouseEvent(usbMouse, buttons: riMouseWheel, data: 120));
      await tick();
      expect(state(PadAction.scroll), ActionState.pending);

      input.send(mouseEvent(touchpad, buttons: riMouseWheel, data: -120));
      await tick();
      expect(state(PadAction.scroll), ActionState.detected);
    });

    test('handle-less wheel (precision gesture) counts unless an external mouse is active', () async {
      input.send(mouseEvent(usbMouse, dx: 5)); // external mouse in use right now
      input.send(mouseEvent(synthetic, buttons: riMouseWheel, data: 120));
      await tick();
      expect(state(PadAction.scroll), ActionState.pending);

      now = now.add(const Duration(seconds: 2)); // external mouse went quiet
      input.send(mouseEvent(synthetic, buttons: riMouseWheel, data: 120));
      await tick();
      expect(state(PadAction.scroll), ActionState.detected);
    });

    test('Flutter scroll gestures are believed only when no external mouse is active', () async {
      input.send(mouseEvent(usbMouse, dx: 5));
      await tick();
      pad.onFlutterScroll();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(state(PadAction.scroll), ActionState.pending);

      now = now.add(const Duration(seconds: 3));
      pad.onFlutterScroll();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(state(PadAction.scroll), ActionState.detected);
    });

    test('precision touchpad: handle-less moves and clicks count while the pad is touched', () async {
      input.send(hidEvent(precisionTouchpad, [1, 3, 0x10, 0x20]));
      await tick();
      input.send(mouseEvent(synthetic, dx: 300, dy: 200));
      input.send(mouseEvent(synthetic, buttons: riMouseRightDown));
      input.send(mouseEvent(synthetic, buttons: riMouseLeftDown));
      await tick();
      now = now.add(const Duration(milliseconds: 20));
      input.send(mouseEvent(synthetic, buttons: riMouseLeftUp));
      await tick();

      expect(state(PadAction.move), ActionState.detected);
      expect(state(PadAction.leftClick), ActionState.detected);
      expect(state(PadAction.rightClick), ActionState.detected);
      // The touchpad is listed as a counted device.
      expect(pad.mice[precisionTouchpad.handle]!.counted, isTrue);
    });

    test('once the pad reports contacts, handle-less input without a recent touch is not the pad', () async {
      input.send(hidEvent(precisionTouchpad, [1, 3, 0x10, 0x20]));
      await tick();
      now = now.add(const Duration(seconds: 3));
      input.send(mouseEvent(synthetic, buttons: riMouseLeftDown, dx: 900, dy: 900));
      await tick();
      expect(state(PadAction.leftClick), ActionState.pending);
      expect(state(PadAction.move), ActionState.pending);
    });

    test('without contact reports, handle-less input counts unless an external mouse is active', () async {
      input.send(mouseEvent(usbMouse, dx: 5));
      input.send(mouseEvent(synthetic, buttons: riMouseLeftDown));
      await tick();
      expect(state(PadAction.leftClick), ActionState.pending);

      now = now.add(const Duration(seconds: 2));
      input.send(mouseEvent(synthetic, buttons: riMouseLeftDown));
      await tick();
      expect(state(PadAction.leftClick), ActionState.detected);
    });

    test('contact reports from a touchpad switched off by hand are not trusted', () async {
      input.send(hidEvent(precisionTouchpad, [1, 3, 0x10, 0x20]));
      await tick();
      pad.setCounted(precisionTouchpad.handle, false);
      now = now.add(const Duration(seconds: 3));
      input.send(hidEvent(precisionTouchpad, [1, 3, 0x10, 0x20]));
      input.send(mouseEvent(synthetic, buttons: riMouseRightDown));
      await tick();
      expect(state(PadAction.rightClick), ActionState.pending);
    });

    test('verdict: missing actions warn, a broken action fails, all done passes', () async {
      pad.finish();
      expect(app.statusOf(ModuleId.touchpad), TestStatus.warning);

      pad.markNotWorking(PadAction.rightClick);
      pad.finish();
      expect(app.statusOf(ModuleId.touchpad), TestStatus.fail);

      for (final a in PadAction.values) {
        pad.markWorking(a);
      }
      pad.finish();
      expect(app.statusOf(ModuleId.touchpad), TestStatus.pass);
      expect(pad.toJson()['scroll'], 'manualPass');
      expect(pad.toJson().containsKey('tap'), isFalse);
    });

    test('a detected action is not downgraded by a manual "works"', () async {
      input.send(mouseEvent(touchpad, buttons: riMouseRightDown));
      await tick();
      pad.markWorking(PadAction.rightClick);
      expect(state(PadAction.rightClick), ActionState.detected);
    });
  });
}
