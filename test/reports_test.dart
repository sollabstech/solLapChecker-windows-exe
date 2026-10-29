import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sollapchecker/app/app_modules.dart';
import 'package:sollapchecker/app/theme.dart';
import 'package:sollapchecker/controllers/app_controller.dart';
import 'package:sollapchecker/core/models/battery_info.dart';
import 'package:sollapchecker/core/models/drive_health.dart';
import 'package:sollapchecker/core/models/test_status.dart';
import 'package:sollapchecker/core/report/report_models.dart';
import 'package:sollapchecker/core/report/report_repository.dart';
import 'package:sollapchecker/core/services/battery_service.dart';
import 'package:sollapchecker/core/services/smartctl_service.dart';
import 'package:sollapchecker/modules/battery/battery_controller.dart';
import 'package:sollapchecker/modules/reports/reports_controller.dart';
import 'package:sollapchecker/modules/reports/reports_view.dart';
import 'package:sollapchecker/modules/storage/storage_controller.dart';

import 'helpers/fake_media.dart';
import 'helpers/sample_report.dart';

class _Battery implements BatteryService {
  @override
  Future<BatteryInfo> read() async => const BatteryInfo(present: true, designMWh: 51000, fullChargeMWh: 46000);
}

/// Taps [finder] in the real-async zone (the controller then does real file IO there),
/// waits until [done] holds (or a short time passes), and pumps the result onto the screen.
Future<void> tapAndWait(WidgetTester tester, Finder finder, {bool Function()? done}) async {
  await tester.runAsync(() async {
    await tester.tap(finder);
    final end = DateTime.now().add(const Duration(seconds: 8));
    if (done == null) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return;
    }
    while (!done() && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// For flows started from a normal tap: alternates short real-time waits (so file IO
/// can complete) with pumps (so the continuations queued in the test zone run).
Future<void> settle(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 250 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
  }
  await tester.pump();
}

/// Lets real-time work that was started earlier (e.g. the view's init) finish.
Future<void> waitFor(WidgetTester tester, bool Function() done) async {
  await tester.runAsync(() async {
    final end = DateTime.now().add(const Duration(seconds: 8));
    while (!done() && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  });
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late ReportRepository repo;
  late FakeFileOpener opener;
  late DateTime now;
  late ReportsController reports;
  late AppController app;

  setUp(() {
    Get.reset();
    app = Get.put(AppController());
    tmp = Directory.systemTemp.createTempSync('sollap_reports_ui_');
    repo = ReportRepository(Directory('${tmp.path}${Platform.pathSeparator}Reports'));
    opener = FakeFileOpener();
    now = DateTime(2026, 10, 25, 14, 30);

    // A finished battery test and a finished storage test, plus the drive data.
    final battery = Get.put(BatteryController(_Battery()));
    battery.info.value = const BatteryInfo(present: true, designMWh: 51000, fullChargeMWh: 46000, cycleCount: 212);
    app.setStatus(ModuleId.battery, TestStatus.pass);
    final storage = Get.put(StorageController(_SmartStub()));
    storage.drives.assignAll([sampleDrive]);
    app.setStatus(ModuleId.storage, TestStatus.pass);

    reports = Get.put(ReportsController(repo, opener: opener, clock: () => now));
  });

  tearDown(() {
    Get.reset();
    tmp.deleteSync(recursive: true);
  });

  group('ReportsController', () {
    test('needs a technician name and at least one finished test', () async {
      expect(reports.canGenerate, isFalse);
      expect(await reports.generate(), isNull);
      expect(reports.error.value, contains('technician'));

      reports.technician.value = 'Asha Rao';
      expect(reports.canGenerate, isTrue);

      for (final m in testModules) {
        app.setStatus(m.id, TestStatus.notTested);
      }
      expect(reports.canGenerate, isFalse);
      expect(await reports.generate(), isNull);
      expect(reports.error.value, contains('at least one test'));
    });

    test('the end of the guided run creates and opens the report by itself', () async {
      final saved = (await reports.autoGenerate())!;

      final json = jsonDecode(File(repo.jsonPath(saved.id)).readAsStringSync()) as Map<String, dynamic>;
      expect(json['technician'], ReportsController.automaticTechnician);
      expect(opener.opened.single, repo.pdfPath(saved.id));
      // The placeholder is not remembered as the technician's name.
      expect(await repo.lastTechnician(), isEmpty);
    });

    test('the automatic report uses the remembered technician name', () async {
      await repo.saveTechnician('Asha Rao');
      final saved = (await reports.autoGenerate())!;
      final json = jsonDecode(File(repo.jsonPath(saved.id)).readAsStringSync()) as Map<String, dynamic>;
      expect(json['technician'], 'Asha Rao');
    });

    test('the guided run hands over to the report when it ends', () async {
      app.startFullTest(); // clears the results...
      app.setStatus(ModuleId.battery, TestStatus.pass); // ...so finish one again
      app.wizardIndex.value = app.wizardSteps.length - 1;
      app.nextStep();
      // Generous: PDF building is slow while other test files run in parallel.
      final end = DateTime.now().add(const Duration(seconds: 30));
      while (reports.lastSaved.value == null && DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(reports.lastSaved.value, isNotNull);
      expect(app.selected.value, ModuleId.reports);
    });

    test('generates a PDF and a JSON copy with the tests that were run', () async {
      reports.technician.value = 'Asha Rao';
      reports.customer.value = ' Mr Patel ';

      final saved = (await reports.generate())!;

      expect(saved.id, 'SLC-20261025-0001');
      expect(File(repo.pdfPath(saved.id)).readAsBytesSync().sublist(0, 5), '%PDF-'.codeUnits);

      final json = jsonDecode(File(repo.jsonPath(saved.id)).readAsStringSync()) as Map<String, dynamic>;
      expect(json['technician'], 'Asha Rao');
      expect(json['customer'], 'Mr Patel');
      expect(json['verifyUrl'], 'https://lapchecker.sollabstech.com/verify/SLC-20261025-0001');
      expect(json['testedCount'], 2);
      final tests = (json['tests'] as List).cast<Map<String, dynamic>>();
      expect(tests.firstWhere((t) => t['id'] == 'battery')['headline'], 'Health 90% · Good');
      expect(tests.firstWhere((t) => t['id'] == 'cpu')['headline'], 'Not tested');

      expect(reports.history.map((h) => h.id), [saved.id]);
      expect(reports.lastSaved.value?.id, saved.id);
      expect(await repo.lastTechnician(), 'Asha Rao');
      expect(saved.partial, isTrue);
    });

    test('consecutive reports get consecutive IDs', () async {
      reports.technician.value = 'A';
      final first = (await reports.generate())!;
      now = now.add(const Duration(minutes: 5));
      final second = (await reports.generate())!;
      expect(first.id, 'SLC-20261025-0001');
      expect(second.id, 'SLC-20261025-0002');
      expect(reports.history.map((h) => h.id), ['SLC-20261025-0002', 'SLC-20261025-0001']);
    });

    test('init restores the remembered technician and the saved reports', () async {
      reports.technician.value = 'Asha Rao';
      await reports.generate();

      Get.delete<ReportsController>(force: true);
      final fresh = Get.put(ReportsController(repo, opener: opener, clock: () => now));
      await fresh.init();
      expect(fresh.technician.value, 'Asha Rao');
      expect(fresh.history, hasLength(1));
    });

    test('open, reveal and a missing PDF being rebuilt', () async {
      reports.technician.value = 'A';
      final saved = (await reports.generate())!;

      await reports.openPdf(saved);
      expect(opener.opened.single, repo.pdfPath(saved.id));

      File(repo.pdfPath(saved.id)).deleteSync();
      await reports.refreshHistory();
      expect(reports.history.single.hasPdf, isFalse);

      await reports.openPdf(reports.history.single);
      expect(File(repo.pdfPath(saved.id)).existsSync(), isTrue); // rebuilt from the JSON copy
      expect(opener.opened, hasLength(2));
      expect(reports.history.single.hasPdf, isTrue);

      await reports.reveal(saved);
      expect(opener.revealed.single, repo.pdfPath(saved.id));
    });

    test('a failing file opener is reported, not thrown', () async {
      reports.technician.value = 'A';
      final saved = (await reports.generate())!;
      opener.failWith = 'no viewer';
      await reports.openPdf(saved);
      expect(reports.error.value, contains('no viewer'));
    });

    test('delete removes the report from disk and the list', () async {
      reports.technician.value = 'A';
      final saved = (await reports.generate())!;
      await reports.delete(saved);
      expect(reports.history, isEmpty);
      expect(File(repo.pdfPath(saved.id)).existsSync(), isFalse);
      expect(reports.lastSaved.value, isNull);
    });

    test('search filters the history', () async {
      reports.technician.value = 'A';
      reports.customer.value = 'Mr Patel';
      await reports.generate();
      now = now.add(const Duration(minutes: 1));
      reports.customer.value = 'Ms Singh';
      await reports.generate();

      reports.query.value = 'patel';
      expect(reports.filtered, hasLength(1));
      reports.query.value = 'zzz';
      expect(reports.filtered, isEmpty);
      reports.query.value = '';
      expect(reports.filtered, hasLength(2));
    });

    test('an older, slower history refresh cannot overwrite a newer one', () async {
      reports.technician.value = 'A';
      final slowRepo = _SlowListRepo(repo.root);
      Get.delete<ReportsController>(force: true);
      final c = Get.put(ReportsController(slowRepo, opener: opener, clock: () => now));

      // 1st refresh starts while the folder is empty and is slow to finish ...
      slowRepo.delayNextList = const Duration(milliseconds: 150);
      final early = c.refreshHistory();
      // ... meanwhile a report is saved, whose own refresh finishes first.
      c.technician.value = 'A';
      await c.generate();
      expect(c.history, hasLength(1));

      await early; // the stale (empty) result arrives late
      expect(c.history, hasLength(1));
    });

    test('the live preview follows the statuses', () {
      expect(reports.preview.testedCount, 2);
      expect(reports.preview.grade, ReportGrade.c); // fewer than half tested
      app.setStatus(ModuleId.cpu, TestStatus.fail);
      expect(reports.preview.testedCount, 3);
    });
  });

  group('Reports screen', () {
    Widget host() => MaterialApp(theme: buildAppTheme(), home: const Scaffold(body: ReportsView()));

    void window(WidgetTester tester) {
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('the Generate button waits for a technician name, then creates and lists a report', (tester) async {
      window(tester);
      await tester.pumpWidget(host());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();

      expect(find.text('No reports yet'), findsOneWidget);
      expect(find.text('Enter the technician name to continue.'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Generate report (PDF)')).onPressed, isNull);
      expect(find.text('2 of 8 tests completed'), findsOneWidget);
      expect(find.textContaining('Not tested: CPU Stress Test'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Technician name *'), 'Asha Rao');
      await tester.enterText(find.widgetWithText(TextField, 'Customer name (optional)'), 'Mr Patel');
      await tester.pump();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Generate report (PDF)')).onPressed, isNotNull);

      await tapAndWait(tester, find.text('Generate report (PDF)'),
          done: () => reports.history.isNotEmpty && !reports.isGenerating.value);

      expect(find.text('Report SLC-20261025-0001 saved'), findsOneWidget);
      expect(find.text('Open PDF'), findsOneWidget);
      expect(find.textContaining('SLC-20261025-0001  ·'), findsNothing); // history row shows id and serial together
      expect(find.text('1 report'), findsOneWidget);
      expect(find.text('Mr Patel · by Asha Rao'), findsOneWidget);

      await tester.tap(find.text('Open PDF'));
      await tester.pump();
      await settle(tester, () => opener.opened.isNotEmpty);
      expect(opener.opened.single, endsWith('SLC-20261025-0001.pdf'));
    });

    testWidgets('history: view results, search and delete with confirmation', (tester) async {
      window(tester);
      reports.technician.value = 'Asha Rao';
      await tester.runAsync(() => reports.generate());

      await tester.pumpWidget(host());
      await waitFor(tester, () => reports.history.isNotEmpty);
      expect(find.text('1 report'), findsOneWidget);

      // view results
      await tapAndWait(tester, find.byTooltip('View results'));
      await tester.pumpAndSettle();
      expect(find.text('Battery Health'), findsWidgets);
      expect(find.textContaining('Health 90% · Good'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // search with no match
      await tester.enterText(find.widgetWithText(TextField, 'Search reports'), 'nothing');
      await tester.pump();
      expect(find.text('No report matches your search.'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Search reports'), '');
      await tester.pump();

      // delete
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this report?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pump();
      await settle(tester, () => reports.history.isEmpty);
      await tester.pumpAndSettle();
      expect(find.text('No reports yet'), findsOneWidget);
    });
  });
}

/// A repository whose next `list()` can be made slow, to provoke overlapping refreshes.
class _SlowListRepo extends ReportRepository {
  _SlowListRepo(super.root);

  Duration? delayNextList;

  @override
  Future<List<ReportSummary>> list() async {
    final snapshot = await super.list(); // taken now, returned after the delay
    final d = delayNextList;
    delayNextList = null;
    if (d != null) await Future<void>.delayed(d);
    return snapshot;
  }
}

class _SmartStub extends SmartctlService {
  @override
  Future<List<DriveHealth>> readAll() async => const [];
}
