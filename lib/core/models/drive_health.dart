import 'test_status.dart';

enum DriveType {
  nvme('NVMe SSD'),
  sataSsd('SATA SSD'),
  hdd('HDD'),
  unknown('Drive');

  const DriveType(this.label);
  final String label;

  bool get isSsd => this == nvme || this == sataSsd;
}

enum DriveVerdict {
  good('Good', TestStatus.pass),
  caution('Caution', TestStatus.warning),
  bad('Bad', TestStatus.fail);

  const DriveVerdict(this.label, this.status);
  final String label;
  final TestStatus status;
}

/// Health summary of one physical drive, built from `smartctl -a -j` output.
class DriveHealth {
  const DriveHealth({
    required this.device,
    required this.model,
    required this.type,
    this.serial,
    this.firmware,
    this.capacityBytes,
    this.healthPercent,
    this.percentUsed,
    this.bytesWritten,
    this.powerOnHours,
    this.powerCycles,
    this.temperatureC,
    this.unsafeShutdowns,
    this.mediaErrors,
    this.reallocatedSectors,
    this.pendingSectors,
    this.availableSpare,
    this.spareThreshold,
    this.criticalWarning,
    this.smartPassed,
  });

  final String device;
  final String model;
  final DriveType type;
  final String? serial;
  final String? firmware;
  final int? capacityBytes;

  /// Remaining life, 0..100 (100 = like new). Null when the drive does not report wear.
  final int? healthPercent;

  /// Rated life consumed, 0..100 (the inverse of [healthPercent]).
  final int? percentUsed;

  /// Total host data written (TBW), in bytes.
  final int? bytesWritten;
  final int? powerOnHours;
  final int? powerCycles;
  final int? temperatureC;
  final int? unsafeShutdowns;
  final int? mediaErrors;
  final int? reallocatedSectors;
  final int? pendingSectors;
  final int? availableSpare;
  final int? spareThreshold;
  final int? criticalWarning;

  /// smartctl's overall SMART self-assessment (null if unknown).
  final bool? smartPassed;

  // --- verdict -------------------------------------------------------------
  //
  // Heuristic thresholds. They are conservative rules of thumb for a
  // buy/sell check, not manufacturer warranty limits.

  static const _tempCaution = 70;
  static const _usedCaution = 70;
  static const _usedBad = 90;
  static const _spareCaution = 50;
  static const _mediaErrorsBad = 50;
  static const _reallocatedBad = 100;
  static const _pendingBad = 50;

  /// Every reason the drive is not simply "Good", each tagged with severity.
  List<DriveIssue> get issues {
    final out = <DriveIssue>[];
    void bad(String m) => out.add(DriveIssue(DriveVerdict.bad, m));
    void caution(String m) => out.add(DriveIssue(DriveVerdict.caution, m));

    if (smartPassed == false) bad('SMART self-assessment reports the drive as failing');
    if ((criticalWarning ?? 0) != 0) bad('Drive reports a critical warning (flags: $criticalWarning)');

    final used = percentUsed;
    if (used != null) {
      if (used >= _usedBad) {
        bad('$used% of the rated lifetime is used');
      } else if (used >= _usedCaution) {
        caution('$used% of the rated lifetime is used');
      }
    }

    final spare = availableSpare;
    final threshold = spareThreshold;
    if (spare != null && threshold != null && spare < threshold) {
      bad('Spare capacity ($spare%) is below the drive threshold ($threshold%)');
    } else if (spare != null && spare < _spareCaution) {
      caution('Spare capacity is down to $spare%');
    }

    final media = mediaErrors ?? 0;
    if (media >= _mediaErrorsBad) {
      bad('$media media errors');
    } else if (media > 0) {
      caution('$media media error${media == 1 ? '' : 's'}');
    }

    final realloc = reallocatedSectors ?? 0;
    if (realloc >= _reallocatedBad) {
      bad('$realloc reallocated sectors');
    } else if (realloc > 0) {
      caution('$realloc reallocated sector${realloc == 1 ? '' : 's'}');
    }

    final pending = pendingSectors ?? 0;
    if (pending >= _pendingBad) {
      bad('$pending sectors waiting to be reallocated');
    } else if (pending > 0) {
      caution('$pending sector${pending == 1 ? '' : 's'} waiting to be reallocated');
    }

    final temp = temperatureC;
    if (temp != null && temp >= _tempCaution) caution('Running hot at $temp °C');

    return out;
  }

