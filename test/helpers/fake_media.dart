import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sollapchecker/core/media/audio_output.dart';
import 'package:sollapchecker/core/media/camera_service.dart';
import 'package:sollapchecker/core/media/mic_recorder.dart';
import 'package:sollapchecker/core/media/window_control.dart';
import 'package:sollapchecker/core/report/file_opener.dart';

class FakeAudioOutput implements AudioOutput {
  final played = <String>[];
  final _done = StreamController<void>.broadcast();
  bool stopped = false;

  /// When true, playback "finishes" by itself right after it starts.
  bool autoComplete = true;

  @override
  Stream<void> get completed => _done.stream;

  void finish() => _done.add(null);

  @override
  Future<void> playFile(String path) async {
    played.add(path);
    stopped = false;
    if (autoComplete) Future<void>.delayed(const Duration(milliseconds: 5), finish);
  }

  @override
  Future<void> stop() async => stopped = true;

  @override
  Future<void> dispose() async {}
}

class FakeMic implements MicRecorder {
  FakeMic({this.permission = true, this.names = const ['Microphone Array (Realtek)'], this.failStart});

  bool permission;
  final List<String> names;
  final String? failStart;
  final _levels = StreamController<double>.broadcast();
  String? startedPath;
  bool recording = false;

  @override
  Stream<double> get levels => _levels.stream;

  void level(double db) => _levels.add(db);

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<List<String>> deviceNames() async => names;

  @override
  Future<void> start(String path) async {
    if (failStart != null) throw StateError(failStart!);
    startedPath = path;
    recording = true;
  }

  @override
  Future<String?> stop() async {
    recording = false;
    return startedPath;
  }

  @override
  Future<void> dispose() async {}
}

class FakeCameraSession implements CameraSession {
  bool disposed = false;

  @override
  Size? get resolution => const Size(1280, 720);

  @override
  Widget buildPreview() => const ColoredBox(color: Color(0xFF334455), child: Center(child: Text('PREVIEW')));

  @override
  Future<void> dispose() async => disposed = true;
}

class FakeCameraService implements CameraService {
  FakeCameraService({this.cameras = const [CameraInfo(name: 'Integrated Camera')], this.failOpen});

  final List<CameraInfo> cameras;
  final String? failOpen;
  final sessions = <FakeCameraSession>[];

  @override
  Future<List<CameraInfo>> list() async => cameras;

  @override
  Future<CameraSession> open(CameraInfo camera) async {
    if (failOpen != null) throw StateError(failOpen!);
    final s = FakeCameraSession();
    sessions.add(s);
    return s;
  }
}

class FakeWindowControl implements WindowControl {
  final calls = <bool>[];

  @override
  Future<void> setFullScreen(bool value) async => calls.add(value);
}

/// Records file opens instead of launching Explorer.
class FakeFileOpener implements FileOpener {
  final opened = <String>[];
  final revealed = <String>[];
  String? failWith;

  @override
  Future<void> open(String path) async {
    if (failWith != null) throw StateError(failWith!);
    opened.add(path);
  }

  @override
  Future<void> reveal(String path) async {
    if (failWith != null) throw StateError(failWith!);
    revealed.add(path);
  }
}
