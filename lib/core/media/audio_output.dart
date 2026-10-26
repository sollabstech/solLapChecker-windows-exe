import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

/// Plays audio files through the default output device.
abstract class AudioOutput {
  /// Starts playing [path] and completes when playback has been started.
  Future<void> playFile(String path);

  /// Emits when the current file finishes by itself.
  Stream<void> get completed;

  Future<void> stop();

  Future<void> dispose();
}

class AudioPlayersOutput implements AudioOutput {
  final _player = AudioPlayer();

  @override
  Future<void> playFile(String path) async {
    await _player.stop();
    await _player.play(DeviceFileSource(path));
  }

  @override
  Stream<void> get completed => _player.onPlayerComplete;

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}
