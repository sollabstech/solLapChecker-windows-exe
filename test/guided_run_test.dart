import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sollapchecker/app/app_modules.dart';
import 'package:sollapchecker/controllers/app_controller.dart';
import 'package:sollapchecker/core/models/stress.dart';
import 'package:sollapchecker/core/models/test_status.dart';
import 'package:sollapchecker/modules/cpu/cpu_controller.dart';
import 'package:sollapchecker/modules/gpu/gpu_controller.dart';
import 'package:sollapchecker/modules/keyboard/keyboard_controller.dart';
import 'package:sollapchecker/modules/keyboard/keyboard_layout.dart';
import 'package:sollapchecker/modules/touchpad/touchpad_controller.dart';
import 'package:sollapchecker/modules/webcam/webcam_controller.dart';

import 'helpers/fake_helper.dart';
import 'helpers/fake_media.dart';
import 'helpers/fake_raw_input.dart';

const _delay = Duration(milliseconds: 30);

Future<void> wait([Duration d = Duration.zero]) => Future<void>.delayed(d);

/// Waits a little longer than the auto-advance delay.
Future<void> afterDelay() => wait(_delay * 3);

void main() {
  late AppController app;

  setUp(() {
    Get.reset();
    app = Get.put(AppController(autoAdvanceDelay: _delay));
  });
  tearDown(Get.reset);

  group('guided run', () {
    test('steps are the eight remaining tests; speaker and microphone are gone', () {
      expect(app.wizardSteps.map((m) => m.id), [
        ModuleId.battery,
        ModuleId.storage,
        ModuleId.cpu,
        ModuleId.gpu,
        ModuleId.keyboard,
        ModuleId.touchpad,
        ModuleId.webcam,
        ModuleId.display,
      ]);
    });

    test('a step with a verdict moves on by itself after the delay, not before', () async {
      app.startFullTest();
      app.setStatus(ModuleId.battery, TestStatus.running);
      app.setStatus(ModuleId.battery, TestStatus.warning);
      await wait(_delay ~/ 3);
      expect(app.selected.value, ModuleId.battery);

      await afterDelay();
      expect(app.wizardIndex.value, 1);
      expect(app.selected.value, ModuleId.storage);
    });

    test('a step that could not run is skipped after the delay', () async {
      app.startFullTest();
      app.skipSoon(ModuleId.battery);
      await afterDelay();
      expect(app.selected.value, ModuleId.storage);

      app.skipSoon(ModuleId.cpu); // not the current step: ignored
      await afterDelay();
      expect(app.selected.value, ModuleId.storage);
    });

    test('reopening a finished step cancels the move', () async {
      app.startFullTest();
      app.setStatus(ModuleId.battery, TestStatus.pass);
      app.setStatus(ModuleId.battery, TestStatus.running); // "Run again"
      await afterDelay();
      expect(app.selected.value, ModuleId.battery);
    });

    test('stopping the run cancels the move', () async {
      app.startFullTest();
      app.setStatus(ModuleId.battery, TestStatus.pass);
      app.stopWizard();
      await afterDelay();
      expect(app.selected.value, ModuleId.battery);
    });

    test('after the last step it opens Reports and asks for the report', () async {
      var completed = 0;
      app.onFullTestComplete = () => completed++;
      app.startFullTest();
      app.wizardIndex.value = app.wizardSteps.length - 1;
      app.select(ModuleId.display);

      app.setStatus(ModuleId.display, TestStatus.pass);
      await afterDelay();

      expect(app.wizardActive.value, isFalse);
      expect(app.selected.value, ModuleId.reports);
      expect(completed, 1);
    });
  });

  group('stress tests start themselves in the guided run', () {
    test('CPU: a 10 second run starts on arrival, then the run moves on', () async {
      final helper = FakeHelper();
      final cpu = Get.put(CpuController(helper)..onInit());
      app.startFullTest();
      app.wizardIndex.value = 2;
      app.select(ModuleId.cpu);

      final run = cpu.runIfNeeded();
      await wait();
      expect(helper.startedArgs.single, ['cpu-stress', '--duration', '10', '--limit', '95']);

      final s = helper.sessions.single;
      s.emit(const StressEnded(StressSummary(test: 'cpu', reason: StressEndReason.completed, maxTempC: 80, elapsedSec: 10)));
      await s.finish();
      await run;
      expect(app.statusOf(ModuleId.cpu), TestStatus.pass);

      await afterDelay();
      expect(app.selected.value, ModuleId.gpu);
    });

    test('CPU: outside the guided run nothing starts by itself', () async {
      final helper = FakeHelper();
      final cpu = Get.put(CpuController(helper)..onInit());
      await cpu.runIfNeeded();
      expect(helper.startedArgs, isEmpty);
    });

    test('CPU: a run that cannot start is skipped', () async {
      final cpu = Get.put(CpuController(FakeHelper(missing: true))..onInit());
      app.startFullTest();
      app.wizardIndex.value = 2;
      await cpu.runIfNeeded();
      await afterDelay();
      expect(app.currentWizardStep.id, ModuleId.gpu);
    });

    test('GPU: every GPU gets 10 seconds, one after another', () async {
      const igpu = GpuDevice(index: 0, name: 'Intel(R) UHD Graphics', integrated: true, hasTempSensor: true);
      const dgpu = GpuDevice(index: 1, name: 'NVIDIA GeForce RTX 2070', integrated: false, hasTempSensor: true, hasOwnTempSensor: true);
      final helper = FakeHelper(gpus: [igpu, dgpu]);
      final gpu = Get.put(GpuController(helper)..onInit());
      app.startFullTest();
      app.wizardIndex.value = 3;

      final run = gpu.runIfNeeded();
      for (var i = 0; i < 2; i++) {
        while (helper.sessions.length <= i) {
          await wait();
        }
        final s = helper.sessions[i];
        s.emit(const StressEnded(StressSummary(test: 'gpu', reason: StressEndReason.completed, maxTempC: 70, elapsedSec: 10)));
        await s.finish();
      }
      await run;

      expect(helper.startedArgs, [
        ['gpu-stress', '--gpu', '0', '--duration', '10', '--limit', '95'],
        ['gpu-stress', '--gpu', '1', '--duration', '10', '--limit', '95'],
      ]);
      expect(app.statusOf(ModuleId.gpu), TestStatus.pass);
    });
  });

  group('input tests finish themselves when everything works', () {
    test('keyboard: the last key finishes the test in the guided run', () async {
      final input = FakeRawInput();
      final kb = KeyboardController(input);
      app.startFullTest();
      await kb.start();

      for (final k in KeyboardLayout.all.where((k) => !k.manualOnly)) {
        input.send(keyEvent(internalKeyboard, k.scan!, extended: k.extended));
      }
      await wait();
      expect(kb.finished.value, isFalse); // Fn still open

      input.send(hidEvent(mediaKeys, [1, 0xE9, 0]));
      await wait();
      expect(kb.finished.value, isTrue);
      expect(app.statusOf(ModuleId.keyboard), TestStatus.pass);
    });

    test('keyboard: outside the guided run the user still presses Finish', () async {
      final input = FakeRawInput();
      final kb = KeyboardController(input);
      await kb.start();
      for (final k in KeyboardLayout.all) {
        kb.markWorking(k.id);
      }
      expect(kb.finished.value, isFalse);
    });

    test('touchpad: the fifth action finishes the test in the guided run', () async {
      final input = FakeRawInput();
      final pad = TouchpadController(input);
      app.startFullTest();
      await pad.start();
      for (final a in PadAction.values) {
        pad.markWorking(a);
      }
      expect(pad.finished.value, isTrue);
      expect(app.statusOf(ModuleId.touchpad), TestStatus.pass);
    });
  });

  group('webcam face check', () {
    test('passes by itself once a face is seen', () async {
      final faces = FakeFaceDetector([0, 0, 1]);
      final cam = WebcamController(FakeCameraService(), faces: faces, lookEvery: Duration.zero);
      await cam.start();
      while (cam.face.value != FaceState.detected) {
        await wait();
      }

      expect(faces.seen, hasLength(3));
      expect(cam.answer.value, isTrue);
      expect(app.statusOf(ModuleId.webcam), TestStatus.pass);
      expect(cam.toJson()['faceDetected'], isTrue);
    });

    test('keeps asking while no face is seen', () async {
      final cam = WebcamController(FakeCameraService(), faces: FakeFaceDetector([0]), lookEvery: Duration.zero);
      await cam.start();
      await wait(const Duration(milliseconds: 20));
      expect(cam.face.value, FaceState.looking);
      expect(app.statusOf(ModuleId.webcam), TestStatus.running);
    });

    test('when detection is unavailable the user judges by hand', () async {
      final cam = WebcamController(FakeCameraService(),
          faces: FakeFaceDetector([StateError('Windows face detection is not available')]),
          lookEvery: Duration.zero,
          retryAfter: const Duration(milliseconds: 50));
      await cam.start();
      await wait(const Duration(milliseconds: 20));

      expect(cam.face.value, FaceState.unavailable);
      expect(cam.faceError.value, contains('not available'));
      expect(app.statusOf(ModuleId.webcam), TestStatus.running);

      cam.setAnswer(true);
      expect(app.statusOf(ModuleId.webcam), TestStatus.pass);
      expect(cam.toJson()['faceDetected'], isFalse);
    });

    test('a failed check is retried, and a face seen afterwards still passes', () async {
      final faces = FakeFaceDetector([StateError('helper busy'), 0, 1]);
      final cam = WebcamController(FakeCameraService(), faces: faces, lookEvery: Duration.zero, retryAfter: Duration.zero);
      await cam.start();
      while (cam.face.value != FaceState.detected) {
        await wait();
      }
      expect(faces.seen, hasLength(3));
      expect(cam.faceError.value, isNull);
      expect(app.statusOf(ModuleId.webcam), TestStatus.pass);
    });

    test('in the guided run a detected face moves on to the next test', () async {
      final cam = WebcamController(FakeCameraService(), faces: FakeFaceDetector([1]), lookEvery: Duration.zero);
      app.startFullTest();
      app.wizardIndex.value = 6;
      app.select(ModuleId.webcam);

      await cam.start();
      await afterDelay();
      expect(app.selected.value, ModuleId.display);
    });
  });
}
