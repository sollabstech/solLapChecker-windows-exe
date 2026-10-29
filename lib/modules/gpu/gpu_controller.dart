import 'package:get/get.dart';

import '../../app/app_modules.dart';
import '../../controllers/app_controller.dart';
import '../../core/models/stress.dart';
import '../../core/models/test_status.dart';
import '../../core/services/helper_service.dart';
import '../stress/stress_runner.dart';

/// GPU stress test: a Direct3D compute load on each GPU (integrated and
/// dedicated are tested separately), with live temperature.
class GpuController extends GetxController {
  GpuController([SolHelperService? service]) : _service = service ?? SolHelperService() {
    runner = StressRunner(_service);
  }

  final SolHelperService _service;
  late final StressRunner runner;

  static const durationOptions = [10, 30, 60]; // minutes
  static const safetyLimitC = 95;

  final durationMin = 10.obs;
  final info = Rxn<HelperInfo>();
  final isLoadingInfo = false.obs;
  final infoError = RxnString();

  /// Latest result per GPU index.
  final results = <int, StressSummary>{}.obs;

  /// GPU currently under test (or last tested), for labelling the live panel.
  final activeIndex = RxnInt();

  /// True while "Test all GPUs" is stepping through the list.
  final runningAll = false.obs;

  AppController get _app => Get.find<AppController>();

  List<GpuDevice> get gpus => info.value?.gpus ?? const [];

  @override
  void onInit() {
    super.onInit();
    _app.registerStopper(ModuleId.gpu, stop);
  }

  Future<void> loadInfo({bool force = false}) async {
    if (isLoadingInfo.value || (info.value != null && !force)) return;
    isLoadingInfo.value = true;
    infoError.value = null;
    try {
      info.value = await _service.info();
    } on HelperMissingException catch (e) {
      infoError.value = '$e';
    } catch (e) {
      infoError.value = '$e';
    } finally {
      isLoadingInfo.value = false;
    }
  }

  void setDuration(int minutes) {
    if (!runner.isRunning.value) durationMin.value = minutes;
  }

  /// Tests every GPU briefly on first visit while the guided wizard is active.
  Future<void> runIfNeeded() async {
    if (!_app.wizardActive.value || _app.statusOf(ModuleId.gpu).isFinished || runningAll.value) return;
    await loadInfo();
    if (gpus.isNotEmpty) await startAll(seconds: AppController.guidedStressSeconds);
    if (!_app.statusOf(ModuleId.gpu).isFinished) _app.skipSoon(ModuleId.gpu);
  }

  /// Runs [gpu] for [seconds], or for the chosen duration when not given.
  Future<void> start(GpuDevice gpu, {int? seconds}) async {
    if (runner.isRunning.value) return;
    seconds ??= durationMin.value * 60;
    activeIndex.value = gpu.index;
    _app.setStatus(ModuleId.gpu, TestStatus.running);

    final summary = await runner.run(
      ['gpu-stress', '--gpu', '${gpu.index}', '--duration', '$seconds', '--limit', '$safetyLimitC'],
      durationSec: seconds,
      deviceName: gpu.name,
    );
    if (summary != null && summary.status != TestStatus.notTested) {
      results[gpu.index] = summary;
    }
    _refreshStatus();
  }

  /// Tests every detected GPU one after another. Stops early only when a GPU
  /// itself fails; a stop caused by CPU heat moves on to the next GPU (the
  /// safety limit still protects it).
  Future<void> startAll({int? seconds}) async {
    if (runner.isRunning.value || runningAll.value) return;
    runningAll.value = true;
    try {
      for (final gpu in gpus) {
        await start(gpu, seconds: seconds);
        final r = results[gpu.index];
        if (r == null || r.status == TestStatus.fail) break;
      }
    } finally {
      runningAll.value = false;
    }
  }

  Future<void> stop() async {
    runningAll.value = false;
    await runner.stop();
  }

  /// Module verdict: any fail wins at once; otherwise every GPU must be tested.
  void _refreshStatus() {
    final all = results.values.map((r) => r.status).toList();
    TestStatus status;
    if (all.contains(TestStatus.fail)) {
      status = TestStatus.fail;
    } else if (gpus.isNotEmpty && results.length >= gpus.length) {
      status = all.contains(TestStatus.warning) ? TestStatus.warning : TestStatus.pass;
    } else {
      status = TestStatus.notTested;
    }
    _app.setStatus(ModuleId.gpu, status);
  }
}