  DriveVerdict get verdict {
    final all = issues;
    if (all.any((i) => i.severity == DriveVerdict.bad)) return DriveVerdict.bad;
    if (all.isNotEmpty) return DriveVerdict.caution;
    return DriveVerdict.good;
  }

  Map<String, dynamic> toJson() => {
        'device': device,
        'model': model,
        'type': type.label,
        'serial': serial,
        'firmware': firmware,
        'capacityBytes': capacityBytes,
        'verdict': verdict.label,
        'healthPercent': healthPercent,
        'percentUsed': percentUsed,
        'bytesWritten': bytesWritten,
        'powerOnHours': powerOnHours,
        'powerCycles': powerCycles,
        'temperatureC': temperatureC,
        'unsafeShutdowns': unsafeShutdowns,
        'mediaErrors': mediaErrors,
        'reallocatedSectors': reallocatedSectors,
        'pendingSectors': pendingSectors,
        'issues': issues.map((i) => i.message).toList(),
      };

  // --- parsing -------------------------------------------------------------

  /// Builds a [DriveHealth] from one `smartctl -a -j` document.
  /// Returns null when the document describes no usable drive.
  static DriveHealth? fromSmartctlJson(Map<String, dynamic> j) {
    final model = _str(j['model_name']) ?? _str(j['model_family']);
    if (model == null) return null;

    final device = _map(j['device']);
    final protocol = _str(device['protocol'])?.toLowerCase();
    final deviceType = _str(device['type'])?.toLowerCase();
    final isNvme = protocol == 'nvme' || deviceType == 'nvme' || j['nvme_smart_health_information_log'] is Map;

    final rotation = _int(j['rotation_rate']);
    final type = isNvme
        ? DriveType.nvme
        : rotation == null
            ? DriveType.unknown
            : rotation == 0
                ? DriveType.sataSsd
                : DriveType.hdd;

    final nvme = _map(j['nvme_smart_health_information_log']);
    final attrs = _attributes(j);
    final blockSize = _int(j['logical_block_size']) ?? 512;

    int? healthPercent;
    int? percentUsed;
    int? written;
    int? unsafe;
    int? mediaErrors;

    if (isNvme) {
      percentUsed = _int(nvme['percentage_used'])?.clamp(0, 100);
      healthPercent = percentUsed == null ? null : 100 - percentUsed;
      final units = _int(nvme['data_units_written']);
      // One NVMe "data unit" is 1000 × 512 bytes.
      written = units == null ? null : units * 512000;
      unsafe = _int(nvme['unsafe_shutdowns']);
      mediaErrors = _int(nvme['media_errors']);
    } else {
      healthPercent = type.isSsd ? _remainingLife(attrs) : null;
      percentUsed = healthPercent == null ? null : 100 - healthPercent;
      written = _bytesWritten(attrs, blockSize);
      unsafe = type == DriveType.hdd ? null : _rawByName(attrs, _unsafeNames);
      mediaErrors = _rawById(attrs, 187);
    }

    return DriveHealth(
      device: _str(device['name']) ?? 'unknown',
      model: model,
      type: type,
      serial: _str(j['serial_number']),
      firmware: _str(j['firmware_version']),
      capacityBytes: _int(_map(j['user_capacity'])['bytes']) ?? _int(j['nvme_total_capacity']),
      healthPercent: healthPercent,
      percentUsed: percentUsed,
      bytesWritten: written,
      powerOnHours: _int(_map(j['power_on_time'])['hours']) ?? _int(nvme['power_on_hours']),
      powerCycles: _int(j['power_cycle_count']) ?? _int(nvme['power_cycles']),
      temperatureC: _int(_map(j['temperature'])['current']) ?? _int(nvme['temperature']),
      unsafeShutdowns: unsafe,
      mediaErrors: mediaErrors,
      reallocatedSectors: isNvme ? null : _rawById(attrs, 5),
      pendingSectors: isNvme ? null : _rawById(attrs, 197),
      availableSpare: _int(nvme['available_spare']),
      spareThreshold: _int(nvme['available_spare_threshold']),
      criticalWarning: _int(nvme['critical_warning']),
      smartPassed: _map(j['smart_status'])['passed'] as bool?,
    );
  }
}

