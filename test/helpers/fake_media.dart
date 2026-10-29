import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sollapchecker/core/media/camera_service.dart';
import 'package:sollapchecker/core/media/face_detector.dart';
import 'package:sollapchecker/core/media/window_control.dart';
import 'package:sollapchecker/core/report/file_opener.dart';

class FakeCameraSession implements CameraSession {
  bool disposed = false;

  @override
  Size? get resolution => const Size(1280, 720);

  @override
  Widget buildPreview() => const ColoredBox(color: Color(0xFF334455), child: Center(child: Text('PREVIEW')));

  int captures = 0;

  @override
  Future<String> capture() async => 'fake_frame_${captures++}.jpg';

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

/// Answers face counts from [results] in order (an exception is thrown).
/// With nothing left to answer it never completes, like a user who has not
/// looked at the camera yet, so no timers are left behind in widget tests.
class FakeFaceDetector implements FaceDetector {
  FakeFaceDetector([List<Object> results = const []]) : _results = [...results];

  final List<Object> _results;
  final seen = <String>[];

  @override
  Future<int> countFaces(String imagePath) {
    seen.add(imagePath);
    if (_results.isEmpty) return Completer<int>().future;
    final r = _results.removeAt(0);
    if (r is int) return Future.value(r);
    return Future.error(r);
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
