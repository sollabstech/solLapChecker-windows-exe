import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sollapchecker/app/app_modules.dart';
import 'package:sollapchecker/app/theme.dart';
import 'package:sollapchecker/controllers/app_controller.dart';
import 'package:sollapchecker/core/models/battery_info.dart';
import 'package:sollapchecker/core/models/drive_health.dart';
import 'package:sollapchecker/core/models/test_status.dart';
import 'package:sollapchecker/core/services/battery_service.dart';
import 'package:sollapchecker/core/services/smartctl_service.dart';
import 'package:sollapchecker/modules/battery/battery_controller.dart';
import 'package:sollapchecker/modules/battery/battery_view.dart';
import 'package:sollapchecker/modules/storage/storage_controller.dart';
import 'package:sollapchecker/modules/storage/storage_view.dart';

class _FakeBattery implements BatteryService {
  _FakeBattery(this.result);
  final BatteryInfo result;
  int calls = 0;

  @override
  Future<BatteryInfo> read() async {
    calls++;
    return result;
  }
}

class _FakeSmart implements SmartctlService {
  _FakeSmart({this.drives = const [], this.missing = false});
  final List<DriveHealth> drives;
  final bool missing;

  @override
  Future<List<DriveHealth>> readAll() async {
    if (missing) throw SmartctlMissingException(['C:\\app\\tools\\smartctl.exe']);
    return drives;
  }
}

Widget _host(Widget child) => GetMaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: child),
    );

Future<void> _bigWindow(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() {
    Get.reset();
    Get.put(AppController());
  });
  tearDown(Get.reset);

  group('Battery screen', () {
    testWidgets('auto-runs in the wizard, shows health and grade, Continue moves on', (tester) async {
      await _bigWindow(tester);
      final fake = _FakeBattery(const BatteryInfo(
        present: true,
        designMWh: 50000,
        fullChargeMWh: 42500,
        cycleCount: 301,
        chargePercent: 64,
        chargeState: ChargeState.discharging,
        manufacturer: 'SMP',
      ));
      Get.put(BatteryController(fake));
      final app = Get.find<AppController>()..startFullTest();

      await tester.pumpWidget(_host(const BatteryView()));
      await tester.pump(const Duration(seconds: 1));

      expect(fake.calls, 1);
      expect(find.text('85%'), findsOneWidget);
      expect(find.text('Good'), findsWidgets);
      expect(find.text('50,000'), findsOneWidget);
      expect(find.text('301'), findsOneWidget);
      expect(app.statusOf(ModuleId.battery), TestStatus.pass);

      await tester.tap(find.text('Continue to next test'));
      await tester.pump();
      expect(app.selected.value, ModuleId.storage);
    });

    testWidgets('does not auto-run outside the wizard', (tester) async {
      await _bigWindow(tester);
      final fake = _FakeBattery(const BatteryInfo.none());
      Get.put(BatteryController(fake));

      await tester.pumpWidget(_host(const BatteryView()));
      await tester.pump(const Duration(milliseconds: 500));

      expect(fake.calls, 0);
      expect(find.text('Ready to check the battery'), findsOneWidget);
    });

    testWidgets('no battery detected is explained and flagged as a warning', (tester) async {
      await _bigWindow(tester);
      Get.put(BatteryController(_FakeBattery(const BatteryInfo.none())));
      final app = Get.find<AppController>();

      await tester.pumpWidget(_host(const BatteryView()));
      await tester.tap(find.text('Run test'));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('No battery detected'), findsOneWidget);
      expect(app.statusOf(ModuleId.battery), TestStatus.warning);
    });

    testWidgets('worn battery shows Replace and fails the test', (tester) async {
      await _bigWindow(tester);
      Get.put(BatteryController(_FakeBattery(
        const BatteryInfo(present: true, designMWh: 50000, fullChargeMWh: 24000),
      )));
      final app = Get.find<AppController>();

      await tester.pumpWidget(_host(const BatteryView()));
      await tester.tap(find.text('Run test'));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('48%'), findsOneWidget);
      expect(find.text('Replace'), findsWidgets);
      expect(find.text('N/A'), findsWidgets); // cycle count / charge not reported
      expect(app.statusOf(ModuleId.battery), TestStatus.fail);
    });
  });

  group('Storage screen', () {
    const good = DriveHealth(
      device: '/dev/nvme0',
      model: 'WDC PC SN810',
      type: DriveType.nvme,
      capacityBytes: 512110190592,
      healthPercent: 97,
      percentUsed: 3,
      bytesWritten: 12288000000000,
      powerOnHours: 1450,
      powerCycles: 312,
      temperatureC: 38,
      unsafeShutdowns: 12,
      mediaErrors: 0,
      smartPassed: true,
    );
    const worn = DriveHealth(
      device: '/dev/sda',
      model: 'Samsung SSD 860 EVO',
      type: DriveType.sataSsd,
      healthPercent: 25,
      percentUsed: 75,
      reallocatedSectors: 4,
      smartPassed: true,
    );

    testWidgets('lists each drive with its verdict and reasons; worst drive sets the status', (tester) async {
      await _bigWindow(tester);
      Get.put(StorageController(_FakeSmart(drives: [good, worn])));
      final app = Get.find<AppController>();

      await tester.pumpWidget(_host(const StorageView()));
      await tester.tap(find.text('Run test'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('WDC PC SN810'), findsOneWidget);
      expect(find.text('Samsung SSD 860 EVO'), findsOneWidget);
      expect(find.text('Good'), findsOneWidget);
      expect(find.text('Caution'), findsOneWidget);
      expect(find.textContaining('75% of the rated lifetime'), findsOneWidget);
      expect(find.textContaining('4 reallocated sectors'), findsOneWidget);
      expect(find.text('12.3 TB'), findsOneWidget);
      expect(app.statusOf(ModuleId.storage), TestStatus.warning);
    });

    testWidgets('missing smartctl.exe is explained and the test stays Not tested', (tester) async {
      await _bigWindow(tester);
      Get.put(StorageController(_FakeSmart(missing: true)));
      final app = Get.find<AppController>();

      await tester.pumpWidget(_host(const StorageView()));
      await tester.tap(find.text('Run test'));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('smartctl.exe is missing'), findsOneWidget);
      expect(app.statusOf(ModuleId.storage), TestStatus.notTested);
    });

    testWidgets('no readable drives is a warning', (tester) async {
      await _bigWindow(tester);
      Get.put(StorageController(_FakeSmart()));
      final app = Get.find<AppController>();

      await tester.pumpWidget(_host(const StorageView()));
      await tester.tap(find.text('Run test'));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('No drives could be read'), findsOneWidget);
      expect(app.statusOf(ModuleId.storage), TestStatus.warning);
    });
  });
}
