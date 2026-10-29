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

  static const durationOptions = [10, 30, 60]; // minutes
  static const safetyLimitC = 95;

  final durationMin = 10.obs;
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

  /// Starts a short run on first visit while the guided wizard is active.
  Future<void> runIfNeeded() async {
    if (!_app.wizardActive.value || _app.statusOf(ModuleId.cpu).isFinished || runner.isRunning.value) return;
    await loadInfo();
    await start(seconds: AppController.guidedStressSeconds);
    if (!_app.statusOf(ModuleId.cpu).isFinished) _app.skipSoon(ModuleId.cpu);
  }

  /// Runs for [seconds], or for the chosen duration when not given.
  Future<void> start({int? seconds}) async {
    if (runner.isRunning.value) return;
    seconds ??= durationMin.value * 60;
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
