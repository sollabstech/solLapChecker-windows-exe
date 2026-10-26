import 'dart:io';

import '../models/battery_info.dart';
import 'powershell_service.dart';

/// Reads battery health from WMI (root\WMI), falling back to
/// `powercfg /batteryreport /xml` when WMI has no capacity data.
class BatteryService {
  BatteryService([this._ps = const PowerShellService()]);

  final PowerShellService _ps;

  // Each root\WMI class is optional: many laptops do not implement
  // BatteryCycleCount, so every query is wrapped and may come back empty.
  static const _script = r'''
function Try-Wmi($cls) {
  try { @(Get-CimInstance -Namespace root\WMI -ClassName $cls) } catch { @() }
}
$static = Try-Wmi 'BatteryStaticData'
$full   = Try-Wmi 'BatteryFullChargedCapacity'
$cycles = Try-Wmi 'BatteryCycleCount'
$status = Try-Wmi 'BatteryStatus'
$win32  = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)

[pscustomobject]@{
  batteries = @($static | ForEach-Object { @{ design = $_.DesignedCapacity; manufacturer = $_.ManufactureName } })
  full      = @($full   | ForEach-Object { @{ full = $_.FullChargedCapacity } })
  cycles    = @($cycles | ForEach-Object { @{ count = $_.CycleCount } })
  status    = @($status | ForEach-Object { @{ charging = $_.Charging; discharging = $_.Discharging; powerOnline = $_.PowerOnline } })
  win32     = @($win32  | ForEach-Object { @{ percent = $_.EstimatedChargeRemaining; status = $_.BatteryStatus; chemistry = $_.Chemistry } })
} | ConvertTo-Json -Depth 6 -Compress
''';

  Future<BatteryInfo> read() async {
    final json = await _ps.runJson(_script);
    var info = json is Map<String, dynamic>
        ? BatteryInfo.fromWmiJson(json)
        : const BatteryInfo.none();

    final needsFallback =
        info.designMWh == null || info.fullChargeMWh == null || info.cycleCount == null;
    if (needsFallback) {
      final report = await _powercfgReport();
      if (report != null) info = info.fillFrom(report);
    }
    return info;
  }

  /// Generates the battery report XML in the temp folder and parses it.
  /// Returns null if powercfg is unavailable or fails.
  Future<BatteryInfo?> _powercfgReport() async {
    if (!Platform.isWindows) return null;
    final file = File('${Directory.systemTemp.path}\\sollapchecker-battery.xml');
    try {
      final result = await Process.run(
        'powercfg',
        ['/batteryreport', '/xml', '/output', file.path],
      ).timeout(const Duration(seconds: 30));
      if (result.exitCode != 0 || !await file.exists()) return null;
      return BatteryInfo.fromPowercfgXml(await file.readAsString());
    } catch (_) {
      return null;
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }
}
