import 'dart:async';

import 'package:record/record.dart';

/// Microphone capture with a live level, used by the microphone test.
abstract class MicRecorder {
  /// Whether Windows lets this app use a microphone.
  Future<bool> hasPermission();

  /// Names of the available input devices (for display).
  Future<List<String>> deviceNames();

  /// Starts recording to [path] (WAV). Levels flow on [levels] while recording.
  Future<void> start(String path);

  /// Input level in dBFS: 0 is full scale, about -60 is near silence.
  Stream<double> get levels;

  /// Stops and returns the file path, or null if nothing was recorded.
  Future<String?> stop();

  Future<void> dispose();
}

class RecordPackageMic implements MicRecorder {
  final _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _amp;
  final _levels = StreamController<double>.broadcast();

  @override
  Stream<double> get levels => _levels.stream;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<List<String>> deviceNames() async {
    try {
      return (await _recorder.listInputDevices()).map((d) => d.label).toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> start(String path) async {
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 44100, numChannels: 1),
      path: path,
    );
    await _amp?.cancel();
    _amp = _recorder.onAmplitudeChanged(const Duration(milliseconds: 80)).listen((a) => _levels.add(a.current));
  }

  @override
  Future<String?> stop() async {
    await _amp?.cancel();
    _amp = null;
    return _recorder.stop();
  }

  @override
  Future<void> dispose() async {
    await _amp?.cancel();
    await _levels.close();
    await _recorder.dispose();
  }
}
