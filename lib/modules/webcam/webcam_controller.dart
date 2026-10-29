import 'dart:io';

import 'package:get/get.dart';

import '../../app/app_modules.dart';
import '../../controllers/app_controller.dart';
import '../../core/media/camera_service.dart';
import '../../core/media/face_detector.dart';
import '../../core/models/test_status.dart';

enum FaceState {
  /// Camera not open yet.
  idle,

  /// Looking at frames, asking the user to show their face.
  looking,

  /// A face was seen: the camera works.
  detected,

  /// Detection cannot run here; the user judges the preview by hand.
  unavailable,
}

/// Webcam test: live preview, and the camera passes by itself as soon as a
/// face is seen in it. The user can still judge it by hand.
class WebcamController extends GetxController {
  WebcamController(
    this._service, {
    FaceDetector? faces,
    this.lookEvery = const Duration(milliseconds: 700),
    this.retryAfter = const Duration(seconds: 3),
  }) : _faces = faces ?? HelperFaceDetector();

  final CameraService _service;
  final FaceDetector _faces;

  /// Pause between two looks at the camera.
  final Duration lookEvery;

  /// Pause before trying again after the face check itself failed.
  final Duration retryAfter;

  final face = FaceState.idle.obs;

  /// Why detection is unavailable, when it is.
  final faceError = RxnString();

  /// Bumped whenever the camera changes, so a stale detection loop stops.
  int _lookSeq = 0;

  final cameras = <CameraInfo>[].obs;
  final selected = 0.obs;
  final session = Rxn<CameraSession>();
  final isStarting = false.obs;
  final error = RxnString();

  /// No camera device exists (or none could be listed).
  final noCamera = false.obs;

  /// The user's verdict: true = works, false = does not, null = not answered.
  final answer = RxnBool();

  AppController get _app => Get.find<AppController>();

  CameraInfo? get current => cameras.isEmpty ? null : cameras[selected.value.clamp(0, cameras.length - 1)];

  Future<void> start() async {
    if (isStarting.value || session.value != null) return;
    isStarting.value = true;
    error.value = null;
    noCamera.value = false;
    try {
      final list = await _service.list();
      cameras.assignAll(list);
      if (list.isEmpty) {
        noCamera.value = true;
        // A laptop with no working camera is worth flagging to a buyer.
        _app.setStatus(ModuleId.webcam, TestStatus.warning);
        return;
      }
      await _open(list[selected.value.clamp(0, list.length - 1)]);
    } catch (e) {
      error.value = '$e';
      _app.setStatus(ModuleId.webcam, TestStatus.notTested);
      _app.skipSoon(ModuleId.webcam);
    } finally {
      isStarting.value = false;
    }
  }

  Future<void> _open(CameraInfo cam) async {
    session.value = await _service.open(cam);
    if (answer.value == null) {
      _app.setStatus(ModuleId.webcam, TestStatus.running);
      _lookForFace();
    }
  }

  /// Grabs a frame now and then until a face shows up in one. If the check
  /// itself fails, says why (the user can judge by hand) and keeps retrying.
  Future<void> _lookForFace() async {
    final mine = ++_lookSeq;
    face.value = FaceState.looking;
    faceError.value = null;
    while (mine == _lookSeq && answer.value == null) {
      final s = session.value;
      if (s == null) return;
      try {
        final path = await s.capture();
        final count = await _faces.countFaces(path);
        _deleteQuietly(path);
        if (mine != _lookSeq || answer.value != null) return;
        if (count > 0) {
          face.value = FaceState.detected;
          setAnswer(true);
          return;
        }
        face.value = FaceState.looking;
        faceError.value = null;
      } catch (e) {
        if (mine != _lookSeq) return;
        face.value = FaceState.unavailable;
        faceError.value = '$e';
        await Future<void>.delayed(retryAfter);
        continue;
      }
      await Future<void>.delayed(lookEvery);
    }
  }

  void _deleteQuietly(String path) {
    try {
      File(path).deleteSync();
    } catch (_) {}
  }

  Future<void> select(int index) async {
    if (index == selected.value && session.value != null) return;
    selected.value = index;
    await _closeSession();
    isStarting.value = true;
    try {
      await _open(cameras[index]);
    } catch (e) {
      error.value = '$e';
    } finally {
      isStarting.value = false;
    }
  }

  void setAnswer(bool works) {
    answer.value = works;
    _app.setStatus(ModuleId.webcam, works ? TestStatus.pass : TestStatus.fail);
  }

  /// Releases the camera (the LED goes off). An unanswered test returns to "Not tested".
  Future<void> stop() async {
    await _closeSession();
    if (answer.value == null && !noCamera.value) _app.setStatus(ModuleId.webcam, TestStatus.notTested);
  }

  Future<void> _closeSession() async {
    _lookSeq++;
    if (face.value == FaceState.looking) face.value = FaceState.idle;
    final s = session.value;
    session.value = null;
    try {
      await s?.dispose();
    } catch (_) {}
  }

  void reset() {
    answer.value = null;
    face.value = FaceState.idle;
    _app.setStatus(ModuleId.webcam, session.value != null ? TestStatus.running : TestStatus.notTested);
    if (session.value != null) _lookForFace();
  }

  Map<String, dynamic> toJson() => {
        'camera': current?.name,
        'resolution': formatResolution(session.value?.resolution),
        'result': answer.value == null ? null : (answer.value! ? 'works' : 'not working'),
        'faceDetected': face.value == FaceState.detected,
        'noCamera': noCamera.value,
      };

  @override
  void onClose() {
    _closeSession();
    super.onClose();
  }
}
