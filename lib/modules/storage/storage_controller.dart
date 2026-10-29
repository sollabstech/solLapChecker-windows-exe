import 'package:get/get.dart';

import '../../app/app_modules.dart';
import '../../controllers/app_controller.dart';
import '../../core/models/drive_health.dart';
import '../../core/models/test_status.dart';
import '../../core/services/smartctl_service.dart';

/// Runs the storage health check and publishes its verdict to [AppController].
class StorageController extends GetxController {
  StorageController([SmartctlService? service]) : _service = service ?? SmartctlService();

  final SmartctlService _service;

  final drives = <DriveHealth>[].obs;
  final hasRun = false.obs;
  final isRunning = false.obs;
  final error = RxnString();

  /// True when the failure is specifically that smartctl.exe is not installed.
  final toolMissing = false.obs;

  AppController get _app => Get.find<AppController>();

  void runIfNeeded() {
    if (_app.wizardActive.value && !_app.statusOf(ModuleId.storage).isFinished && !isRunning.value) {
      run();
    }
  }

  Future<void> run() async {
    if (isRunning.value) return;
    isRunning.value = true;
    error.value = null;
    toolMissing.value = false;
    _app.setStatus(ModuleId.storage, TestStatus.running);
    try {
      final result = await _service.readAll();
      drives.assignAll(result);
      hasRun.value = true;
      _app.setStatus(ModuleId.storage, statusForDrives(result));
    } on SmartctlMissingException catch (e) {
      toolMissing.value = true;
      error.value = '$e';
      _app.setStatus(ModuleId.storage, TestStatus.notTested);
      _app.skipSoon(ModuleId.storage);
    } catch (e) {
      error.value = '$e';
      _app.setStatus(ModuleId.storage, TestStatus.notTested);
      _app.skipSoon(ModuleId.storage);
    } finally {
      isRunning.value = false;
    }
  }
}
