import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sollapchecker/app/app_modules.dart';
import 'package:sollapchecker/app/theme.dart';
import 'package:sollapchecker/controllers/app_controller.dart';
import 'package:sollapchecker/core/models/test_status.dart';
import 'package:sollapchecker/modules/display/display_controller.dart';
import 'package:sollapchecker/modules/display/display_view.dart';
import 'package:sollapchecker/modules/webcam/webcam_controller.dart';
import 'package:sollapchecker/modules/webcam/webcam_view.dart';

import 'helpers/fake_media.dart';

Widget _host(Widget child) => MaterialApp(theme: buildAppTheme(), home: Scaffold(body: child));

void _window(WidgetTester tester) {
  tester.view.physicalSize = const Size(1300, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  late Directory tmp;

  setUp(() {
    Get.reset();
    Get.put(AppController());
    tmp = Directory.systemTemp.createTempSync('sollap_ui_');
  });
  tearDown(() {
    Get.reset();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('Webcam screen', () {
    testWidgets('shows the live preview, camera name and resolution; the verdict sets the status', (tester) async {
      _window(tester);
      final cams = FakeCameraService();
      Get.put(WebcamController(cams, faces: FakeFaceDetector()));
      final app = Get.find<AppController>();

      await tester.pumpWidget(_host(const WebcamView()));
      await tester.pump();
      await tester.pump();

      expect(find.text('PREVIEW'), findsOneWidget);
      expect(find.text('Integrated Camera'), findsOneWidget);
      expect(find.text('1280 × 720'), findsOneWidget);

      await tester.tap(find.text('Camera works'));
      await tester.pump();
      expect(app.statusOf(ModuleId.webcam), TestStatus.pass);

      await tester.tap(find.text('Camera not working'));
      await tester.pump();
      expect(app.statusOf(ModuleId.webcam), TestStatus.fail);
    });

    testWidgets('leaving the screen turns the camera off', (tester) async {
      _window(tester);
      final cams = FakeCameraService();
      Get.put(WebcamController(cams, faces: FakeFaceDetector()));
      await tester.pumpWidget(_host(const WebcamView()));
      await tester.pump();
      await tester.pump();

      await tester.pumpWidget(_host(const SizedBox()));
      await tester.pump();
      await tester.pump();
      expect(cams.sessions.single.disposed, isTrue);
    });

    testWidgets('no camera and open failures are explained', (tester) async {
      _window(tester);
      Get.put(WebcamController(FakeCameraService(cameras: const []), faces: FakeFaceDetector()));
      await tester.pumpWidget(_host(const WebcamView()));
      await tester.pump();
      await tester.pump();
      expect(find.text('No camera detected'), findsOneWidget);
    });

    testWidgets('a camera that cannot open shows the error with Try again', (tester) async {
      _window(tester);
      Get.put(WebcamController(FakeCameraService(failOpen: 'in use by another app'), faces: FakeFaceDetector()));
      await tester.pumpWidget(_host(const WebcamView()));
      await tester.pump();
      await tester.pump();
      expect(find.text('The camera could not be opened'), findsOneWidget);
      expect(find.textContaining('in use by another app'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('Display screen', () {
    testWidgets('fullscreen colours: click through all five, then the verdict dialog decides', (tester) async {
      _window(tester);
      final win = FakeWindowControl();
      final d = Get.put(DisplayController(win));
      final app = Get.find<AppController>();

      await tester.pumpWidget(_host(const DisplayView()));
      await tester.pump();
      expect(find.text('Start display test'), findsOneWidget);

      await tester.tap(find.text('Start display test'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(win.calls, [true]);
      expect(d.active.value, isTrue);
      expect(find.textContaining('Red'), findsWidgets);

      for (var i = 0; i < 4; i++) {
        await tester.tapAt(const Offset(650, 500));
        await tester.pump();
      }
      expect(d.current.name, 'Black');

      await tester.tapAt(const Offset(650, 500)); // past the last colour
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      expect(win.calls, [true, false]);
      expect(find.text('Did you see any problems?'), findsOneWidget);

      await tester.tap(find.text('Yes, I saw problems'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(app.statusOf(ModuleId.display), TestStatus.fail);
      expect(find.text('Display problems reported'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3)); // let hint timers finish
    });

    testWidgets('keyboard: Space advances, Esc quits early with no verdict', (tester) async {
      _window(tester);
      final win = FakeWindowControl();
      final d = Get.put(DisplayController(win));
      final app = Get.find<AppController>();

      await tester.pumpWidget(_host(const DisplayView()));
      await tester.tap(find.text('Start display test'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(d.current.name, 'Green');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(d.current.name, 'Red');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(win.calls, [true, false]);
      expect(find.text('Did you see any problems?'), findsNothing);
      expect(app.statusOf(ModuleId.display), TestStatus.notTested);
      await tester.pump(const Duration(seconds: 3));
    });
  });
}
