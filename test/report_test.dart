import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sollapchecker/app/app_modules.dart';
import 'package:sollapchecker/core/models/battery_info.dart';
import 'package:sollapchecker/core/models/test_status.dart';
import 'package:sollapchecker/core/report/report_builder.dart';
import 'package:sollapchecker/core/report/report_models.dart';
import 'package:sollapchecker/core/report/report_pdf.dart';
import 'package:sollapchecker/core/report/report_repository.dart';

import 'helpers/sample_report.dart';

ReportData build({
  ReportInputs? inputs,
  String id = 'SLC-20261025-0001',
  String technician = 'Asha Rao',
  String? customer,
}) =>
    ReportBuilder.build(
      inputs ?? sampleInputs(),
      id: id,
      createdAt: DateTime(2026, 10, 25, 14, 30),
      technician: technician,
      customer: customer,
      appVersion: '1.0.0',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('score and grade', () {
    Map<ModuleId, TestStatus> all(TestStatus s) => {for (final m in testModules) m.id: s};

    test('weights add up to 100', () {
      expect(reportWeights.values.fold<int>(0, (a, b) => a + b), 100);
      expect(reportWeights.keys.toSet(), testModules.map((m) => m.id).toSet());
    });

    test('everything passing is 100 and Grade A', () {
      final r = computeScore(all(TestStatus.pass));
      expect(r.score, 100);
      expect(r.grade, ReportGrade.a);
      expect(r.partial, isFalse);
    });

    test('a warning earns 60% of its weight', () {
      // storage (20) warns, everything else passes: (80 + 12) / 100
      final s = all(TestStatus.pass)..[ModuleId.storage] = TestStatus.warning;
      final r = computeScore(s);
      expect(r.score, 92);
      expect(r.grade, ReportGrade.a);
    });

    test('any failed test caps the grade at C, however high the score', () {
      // keyboard (10) fails: 90 points, which would be A
      final s = all(TestStatus.pass)..[ModuleId.keyboard] = TestStatus.fail;
      final r = computeScore(s);
      expect(r.score, 90);
      expect(r.grade, ReportGrade.c);
    });

    test('grade thresholds', () {
      ReportGrade g(Map<ModuleId, TestStatus> s) => computeScore(s).grade;
      // all warnings: 60 -> C
      expect(g(all(TestStatus.warning)), ReportGrade.c);
      // storage + battery + cpu fail (50 lost) -> 50 -> D
      final d = all(TestStatus.pass)
        ..[ModuleId.storage] = TestStatus.fail
        ..[ModuleId.battery] = TestStatus.fail
        ..[ModuleId.cpu] = TestStatus.fail;
      expect(computeScore(d).score, 50);
      expect(g(d), ReportGrade.d);
    });

    test('Grade A needs every test: untested caps at B, under half tested caps at C', () {
      final nine = all(TestStatus.pass)..[ModuleId.display] = TestStatus.notTested;
      final r9 = computeScore(nine);
      expect(r9.score, 100); // scored over the tests that ran
      expect(r9.grade, ReportGrade.b);
      expect(r9.partial, isTrue);

      final few = {ModuleId.battery: TestStatus.pass, ModuleId.storage: TestStatus.pass};
      expect(computeScore(few).grade, ReportGrade.c);
    });

    test('nothing tested scores 0', () {
      final r = computeScore(all(TestStatus.notTested));
      expect(r.score, 0);
      expect(r.testedCount, 0);
      expect(r.grade, ReportGrade.d);
    });
  });

  group('ReportBuilder', () {
    test('builds ten tests with the sidebar statuses, in order', () {
      final r = build();
      expect(r.tests.map((t) => t.id), testModules.map((m) => m.id.name));
      expect(r.tests.every((t) => t.status == TestStatus.pass), isTrue);
      expect(r.score, 100);
      expect(r.grade, ReportGrade.a);
      expect(r.id, 'SLC-20261025-0001');
      expect(r.verifyUrl, 'https://lapchecker.sollabstech.com/verify/SLC-20261025-0001');
    });

    test('laptop identity and peak temperatures', () {
      final r = build();
      expect(r.laptopName, 'Lenovo ThinkPad T14 Gen 3');
      expect(r.serial, 'PF3ABCDE');
      expect(r.maxCpuTempC, 84);
      expect(r.maxGpuTempC, 71);
    });

    test('result lines carry the measured values', () {
      final r = build();
      String head(String id) => r.tests.firstWhere((t) => t.id == id).headline;
      String? detail(String id, String label) => r.tests.firstWhere((t) => t.id == id).details.where((d) => d.label == label).firstOrNull?.value;

      expect(head('battery'), 'Health 90% · Good');
      expect(detail('battery', 'Design capacity'), '51,000 mWh');
      expect(detail('battery', 'Cycle count'), '212');
      expect(head('storage'), '1 drive · Good');
      expect(head('cpu'), 'Max 84 °C · no throttling');
      expect(detail('cpu', 'Throttling'), 'Power limit only (not overheating)');
      expect(detail('cpu', 'Temperature'), 'max 84 °C · average 79 °C');
      expect(head('gpu'), '2 GPUs · max 72 °C');
      expect(head('keyboard'), '84 / 84 keys tested');
      expect(head('touchpad'), '4 / 4 actions OK');
      expect(head('webcam'), 'Works · 1280 × 720');
      expect(head('display'), '5 colours checked · No problems seen');
    });

    test('a failing laptop is reported honestly', () {
      final inputs = ReportInputs(
        system: sampleSystemInfo().toJson(),
        statuses: {
          for (final m in testModules) m.id: TestStatus.pass,
          ModuleId.battery: TestStatus.fail,
          ModuleId.keyboard: TestStatus.fail,
        },
        battery: const BatteryInfo(present: true, designMWh: 50000, fullChargeMWh: 20000),
        keyboard: const {
          'total': 84,
          'tested': 80,
          'failed': ['Q', 'Space'],
          'untested': ['F6'],
          'manuallyConfirmed': <String>[],
          'ignoredExternalPresses': 0,
        },
      );
      final r = build(inputs: inputs);

      expect(r.tests.firstWhere((t) => t.id == 'battery').headline, 'Health 40% · Replace');
      final kb = r.tests.firstWhere((t) => t.id == 'keyboard');
      expect(kb.headline, '80 / 84 keys tested · 2 not working');
      expect(kb.details.first.value, 'Q, Space');
      expect(r.grade, ReportGrade.c);
    });

    test('untested modules read "Not tested" and make the report partial', () {
      final r = build(inputs: ReportInputs(
        system: sampleSystemInfo().toJson(),
        statuses: {ModuleId.battery: TestStatus.pass},
        battery: const BatteryInfo(present: true, designMWh: 50000, fullChargeMWh: 48000),
      ));
      expect(r.partial, isTrue);
      expect(r.testedCount, 1);
      expect(r.tests.firstWhere((t) => t.id == 'cpu').headline, 'Not tested');
      expect(r.tests.firstWhere((t) => t.id == 'cpu').status, TestStatus.notTested);
      expect(r.maxCpuTempC, isNull);
    });

    test('customer is optional and trimmed', () {
      expect(build(customer: '  ').customer, isNull);
      expect(build(customer: ' Mr Patel ').customer, 'Mr Patel');
      expect(build(technician: '  Asha  ').technician, 'Asha');
    });

    test('JSON round trip loses nothing', () {
      final r = build(customer: 'Mr Patel');
      final again = ReportData.fromJson(jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>);
      expect(jsonEncode(again.toJson()), jsonEncode(r.toJson()));
      expect(again.grade, r.grade);
      expect(again.tests.length, 8);
      expect(again.createdAt, r.createdAt);
    });
  });

  group('ReportRepository', () {
    late Directory tmp;
    late ReportRepository repo;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('sollap_reports_');
      repo = ReportRepository(Directory('${tmp.path}${Platform.pathSeparator}Reports'));
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    final pdf = Uint8List.fromList(List.generate(64, (i) => i));

    test('IDs count up within a day and restart on a new day', () async {
      final day = DateTime(2026, 10, 25, 9);
      expect(await repo.nextId(day), 'SLC-20261025-0001');

      await repo.save(build(id: 'SLC-20261025-0001'), pdf);
      expect(await repo.nextId(day), 'SLC-20261025-0002');

      await repo.save(build(id: 'SLC-20261025-0007'), pdf);
      expect(await repo.nextId(day), 'SLC-20261025-0008'); // continues after the highest

      expect(await repo.nextId(DateTime(2026, 10, 26)), 'SLC-20261026-0001');
    });

    test('saves a PDF and a JSON copy and reads them back', () async {
      final r = build(customer: 'Mr Patel');
      await repo.save(r, pdf);

      expect(File(repo.pdfPath(r.id)).readAsBytesSync(), pdf);
      expect(jsonDecode(File(repo.jsonPath(r.id)).readAsStringSync())['id'], r.id);
      expect((await repo.load(r.id))!.customer, 'Mr Patel');
      expect(await repo.hasPdf(r.id), isTrue);
      // no temporary files left behind
      expect(repo.root.listSync().whereType<File>().where((f) => f.path.endsWith('.tmp')), isEmpty);
    });

    test('lists newest first with summaries', () async {
      await repo.save(
        ReportBuilder.build(sampleInputs(), id: 'SLC-20261024-0001', createdAt: DateTime(2026, 10, 24, 10), technician: 'A', appVersion: '1'),
        pdf,
      );
      await repo.save(build(id: 'SLC-20261025-0001', customer: 'Mr Patel'), pdf);

      final list = await repo.list();
      expect(list.map((s) => s.id), ['SLC-20261025-0001', 'SLC-20261024-0001']);
      expect(list.first.laptop, 'Lenovo ThinkPad T14 Gen 3');
      expect(list.first.grade, ReportGrade.a);
      expect(list.first.hasPdf, isTrue);
    });

    test('a report whose PDF was deleted is still listed, without a PDF', () async {
      final r = build();
      await repo.save(r, pdf);
      File(repo.pdfPath(r.id)).deleteSync();
      final list = await repo.list();
      expect(list.single.hasPdf, isFalse);
    });

    test('damaged or foreign files are skipped, not fatal', () async {
      await repo.save(build(), pdf);
      File('${repo.root.path}${Platform.pathSeparator}SLC-20261025-0002.json').writeAsStringSync('{not json');
      File('${repo.root.path}${Platform.pathSeparator}notes.json').writeAsStringSync('{}');
      expect((await repo.list()).map((s) => s.id), ['SLC-20261025-0001']);
      expect(await repo.load('SLC-20261025-0002'), isNull);
    });

    test('delete removes both files', () async {
      final r = build();
      await repo.save(r, pdf);
      await repo.delete(r.id);
      expect(File(repo.pdfPath(r.id)).existsSync(), isFalse);
      expect(File(repo.jsonPath(r.id)).existsSync(), isFalse);
      expect(await repo.list(), isEmpty);
    });

    test('the technician name is remembered', () async {
      expect(await repo.lastTechnician(), '');
      await repo.saveTechnician('Asha Rao');
      expect(await repo.lastTechnician(), 'Asha Rao');
    });

    test('search matches id, laptop, serial, customer and technician', () async {
      final s = ReportSummary.fromData(build(customer: 'Mr Patel'), hasPdf: true);
      for (final q in ['patel', 'PF3ABCDE', 'thinkpad', '0001', 'asha', '']) {
        expect(s.matches(q), isTrue, reason: q);
      }
      expect(s.matches('dell'), isFalse);
    });
  });

  group('PDF', () {
    Future<Uint8List> pdfFor(ReportData r) async => buildReportPdf(r, await ReportPdfAssets.load());

    test('produces a PDF for a full report', () async {
      final bytes = await pdfFor(build(customer: 'Mr Patel'));
      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
      expect(bytes.length, greaterThan(8000));

      final dir = Platform.environment['SOL_PDF_OUT'];
      if (dir != null) File('$dir/sample_full.pdf').writeAsBytesSync(bytes);
    });

    test('produces a PDF for a failing, partial report with long values', () async {
      final r = build(
        inputs: ReportInputs(
          system: const {},
          statuses: {ModuleId.battery: TestStatus.fail, ModuleId.keyboard: TestStatus.warning},
          battery: const BatteryInfo(present: false),
          keyboard: {
            'total': 84,
            'tested': 20,
            'failed': <String>[],
            'untested': [for (var i = 0; i < 60; i++) 'K$i'],
            'manuallyConfirmed': <String>[],
            'ignoredExternalPresses': 0,
          },
        ),
        technician: '',
      );
      final bytes = await pdfFor(r);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');

      final dir = Platform.environment['SOL_PDF_OUT'];
      if (dir != null) File('$dir/sample_partial.pdf').writeAsBytesSync(bytes);
    });

    test('the QR payload is the verification URL', () {
      expect(build().verifyUrl, startsWith('https://lapchecker.sollabstech.com/verify/SLC-'));
    });
  });
}
