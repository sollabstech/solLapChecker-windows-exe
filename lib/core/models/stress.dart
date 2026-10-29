import 'dart:convert';

import 'test_status.dart';

/// Messages that SolHelper.exe prints as JSON lines (see helper/SolHelper/Protocol.cs).

/// One second of readings during a stress test.
class StressSample {
  const StressSample({
    required this.t,
    this.tempC,
    this.clockMhz,
    this.loadPct,
    this.powerW,
    this.cpuTempC,
    this.gpuTempC,
  });

  final int t;

  /// Temperature of the part under test.
  final double? tempC;
  final double? clockMhz;
  final double? loadPct;
  final double? powerW;
  final double? cpuTempC;
  final double? gpuTempC;

  factory StressSample.fromJson(Map<String, dynamic> j) => StressSample(
        t: _int(j['t']) ?? 0,
        tempC: _num(j['tempC']),
        clockMhz: _num(j['clockMhz']),
        loadPct: _num(j['loadPct']),
        powerW: _num(j['powerW']),
        cpuTempC: _num(j['cpuTempC']),
        gpuTempC: _num(j['gpuTempC']),
      );
}

enum StressEndReason { completed, stopped, safety, error }

/// Final result of a stress test, as reported by the helper.
class StressSummary {
  const StressSummary({
    required this.test,
    required this.reason,
    this.message,
    this.elapsedSec = 0,
    this.samples = 0,
    this.maxTempC,
    this.avgTempC,
    this.minTempC,
    this.maxClockMhz,
    this.minClockMhz,
    this.avgLoadPct,
    this.maxCpuTempC,
    this.maxGpuTempC,
    this.throttled = false,
    this.powerLimited = false,
    this.throttleNote,
    this.device,
    this.plannedSec,
  });

  final String test;
  final StressEndReason reason;
  final String? message;
  final int elapsedSec;
  final int samples;
  final double? maxTempC;
  final double? avgTempC;
  final double? minTempC;
  final double? maxClockMhz;
  final double? minClockMhz;
  final double? avgLoadPct;
  final double? maxCpuTempC;
  final double? maxGpuTempC;

  /// Thermal throttling (clock collapse while hot).
  final bool throttled;

  /// Clock settled lower without overheating: a power/boost limit, not a defect.
  final bool powerLimited;
  final String? throttleNote;

  /// Filled in by the app, not the helper.
  final String? device;
  final int? plannedSec;

  /// Peak temperature at or above this on a completed run is flagged as a warning.
  static const hotWarningC = 90.0;

  /// Verdict for the sidebar and report.
  ///
  /// * a CPU that heats up to the safety limit is a warning: laptop CPUs often
  ///   run that hot under full load, so it is a cooling concern, not a defect.
  ///   The same goes for a GPU test stopped because the CPU got that hot while
  ///   the GPU itself stayed below it;
  /// * any other safety stop (a GPU at the limit, a sensor going dark) is a fail;
  /// * a run that was stopped early or errored has no verdict;
  /// * completing with thermal throttling is a warning; so is a very high peak
  ///   on a GPU (a laptop CPU at 90-100 °C under full load is normal);
  /// * otherwise pass.
  TestStatus get status {
    switch (reason) {
      case StressEndReason.safety:
        return stoppedByCpuHeat ? TestStatus.warning : TestStatus.fail;
      case StressEndReason.stopped:
      case StressEndReason.error:
        return TestStatus.notTested;
      case StressEndReason.completed:
        if (throttled || peakIsConcern) return TestStatus.warning;
        return TestStatus.pass;
    }
  }

  /// A peak of [hotWarningC] or more matters for a GPU; a laptop CPU runs that hot normally.
  bool get peakIsConcern => test != 'cpu' && (maxTempC ?? 0) >= hotWarningC;

  /// A safety stop caused by the processor's heat, not by a sensor that stopped
  /// responding (that stop leaves every peak well under the limit):
  /// * CPU test: the CPU itself got hot;
  /// * GPU test: the CPU got hot while the GPU's own temperature stayed below
  ///   the warning level (or the GPU has no sensor of its own).
  bool get stoppedByCpuHeat {
    if (reason != StressEndReason.safety) return false;
    if (test == 'cpu') return (maxTempC ?? 0) >= hotWarningC;
    if (test == 'gpu') return (maxTempC ?? 0) < hotWarningC && (maxCpuTempC ?? 0) >= hotWarningC;
    return false;
  }

