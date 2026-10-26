import '../../app/app_modules.dart';
import '../models/battery_info.dart';
import '../models/drive_health.dart';
import '../models/stress.dart';
import '../models/test_status.dart';
import '../utils/format.dart';
import 'report_models.dart';

/// Snapshot of everything the tests produced, gathered from the controllers.
/// Plain data so the builder below can be tested without any UI or hardware.
class ReportInputs {
  const ReportInputs({
    this.system = const {},
    required this.statuses,
    this.battery,
    this.drives = const [],
    this.cpu,
    this.gpus = const [],
    this.keyboard,
    this.touchpad,
    this.webcam,
    this.speaker,
    this.microphone,
    this.display,
  });

  final Map<String, dynamic> system;
  final Map<ModuleId, TestStatus> statuses;
  final BatteryInfo? battery;
  final List<DriveHealth> drives;
  final StressSummary? cpu;

  /// One result per GPU tested.
  final List<StressSummary> gpus;
  final Map<String, dynamic>? keyboard;
  final Map<String, dynamic>? touchpad;
  final Map<String, dynamic>? webcam;
  final Map<String, dynamic>? speaker;
  final Map<String, dynamic>? microphone;
  final Map<String, dynamic>? display;
}

/// Turns [ReportInputs] into the printable [ReportData]: one entry per test
/// with a headline and detail lines, the score, grade and peak temperatures.
class ReportBuilder {
  ReportBuilder._();

  static ReportData build(
    ReportInputs i, {
    required String id,
    required DateTime createdAt,
    required String technician,
    String? customer,
    required String appVersion,
  }) {
    final tests = <ReportTest>[
      _battery(i),
      _storage(i),
      _cpu(i),
      _gpu(i),
      _keyboard(i),
      _touchpad(i),
      _webcam(i),
      _speaker(i),
      _microphone(i),
      _display(i),
    ];

    // The tests' own verdicts drive the score, so the report always agrees with the sidebar.
    final statuses = {for (final t in tests) _idOf(t.id): t.status};
    final score = computeScore(statuses);

    final cust = customer?.trim();
    return ReportData(
      id: id,
      createdAt: createdAt,
      technician: technician.trim(),
      customer: (cust == null || cust.isEmpty) ? null : cust,
      appVersion: appVersion,
      system: i.system,
      tests: tests,
      score: score.score,
      grade: score.grade,
      testedCount: score.testedCount,
      totalCount: score.totalCount,
      maxCpuTempC: _maxOf([i.cpu?.maxTempC, ...i.gpus.map((g) => g.maxCpuTempC), i.cpu?.maxCpuTempC]),
      maxGpuTempC: _maxOf(i.gpus.map((g) => g.maxGpuTempC)),
    );
  }

  static ModuleId _idOf(String name) => ModuleId.values.firstWhere((m) => m.name == name);

  static double? _maxOf(Iterable<double?> values) {
    final v = values.whereType<double>().toList();
    return v.isEmpty ? null : v.reduce((a, b) => a > b ? a : b);
  }

  static TestStatus _status(ReportInputs i, ModuleId id) => i.statuses[id] ?? TestStatus.notTested;

  static ReportTest _make(ReportInputs i, ModuleId id, String headline, [List<ReportDetail> details = const []]) {
    final status = _status(i, id);
    // A test with no verdict (not run, stopped early, left unfinished) prints as
    // "Not tested": partial numbers would read as a result.
    final unfinished = status == TestStatus.notTested;
    return ReportTest(
      id: id.name,
      title: moduleById(id).title,
      status: status,
      headline: unfinished || headline.isEmpty ? 'Not tested' : headline,
      details: unfinished ? const [] : details,
    );
  }

  static String _temp(double? v) => v == null ? 'N/A' : '${v.round()} °C';

  // --- battery ---------------------------------------------------------------

  static ReportTest _battery(ReportInputs i) {
    final b = i.battery;
    if (b == null) return _make(i, ModuleId.battery, '');
    if (!b.present) return _make(i, ModuleId.battery, 'No battery detected');

    final health = b.healthPercent;
    return _make(
      i,
      ModuleId.battery,
      health == null ? 'Health unavailable' : 'Health $health% · ${b.grade!.label}',
      [
        ReportDetail('Design capacity', b.designMWh == null ? 'N/A' : '${groupThousands(b.designMWh!)} mWh'),
        ReportDetail('Full charge capacity', b.fullChargeMWh == null ? 'N/A' : '${groupThousands(b.fullChargeMWh!)} mWh'),
        ReportDetail('Cycle count', b.cycleCount?.toString() ?? 'N/A'),
        ReportDetail('Charge', '${b.chargePercent == null ? 'N/A' : '${b.chargePercent}%'} · ${b.chargeState.label}'),
        if (b.manufacturer != null) ReportDetail('Manufacturer', b.manufacturer!),
      ],
    );
  }

