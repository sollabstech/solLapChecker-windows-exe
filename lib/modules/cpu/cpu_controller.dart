import 'package:get/get.dart';

import '../../app/app_modules.dart';
import '../../controllers/app_controller.dart';
import '../../core/models/stress.dart';
import '../../core/models/test_status.dart';
import '../../core/services/helper_service.dart';
import '../stress/stress_runner.dart';

/// CPU stress test: all cores at full load via SolHelper, with live
/// temperature / clock / load and throttling detection.
class CpuController extends GetxController {
  CpuController([SolHelperService? service]) : _service = service ?? SolHelperService() {
    runner = StressRunner(_service);
  }

  final SolHelperService _service;
  late final StressRunner runner;

  static const durationOptions = [1, 5, 10]; // minutes
  static const safetyLimitC = 95;

  final durationMin = 1.obs;
  final info = Rxn<HelperInfo>();

  AppController get _app => Get.find<AppController>();

  @override
  void onInit() {
    super.onInit();
    _app.registerStopper(ModuleId.cpu, stop);
  }

  /// Reads CPU name and sensor/driver state (for the setup card and driver hint).
  Future<void> loadInfo() async {
    if (info.value != null) return;
    try {
      info.value = await _service.info();
    } catch (_) {
      // Missing helper is reported when the test is started.
    }
  }

  void setDuration(int minutes) {
    if (!runner.isRunning.value) durationMin.value = minutes;
  }

  Future<void> start() async {
    if (runner.isRunning.value) return;
    final seconds = durationMin.value * 60;
    _app.setStatus(ModuleId.cpu, TestStatus.running);

    final summary = await runner.run(
      ['cpu-stress', '--duration', '$seconds', '--limit', '$safetyLimitC'],
      durationSec: seconds,
      deviceName: info.value?.cpuName,
    );
    _app.setStatus(ModuleId.cpu, summary?.status ?? TestStatus.notTested);
  }

  Future<void> stop() => runner.stop();
}
