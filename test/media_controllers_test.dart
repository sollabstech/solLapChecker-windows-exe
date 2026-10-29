import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sollapchecker/app/app_modules.dart';
import 'package:sollapchecker/controllers/app_controller.dart';
import 'package:sollapchecker/core/media/camera_service.dart';
import 'package:sollapchecker/core/models/test_status.dart';
import 'package:sollapchecker/modules/display/display_controller.dart';
import 'package:sollapchecker/modules/webcam/webcam_controller.dart';

import 'helpers/fake_media.dart';

Future<void> tick([int ms = 0]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late Directory tmp;

  setUp(() {
    Get.reset();
    Get.put(AppController());
    tmp = Directory.systemTemp.createTempSync('sollap_test_');
  });
  tearDown(() {
    Get.reset();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('camera helpers', () {
    test('cleans the device path off Windows camera names', () {
      expect(cleanCameraName(r'Integrated Camera <\\?\usb#vid_0bda&pid_5634&mi_00#6&1>'), 'Integrated Camera');
      expect(cleanCameraName('HD Webcam'), 'HD Webcam');
      expect(cleanCameraName(' <path>'), 'Camera');
    });
  });

  group('WebcamController', () {
    test('opens the first camera and waits for the verdict', () async {
      final cams = FakeCameraService();
      final cam = WebcamController(cams, faces: FakeFaceDetector());
      final app = Get.find<AppController>();

      await cam.start();
      expect(cam.session.value, isNotNull);
      expect(cam.current!.name, 'Integrated Camera');
      expect(app.statusOf(ModuleId.webcam), TestStatus.running);

      cam.setAnswer(true);
      expect(app.statusOf(ModuleId.webcam), TestStatus.pass);
      cam.setAnswer(false);
      expect(app.statusOf(ModuleId.webcam), TestStatus.fail);
      expect(cam.toJson()['resolution'], '1280 × 720');
    });

    test('no camera is a warning, not an error', () async {
      final cam = WebcamController(FakeCameraService(cameras: const []), faces: FakeFaceDetector());
      await cam.start();
      expect(cam.noCamera.value, isTrue);
      expect(cam.session.value, isNull);
      expect(Get.find<AppController>().statusOf(ModuleId.webcam), TestStatus.warning);
    });

    test('a camera that cannot be opened reports the error', () async {
      final cam = WebcamController(FakeCameraService(failOpen: 'in use'), faces: FakeFaceDetector());
      await cam.start();
      expect(cam.error.value, contains('in use'));
      expect(Get.find<AppController>().statusOf(ModuleId.webcam), TestStatus.notTested);
    });

    test('stop releases the camera; an unanswered test returns to Not tested', () async {
      final cams = FakeCameraService();
      final cam = WebcamController(cams, faces: FakeFaceDetector());
      await cam.start();
      await cam.stop();
      expect(cams.sessions.single.disposed, isTrue);
      expect(cam.session.value, isNull);
      expect(Get.find<AppController>().statusOf(ModuleId.webcam), TestStatus.notTested);
    });

    test('an answered verdict survives leaving the screen', () async {
      final cam = WebcamController(FakeCameraService(), faces: FakeFaceDetector());
      await cam.start();
      cam.setAnswer(true);
      await cam.stop();
      expect(Get.find<AppController>().statusOf(ModuleId.webcam), TestStatus.pass);
    });

    test('switching cameras closes the old session and opens the new one', () async {
      final cams = FakeCameraService(cameras: const [CameraInfo(name: 'Front'), CameraInfo(name: 'IR')]);
      final cam = WebcamController(cams, faces: FakeFaceDetector());
      await cam.start();
      await cam.select(1);
      expect(cams.sessions, hasLength(2));
      expect(cams.sessions.first.disposed, isTrue);
      expect(cam.current!.name, 'IR');
    });
  });

  group('DisplayController', () {
    test('goes fullscreen, steps through five colours, and exits fullscreen at the end', () async {
      final win = FakeWindowControl();
      final d = DisplayController(win);

      await d.begin();
      expect(d.active.value, isTrue);
      expect(win.calls, [true]);
      expect(d.current.name, 'Red');

      for (var i = 0; i < 4; i++) {
        await d.next();
      }
      expect(d.current.name, 'Black');
      expect(d.sequenceCompleted.value, isFalse);

      await d.next(); // past the last colour
      expect(d.sequenceCompleted.value, isTrue);
      expect(d.active.value, isFalse);
      expect(win.calls, [true, false]);
    });

    test('previous goes back but not before the first colour', () async {
      final d = DisplayController(FakeWindowControl());
      await d.begin();
      d.previous();
      expect(d.index.value, 0);
      await d.next();
      await d.next();
      d.previous();
      expect(d.index.value, 1);
    });

    test('quitting early leaves the test unfinished with no verdict', () async {
      final d = DisplayController(FakeWindowControl());
      final app = Get.find<AppController>();
      await d.begin();
      expect(app.statusOf(ModuleId.display), TestStatus.running);
      await d.next();
      await d.exit();
      expect(d.sequenceCompleted.value, isFalse);
      expect(app.statusOf(ModuleId.display), TestStatus.notTested);
    });

    test('the user verdict after a full run decides pass or fail', () async {
      final d = DisplayController(FakeWindowControl());
      final app = Get.find<AppController>();
      await d.begin();
      for (var i = 0; i < 5; i++) {
        await d.next();
      }
      d.setAnswer(true);
      expect(app.statusOf(ModuleId.display), TestStatus.pass);
      d.setAnswer(false);
      expect(app.statusOf(ModuleId.display), TestStatus.fail);
      expect(d.toJson()['colorsChecked'], ['Red', 'Green', 'Blue', 'White', 'Black']);
    });
  });
}
