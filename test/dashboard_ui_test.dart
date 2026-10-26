import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sollapchecker/app/app_modules.dart';
import 'package:sollapchecker/app/theme.dart';
import 'package:sollapchecker/controllers/app_controller.dart';
import 'package:sollapchecker/core/models/system_info.dart';
import 'package:sollapchecker/core/models/test_status.dart';
import 'package:sollapchecker/core/services/system_info_service.dart';
import 'package:sollapchecker/modules/dashboard/dashboard_controller.dart';
import 'package:sollapchecker/modules/dashboard/dashboard_view.dart';
import 'package:sollapchecker/widgets/sidebar.dart';
import 'package:sollapchecker/widgets/wizard_banner.dart';

class _FakeService implements SystemInfoService {
  @override
  Future<SystemInfo> load() async => SystemInfo.fromJson({
        'computer': {'manufacturer': 'Dell Inc.', 'model': 'XPS 13 9310', 'totalMemory': 17179869184},
        'bios': {'version': '3.1.0', 'serial': 'ABC1234', 'releaseDate': '2022-01-01'},
        'cpu': {'name': 'Intel Core i7', 'cores': 4, 'threads': 8, 'maxMhz': 4800},
        'gpus': [
          {'name': 'Intel Iris Xe', 'driver': '1.0', 'hRes': 1920, 'vRes': 1200, 'refresh': 60},
          {'name': 'NVIDIA GeForce MX450', 'driver': '2.0'},
        ],
        'ram': [
          {'capacity': 8589934592, 'speed': 3200, 'smbiosType': 26},
          {'capacity': 8589934592, 'speed': 3200, 'smbiosType': 26},
        ],
        'disks': [
          {'model': 'NVMe Samsung 512GB', 'size': 512110190592},
        ],
        'os': {'caption': 'Microsoft Windows 11 Home', 'build': '22631', 'arch': '64-bit'},
      });
}

Widget _harness() => GetMaterialApp(
      theme: buildAppTheme(),
      home: const Scaffold(
        body: Row(
          children: [
            AppSidebar(),
            Expanded(
              child: Column(
                children: [
                  WizardBanner(),
                  Expanded(child: DashboardView()),
                ],
              ),
            ),
          ],
        ),
      ),
    );

void main() {
  setUp(() {
    Get.reset();
    Get.put(AppController());
    Get.put(DashboardController(_FakeService()));
  });

  tearDown(Get.reset);

  testWidgets('dashboard renders system info at the minimum window size without overflow', (tester) async {
    tester.view.physicalSize = const Size(1100, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('XPS 13 9310'), findsOneWidget);
    expect(find.text('ABC1234'), findsOneWidget);
    expect(find.text('NVIDIA GeForce MX450'), findsOneWidget);
    expect(find.text('1920 × 1200 @ 60 Hz'), findsOneWidget);
    expect(find.text('Run Full Test'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Run Full Test starts the wizard; Skip advances; Stop ends it', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final app = Get.find<AppController>();
    await tester.pumpWidget(_harness());
    await tester.pump(const Duration(milliseconds: 900));

    await tester.tap(find.text('Run Full Test'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(app.wizardActive.value, isTrue);
    expect(app.selected.value, ModuleId.battery);
    expect(find.text('Guided test · Step 1 of 10'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(app.selected.value, ModuleId.storage);

    await tester.tap(find.text('Stop'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(app.wizardActive.value, isFalse);
  });

  testWidgets('sidebar statuses start as Not tested and update live', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final app = Get.find<AppController>();
    await tester.pumpWidget(_harness());
    await tester.pump(const Duration(milliseconds: 900));

    // The test list is lazily built and scrolls at this height, so check
    // the visible rows plus the controller's full state.
    expect(find.text('Not tested'), findsWidgets);
    expect(app.countOf(TestStatus.notTested), 10);

    app.setStatus(ModuleId.battery, TestStatus.pass);
    app.setStatus(ModuleId.storage, TestStatus.fail);
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Pass'), findsWidgets);
    expect(find.text('Fail'), findsWidgets);
    expect(app.finishedCount, 2);
    expect(app.progress, closeTo(0.2, 1e-9));
  });
}
