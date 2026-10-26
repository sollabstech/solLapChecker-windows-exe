import 'dart:async';
import 'dart:io';

import 'package:get/get.dart';

import '../../app/app_modules.dart';
import '../../controllers/app_controller.dart';
import '../../core/media/audio_output.dart';
import '../../core/media/tone_generator.dart';
import '../../core/models/test_status.dart';

/// Speaker test: a tone on the left, right and both channels; the user says
/// what they heard for each.
class SpeakerController extends GetxController {
  SpeakerController(this._output, {Directory? tempDir})
      : _dir = tempDir ?? Directory('${Directory.systemTemp.path}${Platform.pathSeparator}SolLapChecker');

  final AudioOutput _output;
  final Directory _dir;

  /// true = heard correctly, false = did not, null = not answered yet.
  final heard = <ToneChannel, bool?>{for (final c in ToneChannel.values) c: null}.obs;
  final playing = Rxn<ToneChannel>();
  final error = RxnString();

  AppController get _app => Get.find<AppController>();

  final _files = <ToneChannel, File>{};
  bool _cancelSequence = false;

  Future<File> _toneFile(ToneChannel c) async {
    final cached = _files[c];
    if (cached != null && await cached.exists()) return cached;
    await _dir.create(recursive: true);
    final f = File('${_dir.path}${Platform.pathSeparator}tone_${c.name}.wav');
    await f.writeAsBytes(buildToneWav(channel: c), flush: true);
    return _files[c] = f;
  }

  /// Plays the tone for [channel] and completes when it has finished.
  Future<void> play(ToneChannel channel) async {
    error.value = null;
    playing.value = channel;
    try {
      final file = await _toneFile(channel);
      final done = _output.completed.first.timeout(const Duration(seconds: 4), onTimeout: () {});
      await _output.playFile(file.path);
      await done;
    } catch (e) {
      error.value = 'Could not play the test tone: $e';
    } finally {
      playing.value = null;
    }
  }

  /// Left, then right, then both, with a short pause between.
  Future<void> playAll() async {
    _cancelSequence = false;
    for (final c in ToneChannel.values) {
      if (_cancelSequence) return;
      await play(c);
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  }

  Future<void> stopPlayback() async {
    _cancelSequence = true;
    await _output.stop();
    playing.value = null;
  }

  void answer(ToneChannel channel, bool heardCorrectly) {
    heard[channel] = heardCorrectly;
    _refreshStatus();
  }

  /// Any "no" fails at once; the test passes once all three are confirmed.
  void _refreshStatus() {
    final answers = heard.values.toList();
    final TestStatus status;
    if (answers.contains(false)) {
      status = TestStatus.fail;
    } else if (answers.every((a) => a == true)) {
      status = TestStatus.pass;
    } else {
      status = TestStatus.notTested;
    }
    _app.setStatus(ModuleId.speaker, status);
  }

  void reset() {
    for (final c in ToneChannel.values) {
      heard[c] = null;
    }
    _app.setStatus(ModuleId.speaker, TestStatus.notTested);
  }

  Map<String, dynamic> toJson() => {
        for (final c in ToneChannel.values)
          c.name: heard[c] == null ? null : (heard[c]! ? 'heard' : 'not heard'),
      };

  @override
  void onClose() {
    _output.stop();
    super.onClose();
  }
}
