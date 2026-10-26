import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sollapchecker/app/app_modules.dart';
import 'package:sollapchecker/app/theme.dart';
import 'package:sollapchecker/controllers/app_controller.dart';
import 'package:sollapchecker/core/input/raw_input_event.dart';
import 'package:sollapchecker/core/models/test_status.dart';
import 'package:sollapchecker/modules/keyboard/keyboard_controller.dart';
import 'package:sollapchecker/modules/keyboard/keyboard_view.dart';
import 'package:sollapchecker/modules/touchpad/touchpad_controller.dart';
import 'package:sollapchecker/modules/touchpad/touchpad_view.dart';

import 'helpers/fake_raw_input.dart';

Widget _host(Widget child) => MaterialApp(theme: buildAppTheme(), home: Scaffold(body: child));

void _window(WidgetTester tester) {
  tester.view.physicalSize = const Size(1300, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() {
    Get.reset();
    Get.put(AppController());
  });
  tearDown(Get.reset);

  group('Keyboard screen', () {
    testWidgets('shows the count, lights keys, ignores an external keyboard, and finishes', (tester) async {
      _window(tester);
      final input = FakeRawInput();
      final kb = Get.put(KeyboardController(input));
      final app = Get.find<AppController>();

      await tester.pumpWidget(_host(const KeyboardView()));
      await tester.pump();
      expect(input.started, isTrue);
      expect(find.text('0 / 84 keys tested'), findsOneWidget);
      expect(find.text('Backspace'), findsOneWidget);
      expect(find.text('Fn'), findsOneWidget);

      input.send(keyEvent(internalKeyboard, 0x1E));
      input.send(keyEvent(internalKeyboard, 0x1F));
      input.send(keyEvent(usbKeyboard, 0x20));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('2 / 84 keys tested'), findsOneWidget);
      expect(find.text('Ignored key presses from external keyboards: 1'), findsOneWidget);
      expect(find.textContaining('ACPI PNP0303'), findsOneWidget);
      expect(find.textContaining('USB 046D:C31C'), findsOneWidget);
      expect(kb.keys['key_A'], KeyState.pressed);

      await tester.tap(find.text('Finish test'));
      await tester.pump();
      expect(app.statusOf(ModuleId.keyboard), TestStatus.warning);
    });

    testWidgets('clicking a key opens the manual menu; "not working" fails the test', (tester) async {
      _window(tester);
      final input = FakeRawInput();
      final kb = Get.put(KeyboardController(input));
      final app = Get.find<AppController>();

      await tester.pumpWidget(_host(const KeyboardView()));
      await tester.pump();

      await tester.tap(find.text('Fn'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark as working'));
      await tester.pumpAndSettle();
      expect(kb.keys['fn'], KeyState.manualPass);
      expect(find.text('1 / 84 keys tested'), findsOneWidget);

      await tester.tap(find.text('Esc'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark as NOT working'));
      await tester.pumpAndSettle();
      expect(kb.keys['esc'], KeyState.failed);
      expect(find.textContaining('1 not working'), findsOneWidget);

      await tester.tap(find.text('Finish test'));
      await tester.pump();
      expect(app.statusOf(ModuleId.keyboard), TestStatus.fail);
    });

    testWidgets('Tab and arrow keys are swallowed while the test is open', (tester) async {
      _window(tester);
      Get.put(KeyboardController(FakeRawInput()));
      await tester.pumpWidget(_host(const KeyboardView()));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('0 / 84 keys tested'), findsOneWidget);
    });

    testWidgets('leaving the screen stops listening and resets the sidebar status', (tester) async {
      _window(tester);
      final input = FakeRawInput();
      Get.put(KeyboardController(input));
      final app = Get.find<AppController>();

      await tester.pumpWidget(_host(const KeyboardView()));
      await tester.pump();
      expect(app.statusOf(ModuleId.keyboard), TestStatus.running);

      await tester.pumpWidget(_host(const SizedBox()));
      await tester.pump();
      await tester.pump();
      expect(input.started, isFalse);
      expect(app.statusOf(ModuleId.keyboard), TestStatus.notTested);
    });

    testWidgets('if Raw Input cannot start, a notice explains and manual marking still works', (tester) async {
      _window(tester);
      Get.put(KeyboardController(FakeRawInput(failStart: 'window creation failed')));
      await tester.pumpWidget(_host(const KeyboardView()));
      await tester.pump();
      await tester.pump();

      expect(find.text('Keyboard detection is unavailable'), findsOneWidget);
      expect(find.textContaining('window creation failed'), findsOneWidget);
      expect(find.text('Esc'), findsOneWidget);
    });
  });

  group('Touchpad screen', () {
    testWidgets('actions tick as they are detected; external mouse is ignored', (tester) async {
      _window(tester);
      final input = FakeRawInput();
      final pad = Get.put(TouchpadController(input));
      final app = Get.find<AppController>();

      await tester.pumpWidget(_host(const TouchpadView()));
      await tester.pump();
      expect(find.text('Move the cursor'), findsOneWidget);
      expect(find.text('Two-finger scroll'), findsOneWidget);

      input.send(mouseEvent(usbMouse, buttons: riMouseRightDown));
      input.send(mouseEvent(touchpad, buttons: riMouseRightDown));
      input.send(mouseEvent(touchpad, dx: 500, dy: 100));
      await tester.pump(const Duration(milliseconds: 400));

      expect(pad.actions[PadAction.rightClick], ActionState.detected);
      expect(pad.actions[PadAction.move], ActionState.detected);
      expect(pad.actions[PadAction.leftClick], ActionState.pending);
      expect(find.text('Ignored events from external mice: 1'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsWidgets);

      await tester.tap(find.text('Finish test'));
      await tester.pump();
      expect(app.statusOf(ModuleId.touchpad), TestStatus.warning);
    });

    testWidgets('manual thumbs confirm or fail an action', (tester) async {
      _window(tester);
      final pad = Get.put(TouchpadController(FakeRawInput()));
      final app = Get.find<AppController>();

      await tester.pumpWidget(_host(const TouchpadView()));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.thumb_up_alt_outlined).first); // move
      await tester.pump();
      expect(pad.actions[PadAction.move], ActionState.manualPass);
      expect(find.text('Confirmed by hand'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.thumb_down_alt_outlined).at(4)); // scroll
      await tester.pump();
      expect(pad.actions[PadAction.scroll], ActionState.failed);

      await tester.tap(find.text('Finish test'));
      await tester.pump();
      expect(app.statusOf(ModuleId.touchpad), TestStatus.fail);
    });
  });
}
