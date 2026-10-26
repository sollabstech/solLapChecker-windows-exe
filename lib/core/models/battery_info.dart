import 'test_status.dart';

enum BatteryGrade {
  good('Good'),
  fair('Fair'),
  replace('Replace');

  const BatteryGrade(this.label);
  final String label;

  /// ≥80% Good, 60–79% Fair, <60% Replace (on the whole-number health shown).
  static BatteryGrade forHealth(int healthPercent) {
    if (healthPercent >= 80) return good;
    if (healthPercent >= 60) return fair;
    return replace;
  }
}

enum ChargeState {
  charging('Charging'),
  discharging('On battery'),
  pluggedIn('Plugged in'),
  full('Fully charged'),
  unknown('Unknown');

  const ChargeState(this.label);
  final String label;
}

/// Where the capacity numbers came from.
enum BatterySource { wmi, powercfg }

/// Snapshot of the laptop battery.
class BatteryInfo {
  const BatteryInfo({
    required this.present,
    this.designMWh,
    this.fullChargeMWh,
    this.cycleCount,
    this.chargePercent,
    this.chargeState = ChargeState.unknown,
    this.manufacturer,
    this.chemistry,
    this.source = BatterySource.wmi,
  });

  /// No battery found at all (desktop, removed or dead-and-undetected pack).
  const BatteryInfo.none() : this(present: false);

  final bool present;
  final int? designMWh;
  final int? fullChargeMWh;
  final int? cycleCount;
  final int? chargePercent;
  final ChargeState chargeState;
  final String? manufacturer;
  final String? chemistry;
  final BatterySource source;

  /// Full-charge ÷ design capacity as a whole percent (capped at 100);
  /// null when either capacity is unavailable.
  int? get healthPercent {
    final d = designMWh;
    final f = fullChargeMWh;
    if (d == null || f == null || d <= 0 || f <= 0) return null;
    return (f / d * 100).round().clamp(0, 100);
  }

  BatteryGrade? get grade {
    final h = healthPercent;
    return h == null ? null : BatteryGrade.forHealth(h);
  }

  /// Verdict for the sidebar and report. A missing battery or unreadable
  /// capacity is a warning: the buyer should know before paying.
  TestStatus get testStatus {
    if (!present) return TestStatus.warning;
    return switch (grade) {
      BatteryGrade.good => TestStatus.pass,
      BatteryGrade.fair => TestStatus.warning,
      BatteryGrade.replace => TestStatus.fail,
      null => TestStatus.warning,
    };
  }

  /// Copy with fields from [other] filling any that are missing here.
  BatteryInfo fillFrom(BatteryInfo other) => BatteryInfo(
        present: present || other.present,
        designMWh: designMWh ?? other.designMWh,
        fullChargeMWh: fullChargeMWh ?? other.fullChargeMWh,
        cycleCount: cycleCount ?? other.cycleCount,
        chargePercent: chargePercent ?? other.chargePercent,
        chargeState: chargeState == ChargeState.unknown ? other.chargeState : chargeState,
        manufacturer: manufacturer ?? other.manufacturer,
        chemistry: chemistry ?? other.chemistry,
        source: designMWh == null && other.designMWh != null ? other.source : source,
      );

  Map<String, dynamic> toJson() => {
        'present': present,
        'designCapacityMWh': designMWh,
        'fullChargeCapacityMWh': fullChargeMWh,
        'healthPercent': healthPercent,
        'grade': grade?.label,
        'cycleCount': cycleCount,
        'chargePercent': chargePercent,
        'chargeState': chargeState.label,
        'manufacturer': manufacturer,
        'chemistry': chemistry,
        'source': source.name,
      };

  // --- parsing -------------------------------------------------------------

