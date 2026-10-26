import 'package:get/get.dart';

import '../../app/app_modules.dart';
import '../../controllers/app_controller.dart';
import '../../core/models/battery_info.dart';
import '../../core/models/test_status.dart';
import '../../core/services/battery_service.dart';

/// Runs the battery check and publishes its verdict to [AppController].
class BatteryController extends GetxController {
  BatteryController([BatteryService? service]) : _service = service ?? BatteryService();

  final BatteryService _service;

  final info = Rxn<BatteryInfo>();
  final isRunning = false.obs;
  final error = RxnString();

  AppController get _app => Get.find<AppController>();

  /// Starts a check on first visit while the guided wizard is active.
  void runIfNeeded() {
    if (_app.wizardActive.value && !_app.statusOf(ModuleId.battery).isFinished && !isRunning.value) {
      run();
    }
  }

  Future<void> run() async {
    if (isRunning.value) return;
    isRunning.value = true;
    error.value = null;
    _app.setStatus(ModuleId.battery, TestStatus.running);
    try {
      final result = await _service.read();
      info.value = result;
      _app.setStatus(ModuleId.battery, result.testStatus);
    } catch (e) {
      error.value = '$e';
      _app.setStatus(ModuleId.battery, TestStatus.notTested);
    } finally {
      isRunning.value = false;
    }
  }
}
