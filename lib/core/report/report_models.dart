import '../../app/app_modules.dart';
import '../models/test_status.dart';

/// Where a report is verified online.
const verifyBaseUrl = 'https://lapchecker.sollabstech.com/verify';

String verifyUrlFor(String reportId) => '$verifyBaseUrl/$reportId';

/// Overall condition of the laptop, A (best) to D.
enum ReportGrade {
  a('A', 'Excellent condition'),
  b('B', 'Good condition'),
  c('C', 'Fair condition: some issues found'),
  d('D', 'Poor condition: significant problems');

  const ReportGrade(this.letter, this.verdict);
  final String letter;
  final String verdict;

  static ReportGrade fromLetter(String l) => values.firstWhere((g) => g.letter == l, orElse: () => d);

  /// The worse (later) of two grades.
  ReportGrade worseOf(ReportGrade other) => index >= other.index ? this : other;
}

/// How much each test contributes to the 0-100 health score (sums to 100).
const reportWeights = <ModuleId, int>{
  ModuleId.battery: 15,
  ModuleId.storage: 20,
  ModuleId.cpu: 15,
  ModuleId.gpu: 10,
  ModuleId.keyboard: 10,
  ModuleId.touchpad: 5,
  ModuleId.webcam: 5,
  ModuleId.speaker: 5,
  ModuleId.microphone: 5,
  ModuleId.display: 10,
};

/// Credit a finished test earns: full for a pass, 60% for a warning, none for a fail.
double statusCredit(TestStatus s) => switch (s) {
      TestStatus.pass => 1.0,
      TestStatus.warning => 0.6,
      _ => 0.0,
    };

class ScoreResult {
  const ScoreResult({required this.score, required this.grade, required this.testedCount, required this.totalCount});

  /// 0..100, computed over the tests that were actually run.
  final int score;
  final ReportGrade grade;
  final int testedCount;
  final int totalCount;

  bool get partial => testedCount < totalCount;
}

/// Health score and grade from the tests' statuses.
///
/// * score = weighted credit of the finished tests, as a percentage of their weight;
/// * grade from the score: A >= 90, B >= 75, C >= 60, otherwise D;
/// * any failed test caps the grade at C (a broken component is never "A" or "B");
/// * Grade A needs every test completed: any untested test caps at B, and fewer
///   than half tested caps at C.
ScoreResult computeScore(Map<ModuleId, TestStatus> statuses) {
  var earned = 0.0;
  var possible = 0;
  var tested = 0;
  var failed = 0;

  for (final e in reportWeights.entries) {
    final s = statuses[e.key] ?? TestStatus.notTested;
    if (!s.isFinished) continue;
    tested++;
    possible += e.value;
    earned += e.value * statusCredit(s);
    if (s == TestStatus.fail) failed++;
  }

  final total = reportWeights.length;
  final score = possible == 0 ? 0 : (earned / possible * 100).round();

  var grade = score >= 90
      ? ReportGrade.a
      : score >= 75
          ? ReportGrade.b
          : score >= 60
              ? ReportGrade.c
              : ReportGrade.d;
  if (failed > 0) grade = grade.worseOf(ReportGrade.c);
  if (tested < total) grade = grade.worseOf(ReportGrade.b);
  if (tested * 2 < total) grade = grade.worseOf(ReportGrade.c);

  return ScoreResult(score: score, grade: grade, testedCount: tested, totalCount: total);
}

/// One "label: value" line under a test.
class ReportDetail {
  const ReportDetail(this.label, this.value);

  final String label;
  final String value;

  Map<String, dynamic> toJson() => {'label': label, 'value': value};

  factory ReportDetail.fromJson(Map<String, dynamic> j) => ReportDetail('${j['label'] ?? ''}', '${j['value'] ?? ''}');
}

/// A test's result as printed in the report.
class ReportTest {
  const ReportTest({
    required this.id,
    required this.title,
    required this.status,
    required this.headline,
    this.details = const [],
  });

  final String id;
  final String title;
  final TestStatus status;

  /// One-line summary, e.g. "Health 87% · Good".
  final String headline;
  final List<ReportDetail> details;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'status': status.name,
        'headline': headline,
        'details': details.map((d) => d.toJson()).toList(),
      };

  factory ReportTest.fromJson(Map<String, dynamic> j) => ReportTest(
        id: '${j['id'] ?? ''}',
        title: '${j['title'] ?? ''}',
        status: TestStatus.values.firstWhere((s) => s.name == j['status'], orElse: () => TestStatus.notTested),
        headline: '${j['headline'] ?? ''}',
        details: [
          for (final d in (j['details'] as List? ?? const []).whereType<Map>())
            ReportDetail.fromJson(d.cast<String, dynamic>()),
        ],
      );
}

