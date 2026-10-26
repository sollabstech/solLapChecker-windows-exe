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
import 'package:sollapchecker/modules/microphone/microphone_controller.dart';
import 'package:sollapchecker/modules/microphone/microphone_view.dart';
import 'package:sollapchecker/modules/speaker/speaker_controller.dart';
import 'package:sollapchecker/modules/speaker/speaker_view.dart';
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
      Get.put(WebcamController(cams));
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
      Get.put(WebcamController(cams));
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
      Get.put(WebcamController(FakeCameraService(cameras: const [])));
      await tester.pumpWidget(_host(const WebcamView()));
      await tester.pump();
      await tester.pump();
      expect(find.text('No camera detected'), findsOneWidget);
    });

    testWidgets('a camera that cannot open shows the error with Try again', (tester) async {
      _window(tester);
      Get.put(WebcamController(FakeCameraService(failOpen: 'in use by another app')));
      await tester.pumpWidget(_host(const WebcamView()));
      await tester.pump();
      await tester.pump();
      expect(find.text('The camera could not be opened'), findsOneWidget);
      expect(find.textContaining('in use by another app'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('Speaker screen', () {
    testWidgets('three channel cards; answering all yes passes, a no fails', (tester) async {
      _window(tester);
      final out = FakeAudioOutput();
      Get.put(SpeakerController(out, tempDir: tmp));
      final app = Get.find<AppController>();

      await tester.pumpWidget(_host(const SpeakerView()));
      await tester.pump();
      expect(find.text('Left channel'), findsOneWidget);
      expect(find.text('Right channel'), findsOneWidget);
      expect(find.text('Both channels'), findsOneWidget);
      expect(find.text('Play tone'), findsNWidgets(3));

      // Yes buttons, left to right
      final yes = find.text('Yes');
      expect(yes, findsNWidgets(3));
      await tester.tap(yes.at(0));
      await tester.tap(yes.at(1));
      await tester.tap(yes.at(2));
      await tester.pump();
      expect(app.statusOf(ModuleId.speaker), TestStatus.pass);

      await tester.tap(find.text('No').at(1));
      await tester.pump();
      expect(app.statusOf(ModuleId.speaker), TestStatus.fail);
    });

    testWidgets('Play tone plays the matching file', (tester) async {
      _window(tester);
      final out = FakeAudioOutput();
      Get.put(SpeakerController(out, tempDir: tmp));

      await tester.pumpWidget(_host(const SpeakerView()));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.text('Play tone').at(1));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(out.played.single, endsWith('tone_right.wav'));
    });
  });

  group('Microphone screen', () {
    testWidgets('blocked access shows how to fix it', (tester) async {
      _window(tester);
      Get.put(MicrophoneController(FakeMic(permission: false), FakeAudioOutput(), tempDir: tmp));
      await tester.pumpWidget(_host(const MicrophoneView()));
      await tester.pump();
      await tester.pump();
      expect(find.text('Microphone access is blocked'), findsOneWidget);
    });

    testWidgets('record 5 seconds, play back, answer', (tester) async {
      _window(tester);
      final mic = FakeMic();
      final out = FakeAudioOutput();
      Get.put(MicrophoneController(mic, out, recordLength: const Duration(milliseconds: 300), tempDir: tmp));
      final app = Get.find<AppController>();

      await tester.pumpWidget(_host(const MicrophoneView()));
      await tester.pump();
      await tester.pump();
      expect(find.text('Microphone Array (Realtek)'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.text('Record 5 seconds'));
        await Future<void>.delayed(const Duration(milliseconds: 60));
        mic.level(-18);
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Sound was picked up'), findsOneWidget);
      expect(find.text('Play back recording'), findsOneWidget);
      expect(find.text('Record again'), findsOneWidget);

      await tester.tap(find.text('Yes, it works'));
      await tester.pump();
      expect(app.statusOf(ModuleId.microphone), TestStatus.pass);
    });

    testWidgets('a silent recording warns the user', (tester) async {
      _window(tester);
      final mic = FakeMic();
      Get.put(MicrophoneController(mic, FakeAudioOutput(), recordLength: const Duration(milliseconds: 250), tempDir: tmp));

      await tester.pumpWidget(_host(const MicrophoneView()));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.text('Record 5 seconds'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        mic.level(-90);
        await Future<void>.delayed(const Duration(milliseconds: 450));
      });
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Almost no sound was picked up'), findsOneWidget);
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
