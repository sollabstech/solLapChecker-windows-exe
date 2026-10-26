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

    test('a device can be switched on by hand (misclassified internal keyboard)', () async {
      input.send(keyEvent(usbKeyboard, 0x1E));
      await tick();
      kb.setCounted(200, true);
      input.send(keyEvent(usbKeyboard, 0x1E));
      await tick();
      expect(kb.keys['key_A'], KeyState.pressed);
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

    test('a quick touch-and-lift is a tap; a held press is not', () async {
      // Events are delivered asynchronously, so let each one land before the clock moves.
      input.send(mouseEvent(touchpad, buttons: riMouseLeftDown));
      await tick();
      now = now.add(const Duration(milliseconds: 150));
      input.send(mouseEvent(touchpad, buttons: riMouseLeftUp));
      await tick();
      expect(state(PadAction.tap), ActionState.pending); // a real press

      input.send(mouseEvent(touchpad, buttons: riMouseLeftDown));
      await tick();
      now = now.add(const Duration(milliseconds: 40));
      input.send(mouseEvent(touchpad, buttons: riMouseLeftUp));
      await tick();
      expect(state(PadAction.tap), ActionState.detected);
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

    test('handle-less clicks and moves are never attributed to the touchpad', () async {
      input.send(mouseEvent(synthetic, buttons: riMouseLeftDown, dx: 900, dy: 900));
      await tick();
      expect(state(PadAction.leftClick), ActionState.pending);
      expect(state(PadAction.move), ActionState.pending);
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
      expect(pad.toJson()['tap'], 'manualPass');
    });

    test('a detected action is not downgraded by a manual "works"', () async {
      input.send(mouseEvent(touchpad, buttons: riMouseRightDown));
      await tick();
      pad.markWorking(PadAction.rightClick);
      expect(state(PadAction.rightClick), ActionState.detected);
    });
  });
}