  // --- storage ---------------------------------------------------------------

  static ReportTest _storage(ReportInputs i) {
    final drives = i.drives;
    if (drives.isEmpty) {
      return _make(i, ModuleId.storage, _status(i, ModuleId.storage).isFinished ? 'No drive could be read' : '');
    }

    final worst = drives.map((d) => d.verdict).reduce((a, b) => a.index >= b.index ? a : b);
    final details = <ReportDetail>[];
    for (var n = 0; n < drives.length; n++) {
      final d = drives[n];
      final cap = d.capacityBytes == null ? '' : ', ${formatCapacity(d.capacityBytes!)}';
      details.add(ReportDetail('Drive ${n + 1}', '${d.model} (${d.type.label}$cap)'));

      final health = <String>[
        d.verdict.label,
        if (d.healthPercent != null) 'health ${d.healthPercent}%' else 'wear not reported',
        if (d.bytesWritten != null) '${formatWritten(d.bytesWritten!)} written',
        if (d.powerOnHours != null) '${groupThousands(d.powerOnHours!)} h powered on',
        if (d.powerCycles != null) '${groupThousands(d.powerCycles!)} power cycles',
        if (d.temperatureC != null) '${d.temperatureC} °C',
      ];
      details.add(ReportDetail('  Health', health.join(' · ')));

      final errors = <String>[
        if (d.unsafeShutdowns != null) '${d.unsafeShutdowns} unsafe shutdowns',
        if (d.mediaErrors != null) '${d.mediaErrors} media errors',
        if (d.reallocatedSectors != null) '${d.reallocatedSectors} reallocated sectors',
      ];
      if (errors.isNotEmpty) details.add(ReportDetail('  Error counters', errors.join(' · ')));
      for (final issue in d.issues) {
        details.add(ReportDetail('  Finding', issue.message));
      }
    }
    return _make(
      i,
      ModuleId.storage,
      '${drives.length} drive${drives.length == 1 ? '' : 's'} · ${worst.label}',
      details,
    );
  }

  // --- CPU / GPU ----------------------------------------------------------------

  static String _mmss(int sec) => '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';

  static List<ReportDetail> _stressDetails(StressSummary s) => [
        if (s.device != null) ReportDetail('Device', s.device!),
        ReportDetail('Temperature', 'max ${_temp(s.maxTempC)} · average ${_temp(s.avgTempC)}'),
        if (s.maxClockMhz != null)
          ReportDetail(
            'Clock speed',
            'peak ${s.maxClockMhz!.round()} MHz'
            '${s.minClockMhz != null ? ' · lowest ${s.minClockMhz!.round()} MHz' : ''}',
          ),
        ReportDetail(
          'Throttling',
          s.throttled ? 'Thermal throttling' : (s.powerLimited ? 'Power limit only (not overheating)' : 'None'),
        ),
        ReportDetail(
          'Duration',
          '${_mmss(s.elapsedSec)}${s.plannedSec != null ? ' of ${_mmss(s.plannedSec!)}' : ''}',
        ),
        if (s.reason == StressEndReason.safety) ReportDetail('Stopped', s.message ?? 'Safety limit reached'),
        if (s.throttleNote != null) ReportDetail('Note', s.throttleNote!),
      ];

  static String _stressHeadline(StressSummary s) {
    if (s.reason == StressEndReason.safety) return 'Stopped at ${_temp(s.maxTempC)} (safety limit)';
    final throttle = s.throttled ? 'thermal throttling' : 'no throttling';
    return 'Max ${_temp(s.maxTempC)} · $throttle';
  }

  static ReportTest _cpu(ReportInputs i) {
    final s = i.cpu;
    if (s == null) return _make(i, ModuleId.cpu, '');
    return _make(i, ModuleId.cpu, _stressHeadline(s), _stressDetails(s));
  }

  static ReportTest _gpu(ReportInputs i) {
    if (i.gpus.isEmpty) return _make(i, ModuleId.gpu, '');
    final details = <ReportDetail>[];
    for (final g in i.gpus) {
      if (i.gpus.length > 1) details.add(ReportDetail(g.device ?? 'GPU', _stressHeadline(g)));
      details.addAll(_stressDetails(g));
    }
    final headline = i.gpus.length == 1
        ? _stressHeadline(i.gpus.first)
        : '${i.gpus.length} GPUs · max ${_temp(_maxOf(i.gpus.map((g) => g.maxTempC)))}';
    return _make(i, ModuleId.gpu, headline, details);
  }

  // --- input devices -----------------------------------------------------------

  static String _list(Object? v) {
    final l = (v as List? ?? const []).map((e) => '$e').toList();
    return l.isEmpty ? 'none' : l.join(', ');
  }