/// One finding that lowers a drive's verdict.
class DriveIssue {
  const DriveIssue(this.severity, this.message);
  final DriveVerdict severity;
  final String message;
}

/// Overall result for the Storage test across all drives.
TestStatus statusForDrives(List<DriveHealth> drives) {
  if (drives.isEmpty) return TestStatus.warning;
  if (drives.any((d) => d.verdict == DriveVerdict.bad)) return TestStatus.fail;
  if (drives.any((d) => d.verdict == DriveVerdict.caution)) return TestStatus.warning;
  return TestStatus.pass;
}

// --- SMART attribute helpers ---------------------------------------------------

class _Attr {
  const _Attr(this.id, this.name, this.value, this.raw);
  final int id;
  final String name;
  final int? value; // normalised 0..255
  final int? raw;
}

List<_Attr> _attributes(Map<String, dynamic> j) {
  final table = _map(j['ata_smart_attributes'])['table'];
  if (table is! List) return const [];
  return [
    for (final e in table.whereType<Map>())
      _Attr(
        _int(e['id']) ?? -1,
        _str(e['name']) ?? '',
        _int(e['value']),
        _int(_map(e['raw'])['value']),
      ),
  ];
}

int? _rawById(List<_Attr> a, int id) {
  for (final x in a) {
    if (x.id == id) return x.raw;
  }
  return null;
}

int? _rawByName(List<_Attr> a, Set<String> names) {
  for (final x in a) {
    if (names.contains(x.name)) return x.raw;
  }
  return null;
}

/// Attributes whose normalised value is "life remaining" in percent.
const _lifeNames = {
  'Wear_Leveling_Count',
  'Media_Wearout_Indicator',
  'SSD_Life_Left',
  'Percent_Lifetime_Remain',
  'Remaining_Lifetime_Perc',
};

const _unsafeNames = {
  'Unexpect_Power_Loss_Ct',
  'Unexpected_Power_Loss_Ct',
  'Power-Off_Retract_Count',
};

int? _remainingLife(List<_Attr> a) {
  for (final x in a) {
    if (_lifeNames.contains(x.name) && x.value != null) return x.value!.clamp(0, 100);
  }
  return null;
}

/// Total host writes in bytes; vendors report it in different units.
int? _bytesWritten(List<_Attr> a, int blockSize) {
  for (final x in a) {
    final raw = x.raw;
    if (raw == null) continue;
    switch (x.name) {
      case 'Total_LBAs_Written':
      case 'Total_Host_Sector_Write':
        return raw * blockSize;
      case 'Host_Writes_32MiB':
        return raw * 32 * 1024 * 1024;
      case 'Host_Writes_GiB':
      case 'Total_Writes_GiB':
      case 'Lifetime_Writes_GiB':
        return raw * 1024 * 1024 * 1024;
    }
  }
  return null;
}

Map<String, dynamic> _map(Object? v) => v is Map ? v.cast<String, dynamic>() : const <String, dynamic>{};

int? _int(Object? v) {
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}');
}

String? _str(Object? v) {
  final s = (v ?? '').toString().trim();
  return s.isEmpty ? null : s;
}
