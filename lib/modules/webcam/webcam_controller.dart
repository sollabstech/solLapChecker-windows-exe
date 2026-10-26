import 'package:get/get.dart';

import '../../app/app_modules.dart';
import '../../controllers/app_controller.dart';
import '../../core/media/camera_service.dart';
import '../../core/models/test_status.dart';

/// Webcam test: live preview, then the user judges it.
class WebcamController extends GetxController {
  WebcamController(this._service);

  final CameraService _service;

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
    } finally {
      isStarting.value = false;
    }
  }

  Future<void> _open(CameraInfo cam) async {
    session.value = await _service.open(cam);
    if (answer.value == null) _app.setStatus(ModuleId.webcam, TestStatus.running);
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
    final s = session.value;
    session.value = null;
    try {
      await s?.dispose();
    } catch (_) {}
  }

  void reset() {
    answer.value = null;
    _app.setStatus(ModuleId.webcam, session.value != null ? TestStatus.running : TestStatus.notTested);
  }

  Map<String, dynamic> toJson() => {
        'camera': current?.name,
        'resolution': formatResolution(session.value?.resolution),
        'result': answer.value == null ? null : (answer.value! ? 'works' : 'not working'),
        'noCamera': noCamera.value,
      };

  @override
  void onClose() {
    _closeSession();
    super.onClose();
  }
}