/// Everything in a saved report. Serialises to the JSON copy kept beside the PDF.
class ReportData {
  const ReportData({
    required this.id,
    required this.createdAt,
    required this.technician,
    this.customer,
    required this.appVersion,
    required this.system,
    required this.tests,
    required this.score,
    required this.grade,
    required this.testedCount,
    required this.totalCount,
    this.maxCpuTempC,
    this.maxGpuTempC,
  });

  final String id;
  final DateTime createdAt;
  final String technician;
  final String? customer;
  final String appVersion;

  /// Laptop identity and hardware (see `SystemInfo.toJson`); empty if it could not be read.
  final Map<String, dynamic> system;
  final List<ReportTest> tests;
  final int score;
  final ReportGrade grade;
  final int testedCount;
  final int totalCount;
  final double? maxCpuTempC;
  final double? maxGpuTempC;

  bool get partial => testedCount < totalCount;

  String get verifyUrl => verifyUrlFor(id);

  String get brand => '${system['brand'] ?? ''}'.trim();
  String get model => '${system['model'] ?? ''}'.trim();
  String get serial => '${system['serialNumber'] ?? ''}'.trim();

  /// "Lenovo ThinkPad T14", or "Unknown laptop".
  String get laptopName {
    final n = [brand, model].where((e) => e.isNotEmpty && e != 'Unknown').join(' ');
    return n.isEmpty ? 'Unknown laptop' : n;
  }

  int count(TestStatus s) => tests.where((t) => t.status == s).length;

  Map<String, dynamic> toJson() => {
        'schema': 1,
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'technician': technician,
        'customer': customer,
        'appVersion': appVersion,
        'verifyUrl': verifyUrl,
        'score': score,
        'grade': grade.letter,
        'testedCount': testedCount,
        'totalCount': totalCount,
        'maxCpuTempC': maxCpuTempC,
        'maxGpuTempC': maxGpuTempC,
        'system': system,
        'tests': tests.map((t) => t.toJson()).toList(),
      };

  factory ReportData.fromJson(Map<String, dynamic> j) => ReportData(
        id: '${j['id']}',
        createdAt: DateTime.tryParse('${j['createdAt']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
        technician: '${j['technician'] ?? ''}',
        customer: (j['customer'] as String?)?.trim().isEmpty ?? true ? null : j['customer'] as String,
        appVersion: '${j['appVersion'] ?? ''}',
        system: (j['system'] as Map?)?.cast<String, dynamic>() ?? const {},
        tests: [
          for (final t in (j['tests'] as List? ?? const []).whereType<Map>())
            ReportTest.fromJson(t.cast<String, dynamic>()),
        ],
        score: (j['score'] as num?)?.toInt() ?? 0,
        grade: ReportGrade.fromLetter('${j['grade']}'),
        testedCount: (j['testedCount'] as num?)?.toInt() ?? 0,
        totalCount: (j['totalCount'] as num?)?.toInt() ?? reportWeights.length,
        maxCpuTempC: (j['maxCpuTempC'] as num?)?.toDouble(),
        maxGpuTempC: (j['maxGpuTempC'] as num?)?.toDouble(),
      );
}

/// Row in the history list.
class ReportSummary {
  const ReportSummary({
    required this.id,
    required this.createdAt,
    required this.laptop,
    required this.serial,
    required this.technician,
    this.customer,
    required this.score,
    required this.grade,
    required this.partial,
    required this.hasPdf,
  });

  final String id;
  final DateTime createdAt;
  final String laptop;
  final String serial;
  final String technician;
  final String? customer;
  final int score;
  final ReportGrade grade;
  final bool partial;
  final bool hasPdf;

  factory ReportSummary.fromData(ReportData d, {required bool hasPdf}) => ReportSummary(
        id: d.id,
        createdAt: d.createdAt,
        laptop: d.laptopName,
        serial: d.serial,
        technician: d.technician,
        customer: d.customer,
        score: d.score,
        grade: d.grade,
        partial: d.partial,
        hasPdf: hasPdf,
      );

  /// Matches the history search box (id, laptop, serial, customer, technician).
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [id, laptop, serial, customer ?? '', technician].any((f) => f.toLowerCase().contains(q));
  }
}
