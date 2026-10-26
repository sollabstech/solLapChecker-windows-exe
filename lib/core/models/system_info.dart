import '../utils/format.dart';

/// Laptop identity and hardware summary shown on the dashboard
/// and printed in the report.
class SystemInfo {
  const SystemInfo({
    required this.brand,
    required this.model,
    required this.serialNumber,
    required this.biosVersion,
    required this.biosDate,
    required this.cpu,
    required this.gpus,
    required this.ramTotalBytes,
    required this.ramModules,
    required this.drives,
    required this.windows,
    required this.displayResolution,
  });

  final String brand;
  final String model;
  final String serialNumber;
  final String biosVersion;
  final String biosDate;
  final CpuInfo cpu;
  final List<GpuInfo> gpus;
  final int ramTotalBytes;
  final List<RamModule> ramModules;
  final List<DriveInfo> drives;
  final String windows;

  /// e.g. "1920 × 1080 @ 60 Hz"; null if Windows did not report one.
  final String? displayResolution;

  String get ramSummary {
    if (ramTotalBytes <= 0) return 'Unknown';
    final speeds = ramModules.map((m) => m.speedMhz).whereType<int>().toSet();
    final type = ramModules.map((m) => m.type).whereType<String>().toSet();
    final extras = [
      if (type.length == 1) type.first,
      if (speeds.length == 1) '${speeds.first} MHz',
    ];
    final base = formatRam(ramTotalBytes);
    return extras.isEmpty ? base : '$base · ${extras.join(' ')}';
  }

  String get storageSummary {
    if (drives.isEmpty) return 'Unknown';
    final total = drives.fold<int>(0, (sum, d) => sum + d.sizeBytes);
    return formatCapacity(total);
  }

  factory SystemInfo.fromJson(Map<String, dynamic> json) {
    final cs = _map(json['computer']);
    final product = _map(json['product']);
    final bios = _map(json['bios']);
    final os = _map(json['os']);

    final manufacturer = _str(cs['manufacturer']);
    final rawModel = _str(cs['model']);
    final productName = _str(product['version']);

    return SystemInfo(
      brand: _tidyBrand(manufacturer),
      model: _friendlyModel(manufacturer, rawModel, productName),
      serialNumber: _str(bios['serial']),
      biosVersion: _str(bios['version']),
      biosDate: _str(bios['releaseDate']),
      cpu: CpuInfo.fromJson(_map(json['cpu'])),
      gpus: _list(json['gpus']).map(GpuInfo.fromJson).toList(),
      ramTotalBytes: _int(cs['totalMemory']) ?? 0,
      ramModules: _list(json['ram']).map(RamModule.fromJson).toList(),
      drives: _list(json['disks']).map(DriveInfo.fromJson).toList(),
      windows: _windowsLabel(os),
      displayResolution: _resolution(_list(json['gpus'])),
    );
  }

  /// Plain-map form stored inside the saved report JSON.
  Map<String, dynamic> toJson() => {
        'brand': brand,
        'model': model,
        'serialNumber': serialNumber,
        'bios': '$biosVersion ($biosDate)',
        'cpu': cpu.name,
        'cpuCores': cpu.cores,
        'cpuThreads': cpu.threads,
        'gpus': gpus.map((g) => g.name).toList(),
        'ram': ramSummary,
        'storage': drives
            .map((d) => '${d.model} (${formatCapacity(d.sizeBytes)})')
            .toList(),
        'windows': windows,
        'display': displayResolution,
      };
}

class CpuInfo {
  const CpuInfo({required this.name, required this.cores, required this.threads, this.maxMhz});

  final String name;
  final int cores;
  final int threads;
  final int? maxMhz;

  String get summary =>
      '$cores cores / $threads threads${maxMhz != null ? ' · up to ${(maxMhz! / 1000).toStringAsFixed(2)} GHz' : ''}';