  StressSummary withContext({String? device, int? plannedSec}) => StressSummary(
        test: test,
        reason: reason,
        message: message,
        elapsedSec: elapsedSec,
        samples: samples,
        maxTempC: maxTempC,
        avgTempC: avgTempC,
        minTempC: minTempC,
        maxClockMhz: maxClockMhz,
        minClockMhz: minClockMhz,
        avgLoadPct: avgLoadPct,
        maxCpuTempC: maxCpuTempC,
        maxGpuTempC: maxGpuTempC,
        throttled: throttled,
        powerLimited: powerLimited,
        throttleNote: throttleNote,
        device: device ?? this.device,
        plannedSec: plannedSec ?? this.plannedSec,
      );

  factory StressSummary.fromJson(Map<String, dynamic> j) => StressSummary(
        test: '${j['test'] ?? ''}',
        reason: switch (j['reason']) {
          'completed' => StressEndReason.completed,
          'stopped' => StressEndReason.stopped,
          'safety' => StressEndReason.safety,
          _ => StressEndReason.error,
        },
        message: j['message'] as String?,
        elapsedSec: _int(j['elapsedSec']) ?? 0,
        samples: _int(j['samples']) ?? 0,
        maxTempC: _num(j['maxTempC']),
        avgTempC: _num(j['avgTempC']),
        minTempC: _num(j['minTempC']),
        maxClockMhz: _num(j['maxClockMhz']),
        minClockMhz: _num(j['minClockMhz']),
        avgLoadPct: _num(j['avgLoadPct']),
        maxCpuTempC: _num(j['maxCpuTempC']),
        maxGpuTempC: _num(j['maxGpuTempC']),
        throttled: j['throttled'] == true,
        powerLimited: j['powerLimited'] == true,
        throttleNote: j['throttleNote'] as String?,
      );

  /// Form stored in the saved report JSON.
  Map<String, dynamic> toJson() => {
        'test': test,
        'device': device,
        'result': status.label,
        'reason': reason.name,
        'message': message,
        'plannedSec': plannedSec,
        'elapsedSec': elapsedSec,
        'maxTempC': maxTempC,
        'avgTempC': avgTempC,
        'minTempC': minTempC,
        'maxClockMhz': maxClockMhz,
        'minClockMhz': minClockMhz,
        'avgLoadPct': avgLoadPct,
        'maxCpuTempC': maxCpuTempC,
        'maxGpuTempC': maxGpuTempC,
        'throttled': throttled,
        'powerLimited': powerLimited,
        'throttleNote': throttleNote,
      };
}

/// A GPU the helper can stress.
class GpuDevice {
  const GpuDevice({
    required this.index,
    required this.name,
    required this.integrated,
    this.dedicatedMb = 0,
    this.hasTempSensor = false,
    this.hasOwnTempSensor = false,
  });

  /// DXGI adapter index; passed back to `gpu-stress --gpu`.
  final int index;
  final String name;
  final bool integrated;
  final int dedicatedMb;

  /// A usable temperature exists (own sensor, or the CPU package as a stand-in).
  final bool hasTempSensor;
  final bool hasOwnTempSensor;

  String get kind => integrated ? 'Integrated GPU' : 'Dedicated GPU';

  factory GpuDevice.fromJson(Map<String, dynamic> j) => GpuDevice(
        index: _int(j['index']) ?? 0,
        name: '${j['name'] ?? 'GPU'}',
        integrated: j['kind'] == 'integrated',
        dedicatedMb: _int(j['dedicatedMb']) ?? 0,
        hasTempSensor: j['hasTempSensor'] == true,
        hasOwnTempSensor: j['hasOwnTempSensor'] == true,
      );
}

/// Result of `SolHelper info`.
class HelperInfo {
  const HelperInfo({
    required this.version,
    required this.admin,
    required this.pawnIo,
    this.sensorError,
    this.cpuName,
    this.cpuTempAvailable = false,
    this.cpuTempC,
    this.gpus = const [],
  });

  final String version;
  final bool admin;

  /// The PawnIO sensor driver is installed (needed for CPU temperatures).
  final bool pawnIo;
  final String? sensorError;
  final String? cpuName;
  final bool cpuTempAvailable;
  final double? cpuTempC;
  final List<GpuDevice> gpus;

