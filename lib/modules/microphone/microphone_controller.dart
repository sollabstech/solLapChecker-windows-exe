import 'dart:async';
import 'dart:io';

import 'package:get/get.dart';

import '../../app/app_modules.dart';
import '../../controllers/app_controller.dart';
import '../../core/media/audio_output.dart';
import '../../core/media/mic_recorder.dart';
import '../../core/models/test_status.dart';

enum MicPhase { idle, monitoring, recording, recorded, playing }

/// Maps a dBFS reading (0 = full scale) to 0..1 for the meter; -60 dB and
/// below is treated as silence.
double micLevelFromDb(double db) => ((db + 60) / 60).clamp(0.0, 1.0);

/// Microphone test: live level meter, a 5-second recording, playback, and the
/// user's verdict.
class MicrophoneController extends GetxController {
  MicrophoneController(
    this._mic,
    this._output, {
    this.recordLength = const Duration(seconds: 5),
    Directory? tempDir,
  }) : _dir = tempDir ?? Directory('${Directory.systemTemp.path}${Platform.pathSeparator}SolLapChecker');

  final MicRecorder _mic;
  final AudioOutput _output;
  final Duration recordLength;
  final Directory _dir;

  /// Louder than this during the recording counts as "a signal was picked up".
  static const signalThresholdDb = -45.0;

  final phase = MicPhase.idle.obs;

  /// Smoothed meter value, 0..1.
  final level = 0.0.obs;

  /// Loudest reading of the current session, in dBFS.
  final peakDb = RxnDouble();
  final secondsLeft = 0.obs;
  final devices = <String>[].obs;
  final permissionDenied = false.obs;
  final error = RxnString();

  /// true = heard the recording, false = did not, null = not answered.
  final answer = RxnBool();

  String? recordedPath;
  StreamSubscription<double>? _levelSub;
  StreamSubscription<void>? _playbackDone;
  Timer? _ticker;

  AppController get _app => Get.find<AppController>();

  bool get signalDetected => (peakDb.value ?? -160) > signalThresholdDb;

  Future<void> init() async {
    try {
      permissionDenied.value = !await _mic.hasPermission();
      devices.assignAll(await _mic.deviceNames());
    } catch (e) {
      error.value = '$e';
    }
  }

  Future<String> _newPath(String name) async {
    await _dir.create(recursive: true);
    return '${_dir.path}${Platform.pathSeparator}$name';
  }

  /// Live meter without keeping a recording.
  Future<void> startMonitor() async {
    if (phase.value == MicPhase.monitoring || phase.value == MicPhase.recording) return;
    if (!await _begin(await _newPath('mic_monitor.wav'))) return;
    phase.value = MicPhase.monitoring;
    _app.setStatus(ModuleId.microphone, TestStatus.running);
  }

  Future<void> stopMonitor() async {
    if (phase.value != MicPhase.monitoring) return;
    await _end();
    phase.value = recordedPath == null ? MicPhase.idle : MicPhase.recorded;
  }

  /// Records [recordLength] of audio with the meter running.
  Future<void> record() async {
    if (phase.value == MicPhase.recording) return;
    if (phase.value == MicPhase.monitoring) await _end();
    await _output.stop();

    final path = await _newPath('mic_test.wav');
    peakDb.value = null;
    if (!await _begin(path)) return;

    phase.value = MicPhase.recording;
    answer.value = null;
    _app.setStatus(ModuleId.microphone, TestStatus.running);

    final total = recordLength.inMilliseconds;
    secondsLeft.value = (total / 1000).ceil();
    final watch = Stopwatch()..start();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (t) async {
      final left = total - watch.elapsedMilliseconds;
      secondsLeft.value = (left / 1000).ceil().clamp(0, 99);
      if (left <= 0) {
        t.cancel();
        _ticker = null;
        final saved = await _end();
        recordedPath = saved ?? path;
        phase.value = MicPhase.recorded;
      }
    });
  }

  Future<bool> _begin(String path) async {
    error.value = null;
    try {
      if (!await _mic.hasPermission()) {
        permissionDenied.value = true;
        _app.setStatus(ModuleId.microphone, TestStatus.notTested);
        return false;
      }
      permissionDenied.value = false;
      await _mic.start(path);
      _levelSub = _mic.levels.listen(_onLevel);
      return true;
    } catch (e) {
      error.value = 'Could not start the microphone: $e';
      _app.setStatus(ModuleId.microphone, TestStatus.notTested);
      return false;
    }
  }

  Future<String?> _end() async {
    _ticker?.cancel();
    _ticker = null;
    await _levelSub?.cancel();
    _levelSub = null;
    level.value = 0;
    try {
      return await _mic.stop();
    } catch (_) {
      return null;
    }
  }

  void _onLevel(double db) {
    final v = micLevelFromDb(db);
    // Fast attack, slow decay: a steady meter that still catches peaks.
    level.value = v > level.value ? v : level.value * 0.85 + v * 0.15;
    if (peakDb.value == null || db > peakDb.value!) peakDb.value = db;
  }

  Future<void> play() async {
    final path = recordedPath;
    if (path == null || phase.value == MicPhase.playing) return;
    phase.value = MicPhase.playing;
    await _playbackDone?.cancel();
    _playbackDone = _output.completed.listen((_) {
      if (phase.value == MicPhase.playing) phase.value = MicPhase.recorded;
    });
    try {
      await _output.playFile(path);
    } catch (e) {
      error.value = 'Could not play the recording: $e';
      phase.value = MicPhase.recorded;
    }
  }

  Future<void> stopPlayback() async {
    await _output.stop();
    if (phase.value == MicPhase.playing) phase.value = MicPhase.recorded;
  }

  void setAnswer(bool heardIt) {
    answer.value = heardIt;
    _app.setStatus(ModuleId.microphone, heardIt ? TestStatus.pass : TestStatus.fail);
  }

  /// Leaving the screen: stop capture and playback; an unanswered test goes back to "Not tested".
  Future<void> stop() async {
    if (phase.value == MicPhase.monitoring || phase.value == MicPhase.recording) {
      await _end();
      phase.value = recordedPath == null ? MicPhase.idle : MicPhase.recorded;
    }
    if (phase.value == MicPhase.playing) await stopPlayback();
    if (answer.value == null) _app.setStatus(ModuleId.microphone, TestStatus.notTested);
  }

  void reset() {
    answer.value = null;
    recordedPath = null;
    peakDb.value = null;
    phase.value = MicPhase.idle;
    _app.setStatus(ModuleId.microphone, TestStatus.notTested);
  }

  Map<String, dynamic> toJson() => {
        'devices': devices.toList(),
        'peakDb': peakDb.value,
        'signalDetected': peakDb.value == null ? null : signalDetected,
        'result': answer.value == null ? null : (answer.value! ? 'heard' : 'not heard'),
      };

  @override
  void onClose() {
    _ticker?.cancel();
    _levelSub?.cancel();
    _playbackDone?.cancel();
    super.onClose();
  }
}