  factory CpuInfo.fromJson(Map<String, dynamic> j) => CpuInfo(
        name: _squash(_str(j['name'])),
        cores: _int(j['cores']) ?? 0,
        threads: _int(j['threads']) ?? 0,
        maxMhz: _int(j['maxMhz']),
      );
}

class GpuInfo {
  const GpuInfo({required this.name, required this.driver});

  final String name;
  final String driver;

  factory GpuInfo.fromJson(Map<String, dynamic> j) =>
      GpuInfo(name: _str(j['name']), driver: _str(j['driver']));
}

class RamModule {
  const RamModule({required this.bytes, this.speedMhz, this.type});

  final int bytes;
  final int? speedMhz;
  final String? type;

  factory RamModule.fromJson(Map<String, dynamic> j) => RamModule(
        bytes: _int(j['capacity']) ?? 0,
        speedMhz: _int(j['speed']),
        type: _ramType(_int(j['smbiosType'])),
      );
}

class DriveInfo {
  const DriveInfo({required this.model, required this.sizeBytes});

  final String model;
  final int sizeBytes;

  factory DriveInfo.fromJson(Map<String, dynamic> j) =>
      DriveInfo(model: _squash(_str(j['model'])), sizeBytes: _int(j['size']) ?? 0);
}

// ---------------------------------------------------------------------------
// Tolerant JSON helpers: PowerShell turns one-element arrays into plain
// objects and missing values into null, so every field is read defensively.
// ---------------------------------------------------------------------------

Map<String, dynamic> _map(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : const <String, dynamic>{};

List<Map<String, dynamic>> _list(Object? v) {
  if (v is List) return v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  if (v is Map) return [v.cast<String, dynamic>()];
  return const [];
}

String _str(Object? v) {
  final s = (v ?? '').toString().trim();
  const junk = {'', 'none', 'default string', 'to be filled by o.e.m.', 'system serial number', 'not specified'};
  return junk.contains(s.toLowerCase()) ? 'Unknown' : s;
}

int? _int(Object? v) {
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}');
}

/// Collapses the runs of spaces WMI pads names with.
String _squash(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

String _tidyBrand(String m) {
  final s = _squash(m);
  if (s == s.toUpperCase() && s.length > 4) {
    // "LENOVO" -> "Lenovo", "SAMSUNG ELECTRONICS CO., LTD." stays readable.
    return s.split(' ').map((w) => w.isEmpty ? w : w[0] + w.substring(1).toLowerCase()).join(' ');
  }
  return s;
}

/// Lenovo stores the marketing name (e.g. "ThinkPad T14 Gen 3") in
/// Win32_ComputerSystemProduct.Version and a machine code in Model.
String _friendlyModel(String manufacturer, String model, String productName) {
  if (manufacturer.toLowerCase().contains('lenovo') && productName != 'Unknown') {
    return productName;
  }
  return _squash(model);
}

String _windowsLabel(Map<String, dynamic> os) {
  final caption = _squash(_str(os['caption']).replaceFirst('Microsoft ', ''));
  final build = _str(os['build']);
  final arch = _str(os['arch']);
  return [
    caption,
    if (build != 'Unknown') 'build $build',
    if (arch != 'Unknown') arch,
  ].join(' · ');
}

String? _resolution(List<Map<String, dynamic>> gpus) {
  for (final g in gpus) {
    final w = _int(g['hRes']);
    final h = _int(g['vRes']);
    if (w != null && h != null && w > 0 && h > 0) {
      final hz = _int(g['refresh']);
      return '$w × $h${hz != null && hz > 0 ? ' @ $hz Hz' : ''}';
    }
  }
  return null;
}

/// SMBIOS memory type codes from the DMTF spec.
String? _ramType(int? code) => switch (code) {
      20 => 'DDR',
      21 => 'DDR2',
      24 => 'DDR3',
      26 => 'DDR4',
      30 => 'LPDDR4',
      34 => 'DDR5',
      35 => 'LPDDR5',
      _ => null,
    };