  /// Parses the JSON emitted by `BatteryService`'s PowerShell script.
  factory BatteryInfo.fromWmiJson(Map<String, dynamic> j) {
    final batteries = _list(j['batteries']);
    final design = _sum(batteries.map((b) => _int(b['design'])));
    final full = _sum(_list(j['full']).map((b) => _int(b['full'])));
    final cycles = _sum(_list(j['cycles']).map((b) => _int(b['count'])));
    final status = _list(j['status']);
    final win32 = _list(j['win32']);

    final present = batteries.isNotEmpty ||
        win32.isNotEmpty ||
        design != null ||
        full != null;
    if (!present) return const BatteryInfo.none();

    // 0 is what drivers report when they simply do not support a counter.
    final cycleCount = (cycles ?? 0) > 0 ? cycles : null;

    final percent = _int(win32.isEmpty ? null : win32.first['percent']);

    return BatteryInfo(
      present: true,
      designMWh: (design ?? 0) > 0 ? design : null,
      fullChargeMWh: (full ?? 0) > 0 ? full : null,
      cycleCount: cycleCount,
      chargePercent: percent?.clamp(0, 100),
      chargeState: _chargeState(status, win32),
      manufacturer: _clean(batteries.isEmpty ? null : batteries.first['manufacturer']),
      chemistry: _chemistry(win32.isEmpty ? null : _int(win32.first['chemistry'])),
    );
  }

  /// Parses the XML written by `powercfg /batteryreport /xml`.
  /// Used when the WMI classes are missing or report nothing.
  factory BatteryInfo.fromPowercfgXml(String xml) {
    final blocks = RegExp(r'<Battery>(.*?)</Battery>', dotAll: true)
        .allMatches(xml)
        .map((m) => m.group(1)!)
        .toList();
    if (blocks.isEmpty) return const BatteryInfo.none();

    int? tag(String block, String name) {
      final m = RegExp('<$name>\\s*(\\d+)\\s*</$name>').firstMatch(block);
      return m == null ? null : int.tryParse(m.group(1)!);
    }

    String? text(String block, String name) {
      final m = RegExp('<$name>\\s*([^<]*?)\\s*</$name>').firstMatch(block);
      final v = m?.group(1);
      return (v == null || v.isEmpty) ? null : v;
    }

    final design = _sum(blocks.map((b) => tag(b, 'DesignCapacity')));
    final full = _sum(blocks.map((b) => tag(b, 'FullChargeCapacity')));
    final cycles = _sum(blocks.map((b) => tag(b, 'CycleCount')));

    return BatteryInfo(
      present: true,
      designMWh: (design ?? 0) > 0 ? design : null,
      fullChargeMWh: (full ?? 0) > 0 ? full : null,
      cycleCount: (cycles ?? 0) > 0 ? cycles : null,
      manufacturer: text(blocks.first, 'Manufacturer'),
      chemistry: text(blocks.first, 'Chemistry'),
      source: BatterySource.powercfg,
    );
  }
}

// --- helpers -----------------------------------------------------------------

List<Map<String, dynamic>> _list(Object? v) {
  if (v is List) return v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  if (v is Map) return [v.cast<String, dynamic>()];
  return const [];
}

int? _int(Object? v) {
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}');
}

int? _sum(Iterable<int?> values) {
  final present = values.whereType<int>().toList();
  return present.isEmpty ? null : present.fold<int>(0, (a, b) => a + b);
}

String? _clean(Object? v) {
  final s = (v ?? '').toString().trim();
  return s.isEmpty ? null : s;
}

/// Win32_Battery.Chemistry codes.
String? _chemistry(int? code) => switch (code) {
      3 => 'Lead acid',
      4 => 'Nickel cadmium',
      5 => 'Nickel metal hydride',
      6 => 'Lithium-ion',
      7 => 'Zinc air',
      8 => 'Lithium polymer',
      _ => null,
    };

ChargeState _chargeState(List<Map<String, dynamic>> status, List<Map<String, dynamic>> win32) {
  if (status.isNotEmpty) {
    final s = status.first;
    if (s['charging'] == true) return ChargeState.charging;
    if (s['discharging'] == true) return ChargeState.discharging;
    if (s['powerOnline'] == true) return ChargeState.pluggedIn;
  }
  // Win32_Battery.BatteryStatus codes.
  switch (win32.isEmpty ? null : _int(win32.first['status'])) {
    case 1:
    case 4:
    case 5:
      return ChargeState.discharging;
    case 2:
      return ChargeState.pluggedIn;
    case 3:
      return ChargeState.full;
    case 6:
    case 7:
    case 8:
    case 9:
      return ChargeState.charging;
    default:
      return ChargeState.unknown;
  }
}
