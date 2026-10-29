import 'package:sollapchecker/app/app_modules.dart';
import 'package:sollapchecker/core/models/battery_info.dart';
import 'package:sollapchecker/core/models/drive_health.dart';
import 'package:sollapchecker/core/models/stress.dart';
import 'package:sollapchecker/core/models/system_info.dart';
import 'package:sollapchecker/core/models/test_status.dart';
import 'package:sollapchecker/core/report/report_builder.dart';

SystemInfo sampleSystemInfo() => SystemInfo.fromJson({
      'computer': {'manufacturer': 'LENOVO', 'model': '21BR0010US', 'totalMemory': 17044873216},
      'product': {'version': 'ThinkPad T14 Gen 3'},
      'bios': {'version': 'N3AET67W (1.35 )', 'serial': 'PF3ABCDE', 'releaseDate': '2023-05-12'},
      'cpu': {'name': 'Intel(R) Core(TM) i7-1260P', 'cores': 12, 'threads': 16, 'maxMhz': 2100},
      'gpus': [
        {'name': 'Intel(R) Iris(R) Xe Graphics', 'driver': '31.0.101.4502', 'hRes': 1920, 'vRes': 1080, 'refresh': 60},
        {'name': 'NVIDIA GeForce MX550', 'driver': '31.0.15.3623'},
      ],
      'ram': [
        {'capacity': 8589934592, 'speed': 4800, 'smbiosType': 34},
        {'capacity': 8589934592, 'speed': 4800, 'smbiosType': 34},
      ],
      'disks': [
        {'model': 'WDC PC SN810 SDCPNRY-512G-1006', 'size': 512110190592},
      ],
      'os': {'caption': 'Microsoft Windows 11 Pro', 'build': '22631', 'arch': '64-bit'},
    });

const sampleDrive = DriveHealth(
  device: '/dev/nvme0',
  model: 'WDC PC SN810 SDCPNRY-512G-1006',
  type: DriveType.nvme,
  capacityBytes: 512110190592,
  healthPercent: 97,
  percentUsed: 3,
  bytesWritten: 12288000000000,
  powerOnHours: 1450,
  powerCycles: 312,
  temperatureC: 38,
  unsafeShutdowns: 12,
  mediaErrors: 0,
  smartPassed: true,
);

/// Every test run and passing, on a healthy laptop.
ReportInputs sampleInputs({Map<ModuleId, TestStatus>? statuses}) => ReportInputs(
      system: sampleSystemInfo().toJson(),
      statuses: statuses ??
          {for (final m in testModules) m.id: TestStatus.pass},
      battery: const BatteryInfo(
        present: true,
        designMWh: 51000,
        fullChargeMWh: 46000,
        cycleCount: 212,
        chargePercent: 76,
        chargeState: ChargeState.discharging,
        manufacturer: 'SMP',
      ),
      drives: const [sampleDrive],
      cpu: const StressSummary(
        test: 'cpu',
        reason: StressEndReason.completed,
        device: 'Intel(R) Core(TM) i7-1260P',
        plannedSec: 300,
        elapsedSec: 300,
        maxTempC: 84,
        avgTempC: 79,
        maxClockMhz: 4400,
        minClockMhz: 3500,
        powerLimited: true,
        throttleNote: 'Clock settled from 4400 to 3500 MHz without overheating (power/boost limit).',
        maxCpuTempC: 84,
      ),
      gpus: const [
        StressSummary(
          test: 'gpu',
          reason: StressEndReason.completed,
          device: 'Intel(R) Iris(R) Xe Graphics',
          plannedSec: 60,
          elapsedSec: 60,
          maxTempC: 72,
          avgTempC: 68,
          maxCpuTempC: 72,
        ),
        StressSummary(
          test: 'gpu',
          reason: StressEndReason.completed,
          device: 'NVIDIA GeForce MX550',
          plannedSec: 60,
          elapsedSec: 60,
          maxTempC: 71,
          avgTempC: 66,
          maxClockMhz: 1700,
          minClockMhz: 1650,
          maxGpuTempC: 71,
          maxCpuTempC: 66,
        ),
      ],
      keyboard: {
        'total': 84,
        'tested': 84,
        'failed': <String>[],
        'untested': <String>[],
        'manuallyConfirmed': ['Fn'],
        'ignoredExternalPresses': 3,
      },
      touchpad: {
        'move': 'detected',
        'leftClick': 'detected',
        'rightClick': 'detected',
        'scroll': 'manualPass',
        'ignoredExternalEvents': 41,
      },
      webcam: {'camera': 'Integrated Camera', 'resolution': '1280 × 720', 'result': 'works', 'noCamera': false},
      display: {
        'colorsChecked': ['Red', 'Green', 'Blue', 'White', 'Black'],
        'result': 'no problems',
      },
    );
