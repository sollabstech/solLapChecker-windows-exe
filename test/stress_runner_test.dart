import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sollapchecker/app/app_modules.dart';
import 'package:sollapchecker/controllers/app_controller.dart';
import 'package:sollapchecker/core/models/stress.dart';
import 'package:sollapchecker/core/models/test_status.dart';
import 'package:sollapchecker/modules/cpu/cpu_controller.dart';
import 'package:sollapchecker/modules/gpu/gpu_controller.dart';
import 'package:sollapchecker/modules/stress/stress_runner.dart';

import 'helpers/fake_helper.dart';

StressSample sample(int t, double temp, {double clock = 4000, double load = 100}) =>
    StressSample(t: t, tempC: temp, clockMhz: clock, loadPct: load, cpuTempC: temp);

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  setUp(() {
    Get.reset();
    Get.put(AppController());
  });
  tearDown(Get.reset);

  group('StressRunner', () {
    test('collects samples and the final summary', () async {
      final helper = FakeHelper();
      final runner = StressRunner(helper);

      final run = runner.run(['cpu-stress'], durationSec: 60, deviceName: 'CPU');
      await settle();
      final session = helper.sessions.single;

      session.emit(const StressStarted(durationSec: 60, limitC: 95, device: 'Intel Core i7'));
      session.emit(StressSampled(sample(1, 55)));
      session.emit(StressSampled(sample(2, 60)));
      await settle();
      expect(runner.isRunning.value, isTrue);
      expect(runner.samples, hasLength(2));
      expect(runner.device.value, 'Intel Core i7');

      session.emit(const StressEnded(StressSummary(
          test: 'cpu', reason: StressEndReason.completed, maxTempC: 60, elapsedSec: 60, samples: 60)));
      await session.finish();
      final summary = await run;

      expect(runner.isRunning.value, isFalse);
      expect(summary?.status, TestStatus.pass);
      expect(summary?.device, 'Intel Core i7');
      expect(summary?.plannedSec, 60);
    });

    test('a helper that dies without a summary is reported as an error', () async {
      final helper = FakeHelper();
      final runner = StressRunner(helper);

      final run = runner.run(['cpu-stress'], durationSec: 60);
      await settle();
      helper.sessions.single.emit(StressSampled(sample(1, 50)));
      await helper.sessions.single.finish(code: 137);

      expect(await run, isNull);
      expect(runner.errorCode.value, 'helper-crashed');
      expect(runner.error.value, contains('137'));
    });

    test('an error event (no temperature sensor) is surfaced with its code', () async {
      final helper = FakeHelper();
      final runner = StressRunner(helper);

      final run = runner.run(['cpu-stress'], durationSec: 60);
      await settle();
      helper.sessions.single.emit(const StressFailed('no-temperature', 'No sensor.'));
      await helper.sessions.single.finish(code: 3);

      expect(await run, isNull);
      expect(runner.errorCode.value, 'no-temperature');
      expect(runner.error.value, 'No sensor.');
    });

    test('a missing helper is reported without crashing', () async {
      final runner = StressRunner(FakeHelper(missing: true));
      expect(await runner.run(['cpu-stress'], durationSec: 60), isNull);
      expect(runner.errorCode.value, 'helper-missing');
      expect(runner.isRunning.value, isFalse);
    });

    test('stop asks the helper to stop and yields a "stopped" summary', () async {
      final helper = FakeHelper();
      final runner = StressRunner(helper);

      final run = runner.run(['cpu-stress'], durationSec: 300);
      await settle();
      await runner.stop();
      final summary = await run;

      expect(helper.sessions.single.stopRequested, isTrue);
      expect(summary?.reason, StressEndReason.stopped);
      expect(summary?.status, TestStatus.notTested);
    });
  });

  group('CpuController', () {
    test('builds the helper command and publishes the verdict', () async {
      final helper = FakeHelper();
      final cpu = CpuController(helper)..onInit();
      cpu.setDuration(5);
      final app = Get.find<AppController>();

      final run = cpu.start();
      await settle();
      expect(helper.startedArgs.single, ['cpu-stress', '--duration', '300', '--limit', '95']);
      expect(app.statusOf(ModuleId.cpu), TestStatus.running);
      expect(app.runningStress, ModuleId.cpu);

      final s = helper.sessions.single;
      s.emit(const StressEnded(StressSummary(
          test: 'cpu', reason: StressEndReason.completed, maxTempC: 93, throttled: true, elapsedSec: 300)));
      await s.finish();
      await run;

      expect(app.statusOf(ModuleId.cpu), TestStatus.warning);
      expect(app.runningStress, isNull);
    });

    test('a CPU safety stop at the temperature limit is a warning', () async {
      final helper = FakeHelper();
      final cpu = CpuController(helper)..onInit();
      final app = Get.find<AppController>();

      final run = cpu.start();
      await settle();
      final s = helper.sessions.single;
      s.emit(const StressEnded(StressSummary(
          test: 'cpu', reason: StressEndReason.safety, maxTempC: 96, message: 'Reached 96 °C (limit 95 °C).')));
      await s.finish();
      await run;

      expect(app.statusOf(ModuleId.cpu), TestStatus.warning);
    });

    test('the global stop hook stops the running test', () async {
      final helper = FakeHelper();
      final cpu = CpuController(helper)..onInit();
      final app = Get.find<AppController>();

      final run = cpu.start();
      await settle();
      await app.stopRunning();
      await run;

      expect(helper.sessions.single.stopRequested, isTrue);
      expect(app.statusOf(ModuleId.cpu), TestStatus.notTested);
    });

    test('duration cannot change while running', () async {
      final helper = FakeHelper();
      final cpu = CpuController(helper)..onInit();
      final run = cpu.start();
      await settle();
      expect(cpu.durationMin.value, 10); // the default
      cpu.setDuration(60);
      expect(cpu.durationMin.value, 10);
      await cpu.stop();
      await run;
    });
  });

  group('GpuController', () {
    const igpu = GpuDevice(index: 0, name: 'Intel UHD', integrated: true, hasTempSensor: true);
    const dgpu = GpuDevice(index: 1, name: 'NVIDIA RTX', integrated: false, dedicatedMb: 6144, hasTempSensor: true, hasOwnTempSensor: true);

    StressSummary done(double max, {StressEndReason reason = StressEndReason.completed, bool throttled = false}) =>
        StressSummary(test: 'gpu', reason: reason, maxTempC: max, throttled: throttled, elapsedSec: 60);

    Future<void> finishNext(FakeHelper helper, StressSummary summary) async {
      await settle();
      final s = helper.sessions.last;
      s.emit(StressEnded(summary));
      await s.finish();
      await settle();
    }

    test('integrated and dedicated GPUs are tested separately; verdict waits for all', () async {
      final helper = FakeHelper(gpus: [igpu, dgpu]);
      final gpu = GpuController(helper)..onInit();
      await gpu.loadInfo();
      final app = Get.find<AppController>();

      final r1 = gpu.start(igpu);
      await finishNext(helper, done(70));
      await r1;
      expect(helper.startedArgs.last, ['gpu-stress', '--gpu', '0', '--duration', '600', '--limit', '95']);
      expect(app.statusOf(ModuleId.gpu), TestStatus.notTested); // dedicated not tested yet

      final r2 = gpu.start(dgpu);
      await finishNext(helper, done(88));
      await r2;
      expect(helper.startedArgs.last[2], '1');
      expect(app.statusOf(ModuleId.gpu), TestStatus.pass);
    });

    test('one failing GPU fails the module immediately', () async {
      final helper = FakeHelper(gpus: [igpu, dgpu]);
      final gpu = GpuController(helper)..onInit();
      await gpu.loadInfo();

      final r = gpu.start(dgpu);
      await finishNext(helper, done(96, reason: StressEndReason.safety));
      await r;

      expect(Get.find<AppController>().statusOf(ModuleId.gpu), TestStatus.fail);
    });

    test('Test all GPUs carries on when only the CPU got too hot', () async {
      final helper = FakeHelper(gpus: [igpu, dgpu]);
      final gpu = GpuController(helper)..onInit();
      await gpu.loadInfo();

      final all = gpu.startAll();
      // Integrated GPU: no sensor of its own, stopped because the CPU package hit the limit.
      await finishNext(helper, const StressSummary(
          test: 'gpu', reason: StressEndReason.safety, maxCpuTempC: 95, message: 'Reached 95 °C (limit 95 °C).'));
      await finishNext(helper, done(70));
      await all;

      expect(helper.sessions, hasLength(2));
      expect(gpu.results[0]!.status, TestStatus.warning);
      expect(Get.find<AppController>().statusOf(ModuleId.gpu), TestStatus.warning);
    });

    test('Test all GPUs runs them in order and stops after a GPU itself overheats', () async {
      final helper = FakeHelper(gpus: [igpu, dgpu]);
      final gpu = GpuController(helper)..onInit();
      await gpu.loadInfo();

      final all = gpu.startAll();
      await finishNext(helper, done(96, reason: StressEndReason.safety)); // first GPU aborts
      await all;

      expect(helper.sessions, hasLength(1)); // second GPU never started
      expect(gpu.runningAll.value, isFalse);
    });

    test('a missing helper is reported when loading GPUs', () async {
      final gpu = GpuController(FakeHelper(missing: true))..onInit();
      await gpu.loadInfo();
      expect(gpu.infoError.value, contains('SolHelper.exe was not found'));
      expect(gpu.gpus, isEmpty);
    });
  });
}
