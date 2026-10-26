import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sollapchecker/app/app_modules.dart';
import 'package:sollapchecker/app/theme.dart';
import 'package:sollapchecker/controllers/app_controller.dart';
import 'package:sollapchecker/core/models/stress.dart';
import 'package:sollapchecker/core/models/test_status.dart';
import 'package:sollapchecker/modules/cpu/cpu_controller.dart';
import 'package:sollapchecker/modules/cpu/cpu_view.dart';
import 'package:sollapchecker/modules/gpu/gpu_controller.dart';
import 'package:sollapchecker/modules/gpu/gpu_view.dart';
import 'package:sollapchecker/widgets/active_test_bar.dart';

import 'helpers/fake_helper.dart';

Widget _host(Widget child) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: Column(children: [const ActiveTestBar(), Expanded(child: child)])),
    );

void _bigWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1300, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() {
    Get.reset();
    Get.put(AppController());
  });
  tearDown(Get.reset);

  testWidgets('CPU screen: start, live numbers, always-visible Stop, then verdict', (tester) async {
    _bigWindow(tester);
    final helper = FakeHelper();
    Get.put(CpuController(helper)..onInit());
    final app = Get.find<AppController>();

    await tester.pumpWidget(_host(const CpuView()));
    await tester.pump();
    expect(find.text('Start stress test'), findsOneWidget);
    expect(find.text('Stop'), findsNothing);

    // choose 5 minutes, start
    await tester.tap(find.text('5 min'));
    await tester.pump();
    await tester.tap(find.text('Start stress test'));
    await tester.pump();
    expect(helper.startedArgs.single, contains('300'));

    final s = helper.sessions.single;
    s.emit(const StressStarted(durationSec: 300, limitC: 95, device: 'Intel Core i7'));
    for (var t = 1; t <= 4; t++) {
      s.emit(StressSampled(StressSample(t: t, tempC: 55.0 + t * 5, clockMhz: 4200, loadPct: 100, cpuTempC: 55.0 + t * 5)));
    }
    await tester.pump(const Duration(milliseconds: 50));

    // live figures + the global Stop bar (visible regardless of scroll position)
    expect(find.text('75'), findsWidgets); // current temp 55+4*5
    expect(find.text('Stop'), findsOneWidget); // ActiveTestBar
    expect(find.text('Stop test'), findsOneWidget); // setup card
    expect(find.textContaining('Elapsed 0:04'), findsOneWidget);
    expect(find.text('Checking…'), findsOneWidget);
    expect(app.statusOf(ModuleId.cpu), TestStatus.running);

    // finish
    s.emit(const StressEnded(StressSummary(
        test: 'cpu', reason: StressEndReason.completed, maxTempC: 75, avgTempC: 66, elapsedSec: 300, maxClockMhz: 4200, minClockMhz: 4100)));
    await s.finish();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Passed'), findsWidgets);
    expect(find.text('Run again'), findsOneWidget);
    expect(find.text('Stop'), findsNothing);
    expect(app.statusOf(ModuleId.cpu), TestStatus.pass);
  });

  testWidgets('CPU screen: Stop button ends the run and leaves no verdict', (tester) async {
    _bigWindow(tester);
    final helper = FakeHelper();
    Get.put(CpuController(helper)..onInit());
    final app = Get.find<AppController>();

    await tester.pumpWidget(_host(const CpuView()));
    await tester.tap(find.text('Start stress test'));
    await tester.pump();
    helper.sessions.single.emit(StressSampled(const StressSample(t: 1, tempC: 60, clockMhz: 4000, loadPct: 100)));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Stop')); // the global bar
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(helper.sessions.single.stopRequested, isTrue);
    expect(find.text('Stopped early'), findsOneWidget);
    expect(app.statusOf(ModuleId.cpu), TestStatus.notTested);
  });

  testWidgets('CPU screen: a safety stop is shown prominently and fails the test', (tester) async {
    _bigWindow(tester);
    final helper = FakeHelper();
    Get.put(CpuController(helper)..onInit());
    final app = Get.find<AppController>();

    await tester.pumpWidget(_host(const CpuView()));
    await tester.tap(find.text('Start stress test'));
    await tester.pump();
    final s = helper.sessions.single;
    s.emit(StressSampled(const StressSample(t: 1, tempC: 96, clockMhz: 3000, loadPct: 100)));
    s.emit(const StressEnded(StressSummary(
        test: 'cpu', reason: StressEndReason.safety, maxTempC: 96, message: 'Reached 96 °C (limit 95 °C).', elapsedSec: 1)));
    await s.finish();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Stopped for safety'), findsOneWidget);
    expect(find.textContaining('Reached 96 °C'), findsOneWidget);
    expect(app.statusOf(ModuleId.cpu), TestStatus.fail);
  });

  testWidgets('CPU screen: no temperature sensor explains the PawnIO driver', (tester) async {
    _bigWindow(tester);
    final helper = FakeHelper(pawnIo: false);
    Get.put(CpuController(helper)..onInit());

    await tester.pumpWidget(_host(const CpuView()));
    await tester.pump(const Duration(milliseconds: 100)); // loadInfo
    await tester.tap(find.text('Start stress test'));
    await tester.pump();
    final s = helper.sessions.single;
    s.emit(const StressFailed('no-temperature', 'No temperature sensor could be read.'));
    await s.finish(code: 3);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('No temperature sensor available'), findsOneWidget);
    expect(find.textContaining('PawnIO'), findsOneWidget);
    expect(Get.find<AppController>().statusOf(ModuleId.cpu), TestStatus.notTested);
  });

  testWidgets('CPU screen: missing helper is explained', (tester) async {
    _bigWindow(tester);
    Get.put(CpuController(FakeHelper(missing: true))..onInit());

    await tester.pumpWidget(_host(const CpuView()));
    await tester.tap(find.text('Start stress test'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('SolHelper.exe is missing'), findsOneWidget);
  });

  group('GPU screen', () {
    const igpu = GpuDevice(index: 0, name: 'Intel(R) UHD Graphics', integrated: true, hasTempSensor: true);
    const dgpu = GpuDevice(index: 1, name: 'NVIDIA GeForce RTX 3060', integrated: false, dedicatedMb: 6144, hasTempSensor: true, hasOwnTempSensor: true);

    testWidgets('lists integrated and dedicated GPUs, each with its own Test button', (tester) async {
      _bigWindow(tester);
      final helper = FakeHelper(gpus: [igpu, dgpu]);
      Get.put(GpuController(helper)..onInit());

      await tester.pumpWidget(_host(const GpuView()));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Intel(R) UHD Graphics'), findsOneWidget);
      expect(find.text('NVIDIA GeForce RTX 3060'), findsOneWidget);
      expect(find.textContaining('Integrated GPU'), findsOneWidget);
      expect(find.textContaining('Dedicated GPU'), findsOneWidget);
      expect(find.textContaining('temperature from CPU package'), findsOneWidget);
      expect(find.text('Test'), findsNWidgets(2));
      expect(find.text('Test all GPUs'), findsOneWidget);

      await tester.tap(find.text('Test').last);
      await tester.pump();
      expect(helper.startedArgs.single, ['gpu-stress', '--gpu', '1', '--duration', '60', '--limit', '95']);

      // while running: other Test buttons disabled, Stop available
      expect(find.text('Stop'), findsWidgets);
      final s = helper.sessions.single;
      s.emit(const StressEnded(StressSummary(test: 'gpu', reason: StressEndReason.completed, maxTempC: 80, elapsedSec: 60)));
      await s.finish();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('Pass · max 80 °C'), findsOneWidget);
      // dedicated passed but the integrated GPU is still untested, so no module verdict yet
      expect(Get.find<AppController>().statusOf(ModuleId.gpu), TestStatus.notTested);
    });

    testWidgets('no GPU found is explained', (tester) async {
      _bigWindow(tester);
      Get.put(GpuController(FakeHelper())..onInit());
      await tester.pumpWidget(_host(const GpuView()));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('No GPU found'), findsOneWidget);
    });

    testWidgets('a missing helper is explained', (tester) async {
      _bigWindow(tester);
      Get.put(GpuController(FakeHelper(missing: true))..onInit());
      await tester.pumpWidget(_host(const GpuView()));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('SolHelper.exe is missing'), findsOneWidget);
    });
  });
}