  factory HelperInfo.fromJson(Map<String, dynamic> j) => HelperInfo(
        version: '${j['version'] ?? ''}',
        admin: j['admin'] == true,
        pawnIo: j['pawnIo'] == true,
        sensorError: j['sensorError'] as String?,
        cpuName: j['cpuName'] as String?,
        cpuTempAvailable: j['cpuTempAvailable'] == true,
        cpuTempC: _num(j['cpuTempC']),
        gpus: [
          for (final g in (j['gpus'] as List? ?? const []).whereType<Map>())
            GpuDevice.fromJson(g.cast<String, dynamic>()),
        ],
      );
}

// --- stream events --------------------------------------------------------------

sealed class StressEvent {
  const StressEvent();
}

class StressStarted extends StressEvent {
  const StressStarted({required this.durationSec, required this.limitC, required this.device, this.tempSource});

  final int durationSec;
  final double limitC;
  final String device;

  /// e.g. "cpu-package" when an integrated GPU's temperature is borrowed from the CPU.
  final String? tempSource;
}

class StressSampled extends StressEvent {
  const StressSampled(this.sample);
  final StressSample sample;
}

class StressWarning extends StressEvent {
  const StressWarning(this.message);
  final String message;
}

class StressFailed extends StressEvent {
  const StressFailed(this.code, this.message);
  final String code;
  final String message;
}

class StressEnded extends StressEvent {
  const StressEnded(this.summary);
  final StressSummary summary;
}

class HelperInfoEvent extends StressEvent {
  const HelperInfoEvent(this.info);
  final HelperInfo info;
}

/// Decodes one stdout line from SolHelper. Anything that is not a JSON
/// object with a known "type" (stray log text, blank lines) yields null.
StressEvent? parseHelperLine(String line) {
  final text = line.trim();
  if (!text.startsWith('{')) return null;

  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;

  switch (decoded['type']) {
    case 'start':
      return StressStarted(
        durationSec: _int(decoded['durationSec']) ?? 0,
        limitC: _num(decoded['limitC']) ?? 95,
        device: '${decoded['device'] ?? ''}',
        tempSource: decoded['tempSource'] as String?,
      );
    case 'sample':
      return StressSampled(StressSample.fromJson(decoded));
    case 'warning':
      return StressWarning('${decoded['message'] ?? ''}');
    case 'error':
      return StressFailed('${decoded['code'] ?? 'error'}', '${decoded['message'] ?? 'Unknown error'}');
    case 'end':
      return StressEnded(StressSummary.fromJson(decoded));
    case 'info':
      return HelperInfoEvent(HelperInfo.fromJson(decoded));
    default:
      return null;
  }
}

num? _numRaw(Object? v) => v is num ? v : num.tryParse('${v ?? ''}');

double? _num(Object? v) => _numRaw(v)?.toDouble();

int? _int(Object? v) => _numRaw(v)?.toInt();

/// Plain-language result line shown under a finished stress test.
/// With [withTemperatures] false no temperature figure is mentioned.
String describeStressSummary(StressSummary s, {String part = 'processor', bool withTemperatures = true}) {
  final max = withTemperatures ? s.maxTempC?.round() : null;
  switch (s.reason) {
    case StressEndReason.safety:
      final stop = withTemperatures
          ? 'Stopped automatically to protect the laptop. ${s.message ?? ''}'.trim()
          : 'Stopped early to protect the laptop because it got too hot.';
      if (!s.stoppedByCpuHeat) return stop;
      final who = s.test == 'gpu'
          ? 'It was the processor (CPU) that got this hot, not the graphics card. '
          : 'Many laptop processors run this hot under full load. ';
      return '$stop ${who}This is a warning, not a fault. '
          'If it happens within seconds, cleaning the fans or renewing the thermal paste usually helps.';
    case StressEndReason.stopped:
      return 'Stopped before the end, so there is no verdict. Run the full duration for a result.';
    case StressEndReason.error:
      return s.message ?? 'The test could not finish.';
    case StressEndReason.completed:
      if (s.throttled) {
        return s.throttleNote ?? 'The $part throttled because of heat.';
      }
      if (s.peakIsConcern) {
        final peak = max == null ? '' : ' (peak $max °C)';
        return 'The $part ran very hot$peak. Cooling may need cleaning or new thermal paste.';
      }
      final limited = s.powerLimited ? ' ${s.throttleNote ?? ''}' : '';
      return 'Held up under full load${max == null ? '' : ', peak $max °C'}.$limited'.trim();
  }
}
