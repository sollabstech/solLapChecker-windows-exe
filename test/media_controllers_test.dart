import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sollapchecker/app/app_modules.dart';
import 'package:sollapchecker/controllers/app_controller.dart';
import 'package:sollapchecker/core/media/camera_service.dart';
import 'package:sollapchecker/core/media/tone_generator.dart';
import 'package:sollapchecker/core/models/test_status.dart';
import 'package:sollapchecker/modules/display/display_controller.dart';
import 'package:sollapchecker/modules/microphone/microphone_controller.dart';
import 'package:sollapchecker/modules/speaker/speaker_controller.dart';
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

  group('tone generator', () {
    /// Peak absolute sample per channel.
    (int, int) peaks(Uint8List wav) {
      final d = ByteData.sublistView(wav);
      var l = 0, r = 0;
      for (var o = 44; o + 3 < wav.length; o += 4) {
        l = l < d.getInt16(o, Endian.little).abs() ? d.getInt16(o, Endian.little).abs() : l;
        r = r < d.getInt16(o + 2, Endian.little).abs() ? d.getInt16(o + 2, Endian.little).abs() : r;
      }
      return (l, r);
    }

    test('writes a valid 16-bit stereo PCM header and the right length', () {
      final wav = buildToneWav(channel: ToneChannel.both, seconds: 1.0);
      final d = ByteData.sublistView(wav);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(d.getUint16(20, Endian.little), 1); // PCM
      expect(d.getUint16(22, Endian.little), 2); // stereo
      expect(d.getUint32(24, Endian.little), 44100);
      expect(d.getUint16(34, Endian.little), 16);
      expect(d.getUint32(40, Endian.little), 44100 * 4);
      expect(wav.length, 44 + 44100 * 4);
      expect(d.getUint32(4, Endian.little), wav.length - 8);
    });

    test('left plays only on the left, right only on the right, both on both', () {
      final (ll, lr) = peaks(buildToneWav(channel: ToneChannel.left));
      expect(ll, greaterThan(10000));
      expect(lr, 0);

      final (rl, rr) = peaks(buildToneWav(channel: ToneChannel.right));
      expect(rl, 0);
      expect(rr, greaterThan(10000));

      final (bl, br) = peaks(buildToneWav(channel: ToneChannel.both));
      expect(bl, greaterThan(10000));
      expect(br, bl);
    });

    test('amplitude is limited (not full scale) and the tone fades in and out', () {
      final wav = buildToneWav(channel: ToneChannel.both);
      final (l, _) = peaks(wav);
      expect(l, lessThan(32767 * 0.45));
      final d = ByteData.sublistView(wav);
      expect(d.getInt16(44, Endian.little), 0); // starts at silence
      expect(d.getInt16(wav.length - 4, Endian.little).abs(), lessThan(300)); // ends near silence
    });
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
      final cam = WebcamController(cams);
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
      final cam = WebcamController(FakeCameraService(cameras: const []));
      await cam.start();
      expect(cam.noCamera.value, isTrue);
      expect(cam.session.value, isNull);
      expect(Get.find<AppController>().statusOf(ModuleId.webcam), TestStatus.warning);
    });

    test('a camera that cannot be opened reports the error', () async {
      final cam = WebcamController(FakeCameraService(failOpen: 'in use'));
      await cam.start();
      expect(cam.error.value, contains('in use'));
      expect(Get.find<AppController>().statusOf(ModuleId.webcam), TestStatus.notTested);
    });

    test('stop releases the camera; an unanswered test returns to Not tested', () async {
      final cams = FakeCameraService();
      final cam = WebcamController(cams);
      await cam.start();
      await cam.stop();
      expect(cams.sessions.single.disposed, isTrue);
      expect(cam.session.value, isNull);
      expect(Get.find<AppController>().statusOf(ModuleId.webcam), TestStatus.notTested);
    });

    test('an answered verdict survives leaving the screen', () async {
      final cam = WebcamController(FakeCameraService());
      await cam.start();
      cam.setAnswer(true);
      await cam.stop();
      expect(Get.find<AppController>().statusOf(ModuleId.webcam), TestStatus.pass);
    });

    test('switching cameras closes the old session and opens the new one', () async {
      final cams = FakeCameraService(cameras: const [CameraInfo(name: 'Front'), CameraInfo(name: 'IR')]);
      final cam = WebcamController(cams);
      await cam.start();
      await cam.select(1);
      expect(cams.sessions, hasLength(2));
      expect(cams.sessions.first.disposed, isTrue);
      expect(cam.current!.name, 'IR');
    });
  });

  group('SpeakerController', () {
    test('plays a tone file per channel and waits for it to finish', () async {
      final out = FakeAudioOutput();
      final sp = SpeakerController(out, tempDir: tmp);

      await sp.play(ToneChannel.left);
      expect(out.played.single, endsWith('tone_left.wav'));
      expect(File(out.played.single).lengthSync(), greaterThan(44));
      expect(sp.playing.value, isNull);

      await sp.play(ToneChannel.right);
      expect(out.played.last, endsWith('tone_right.wav'));
    });

    test('Play all runs left, right, both in order', () async {
      final out = FakeAudioOutput();
      final sp = SpeakerController(out, tempDir: tmp);
      await sp.playAll();
      expect(out.played.map((p) => p.split(Platform.pathSeparator).last), ['tone_left.wav', 'tone_right.wav', 'tone_both.wav']);
    });

    test('three yeses pass; any no fails immediately; unanswered stays Not tested', () async {
      final sp = SpeakerController(FakeAudioOutput(), tempDir: tmp);
      final app = Get.find<AppController>();

      sp.answer(ToneChannel.left, true);
      sp.answer(ToneChannel.right, true);
      expect(app.statusOf(ModuleId.speaker), TestStatus.notTested);

      sp.answer(ToneChannel.both, true);
      expect(app.statusOf(ModuleId.speaker), TestStatus.pass);

      sp.answer(ToneChannel.right, false);
      expect(app.statusOf(ModuleId.speaker), TestStatus.fail);
      expect(sp.toJson()['right'], 'not heard');

      sp.reset();
      expect(app.statusOf(ModuleId.speaker), TestStatus.notTested);
    });

    test('a failure to play is reported', () async {
      final out = _ThrowingOutput();
      final sp = SpeakerController(out, tempDir: tmp);
      await sp.play(ToneChannel.both);
      expect(sp.error.value, contains('Could not play'));
      expect(sp.playing.value, isNull);
    });
  });

  group('MicrophoneController', () {
    late FakeMic mic;
    late FakeAudioOutput out;
    late MicrophoneController c;

    setUp(() {
      mic = FakeMic();
      out = FakeAudioOutput();
      c = MicrophoneController(mic, out, recordLength: const Duration(milliseconds: 350), tempDir: tmp);
    });

    test('level mapping: -60 dB or lower is silent, 0 dB is full', () {
      expect(micLevelFromDb(-80), 0);
      expect(micLevelFromDb(-60), 0);
      expect(micLevelFromDb(-30), closeTo(0.5, 1e-9));
      expect(micLevelFromDb(0), 1);
      expect(micLevelFromDb(6), 1);
    });

    test('init lists devices and detects blocked access', () async {
      await c.init();
      expect(c.devices, ['Microphone Array (Realtek)']);
      expect(c.permissionDenied.value, isFalse);

      final blocked = MicrophoneController(FakeMic(permission: false), out, tempDir: tmp);
      await blocked.init();
      expect(blocked.permissionDenied.value, isTrue);
    });

    test('monitoring shows a live level and keeps no recording', () async {
      await c.startMonitor();
      expect(c.phase.value, MicPhase.monitoring);
      mic.level(-20);
      mic.level(-10);
      await tick();
      expect(c.level.value, greaterThan(0.7));
      expect(c.peakDb.value, -10);

      await c.stopMonitor();
      expect(c.phase.value, MicPhase.idle);
      expect(c.level.value, 0);
    });

    test('recording runs for the set length, then offers playback', () async {
      await c.record();
      expect(c.phase.value, MicPhase.recording);
      expect(mic.startedPath, endsWith('mic_test.wav'));
      mic.level(-25);
      await tick(600);

      expect(c.phase.value, MicPhase.recorded);
      expect(mic.recording, isFalse);
      expect(c.recordedPath, endsWith('mic_test.wav'));
      expect(c.signalDetected, isTrue);

      await c.play();
      expect(c.phase.value, MicPhase.playing);
      expect(out.played.single, endsWith('mic_test.wav'));
      await tick(60);
      expect(c.phase.value, MicPhase.recorded); // playback finished
    });

    test('a silent recording is flagged', () async {
      await c.record();
      mic.level(-90);
      await tick(600);
      expect(c.signalDetected, isFalse);
    });

    test('the verdict sets the status', () async {
      final app = Get.find<AppController>();
      await c.record();
      await tick(600);
      c.setAnswer(true);
      expect(app.statusOf(ModuleId.microphone), TestStatus.pass);
      c.setAnswer(false);
      expect(app.statusOf(ModuleId.microphone), TestStatus.fail);
    });

    test('blocked access does not start recording and leaves the test unrun', () async {
      final blocked = MicrophoneController(FakeMic(permission: false), out, tempDir: tmp);
      await blocked.record();
      expect(blocked.phase.value, MicPhase.idle);
      expect(blocked.permissionDenied.value, isTrue);
    });

    test('a microphone that fails to start is reported', () async {
      final broken = MicrophoneController(FakeMic(failStart: 'device busy'), out, tempDir: tmp);
      await broken.startMonitor();
      expect(broken.error.value, contains('device busy'));
      expect(broken.phase.value, MicPhase.idle);
    });

    test('leaving the screen stops capture and returns an unanswered test to Not tested', () async {
      await c.startMonitor();
      await c.stop();
      expect(mic.recording, isFalse);
      expect(c.phase.value, MicPhase.idle);
      expect(Get.find<AppController>().statusOf(ModuleId.microphone), TestStatus.notTested);
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

class _ThrowingOutput extends FakeAudioOutput {
  @override
  Future<void> playFile(String path) async => throw StateError('no audio device');
}
