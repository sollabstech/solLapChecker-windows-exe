import '../models/system_info.dart';
import 'powershell_service.dart';

/// Collects the laptop's identity and hardware summary from WMI.
class SystemInfoService {
  SystemInfoService([this._ps = const PowerShellService()]);

  final PowerShellService _ps;

  // One round trip fetches everything; PowerShell start-up dominates the cost.
  static const _script = r'''
$cs   = Get-CimInstance Win32_ComputerSystem
$prod = Get-CimInstance Win32_ComputerSystemProduct
$bios = Get-CimInstance Win32_BIOS
$cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
$os   = Get-CimInstance Win32_OperatingSystem
$biosDate = if ($bios.ReleaseDate) { $bios.ReleaseDate.ToString('yyyy-MM-dd') } else { '' }

[pscustomobject]@{
  computer = @{ manufacturer = $cs.Manufacturer; model = $cs.Model; totalMemory = [int64]$cs.TotalPhysicalMemory }
  product  = @{ version = $prod.Version }
  bios     = @{ version = $bios.SMBIOSBIOSVersion; serial = $bios.SerialNumber; releaseDate = $biosDate }
  cpu      = @{ name = $cpu.Name; cores = $cpu.NumberOfCores; threads = $cpu.NumberOfLogicalProcessors; maxMhz = $cpu.MaxClockSpeed }
  gpus     = @(Get-CimInstance Win32_VideoController | ForEach-Object {
               @{ name = $_.Name; driver = $_.DriverVersion; hRes = $_.CurrentHorizontalResolution
                  vRes = $_.CurrentVerticalResolution; refresh = $_.CurrentRefreshRate } })
  ram      = @(Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
               @{ capacity = [int64]$_.Capacity; speed = $_.Speed; smbiosType = $_.SMBIOSMemoryType } })
  disks    = @(Get-CimInstance Win32_DiskDrive | Where-Object { $_.InterfaceType -ne 'USB' } | ForEach-Object {
               @{ model = $_.Model; size = [int64]$_.Size } })
  os       = @{ caption = $os.Caption; build = $os.BuildNumber; arch = $os.OSArchitecture }
} | ConvertTo-Json -Depth 6 -Compress
''';

  Future<SystemInfo> load() async {
    final json = await _ps.runJson(_script);
    if (json is! Map<String, dynamic>) {
      throw PowerShellException('Unexpected system information response.');
    }
    return SystemInfo.fromJson(json);
  }
}