  static ReportTest _keyboard(ReportInputs i) {
    final k = i.keyboard;
    if (k == null) return _make(i, ModuleId.keyboard, '');
    final failed = (k['failed'] as List? ?? const []);
    final head = '${k['tested']} / ${k['total']} keys tested${failed.isEmpty ? '' : ' · ${failed.length} not working'}';
    return _make(i, ModuleId.keyboard, head, [
      ReportDetail('Keys not working', _list(k['failed'])),
      ReportDetail('Keys not tested', _list(k['untested'])),
      if ((k['manuallyConfirmed'] as List? ?? const []).isNotEmpty)
        ReportDetail('Confirmed by hand', _list(k['manuallyConfirmed'])),
      if (((k['ignoredExternalPresses'] as num?) ?? 0) > 0)
        ReportDetail('External keyboard', '${k['ignoredExternalPresses']} key presses ignored'),
    ]);
  }

  static ReportTest _touchpad(ReportInputs i) {
    final t = i.touchpad;
    if (t == null) return _make(i, ModuleId.touchpad, '');
    const names = {
      'move': 'Move cursor',
      'leftClick': 'Left click',
      'rightClick': 'Right click',
      'tap': 'Tap to click',
      'scroll': 'Two-finger scroll',
    };
    String word(Object? s) => switch (s) {
          'detected' => 'Detected',
          'manualPass' => 'Confirmed by hand',
          'failed' => 'Not working',
          _ => 'Not tested',
        };
    final done = names.keys.where((k) => t[k] == 'detected' || t[k] == 'manualPass').length;
    return _make(i, ModuleId.touchpad, '$done / ${names.length} actions OK', [
      for (final e in names.entries) ReportDetail(e.value, word(t[e.key])),
      if (((t['ignoredExternalEvents'] as num?) ?? 0) > 0)
        ReportDetail('External mouse', '${t['ignoredExternalEvents']} events ignored'),
    ]);
  }

  // --- media ---------------------------------------------------------------------

  static ReportTest _webcam(ReportInputs i) {
    final w = i.webcam;
    if (w == null) return _make(i, ModuleId.webcam, '');
    if (w['noCamera'] == true) return _make(i, ModuleId.webcam, 'No camera detected');
    final result = switch (w['result']) {
      'works' => 'Works',
      'not working' => 'Not working',
      _ => 'Not judged',
    };
    return _make(i, ModuleId.webcam, '$result · ${w['resolution'] ?? 'unknown'}', [
      ReportDetail('Camera', '${w['camera'] ?? 'Unknown'}'),
      ReportDetail('Resolution', '${w['resolution'] ?? 'Unknown'}'),
    ]);
  }

  static ReportTest _speaker(ReportInputs i) {
    final s = i.speaker;
    if (s == null) return _make(i, ModuleId.speaker, '');
    String word(Object? v) => v == null ? 'not answered' : '$v';
    return _make(
      i,
      ModuleId.speaker,
      'Left ${word(s['left'])} · Right ${word(s['right'])} · Both ${word(s['both'])}',
      [
        ReportDetail('Left channel', word(s['left'])),
        ReportDetail('Right channel', word(s['right'])),
        ReportDetail('Both channels', word(s['both'])),
      ],
    );
  }

  static ReportTest _microphone(ReportInputs i) {
    final m = i.microphone;
    if (m == null) return _make(i, ModuleId.microphone, '');
    final result = switch (m['result']) {
      'heard' => 'Recording heard',
      'not heard' => 'Recording not heard',
      _ => 'Not judged',
    };
    final peak = (m['peakDb'] as num?)?.toDouble();
    final devices = (m['devices'] as List? ?? const []).join(', ');
    return _make(i, ModuleId.microphone, result, [
      if (devices.isNotEmpty) ReportDetail('Microphone', devices),
      ReportDetail('Peak level', peak == null ? 'N/A' : '${peak.toStringAsFixed(0)} dB'),
      ReportDetail('Signal picked up', m['signalDetected'] == null ? 'N/A' : (m['signalDetected'] == true ? 'Yes' : 'No')),
    ]);
  }

  static ReportTest _display(ReportInputs i) {
    final d = i.display;
    if (d == null) return _make(i, ModuleId.display, '');
    final colors = (d['colorsChecked'] as List? ?? const []);
    final result = switch (d['result']) {
      'no problems' => 'No problems seen',
      'problems seen' => 'Problems seen',
      _ => 'Not judged',
    };
    return _make(i, ModuleId.display, '${colors.length} colours checked · $result', [
      ReportDetail('Colours checked', colors.isEmpty ? 'none' : colors.join(', ')),
      ReportDetail('Result', result),
    ]);
  }
}
