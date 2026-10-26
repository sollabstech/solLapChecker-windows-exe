import 'package:flutter_test/flutter_test.dart';
import 'package:sollapchecker/core/models/drive_health.dart';
import 'package:sollapchecker/core/models/test_status.dart';

/// Trimmed `smartctl -a -j` output for an NVMe drive.
Map<String, dynamic> nvme({
  int used = 3,
  int mediaErrors = 0,
  int spare = 100,
  int criticalWarning = 0,
  int temp = 38,
  bool passed = true,
}) =>
    {
      'device': {'name': '/dev/nvme0', 'type': 'nvme', 'protocol': 'NVMe'},
      'model_name': 'WDC PC SN810 SDCPNRY-512G-1006',
      'serial_number': '2146A5800123',
      'firmware_version': '61610000',
      'user_capacity': {'blocks': 1000215216, 'bytes': 512110190592},
      'logical_block_size': 512,
      'smart_status': {'passed': passed},
      'nvme_smart_health_information_log': {
        'critical_warning': criticalWarning,
        'temperature': temp,
        'available_spare': spare,
        'available_spare_threshold': 10,
        'percentage_used': used,
        'data_units_written': 24000000,
        'power_cycles': 312,
        'power_on_hours': 1450,
        'unsafe_shutdowns': 12,
        'media_errors': mediaErrors,
      },
      'temperature': {'current': temp},
      'power_cycle_count': 312,
      'power_on_time': {'hours': 1450},
    };

Map<String, dynamic> attr(int id, String name, int value, int raw) => {
      'id': id,
      'name': name,
      'value': value,
      'worst': value,
      'thresh': 0,
      'raw': {'value': raw, 'string': '$raw'},
    };

/// Trimmed `smartctl -a -j` output for a Samsung SATA SSD.
Map<String, dynamic> sata({int wearRemaining = 96, int reallocated = 0, int pending = 0}) => {
      'device': {'name': '/dev/sda', 'type': 'sat', 'protocol': 'ATA'},
      'model_name': 'Samsung SSD 860 EVO 500GB',
      'serial_number': 'S3Z2NB0K',
      'user_capacity': {'blocks': 976773168, 'bytes': 500107862016},
      'logical_block_size': 512,
      'rotation_rate': 0,
      'smart_status': {'passed': true},
      'ata_smart_attributes': {
        'table': [
          attr(5, 'Reallocated_Sector_Ct', 100, reallocated),
          attr(9, 'Power_On_Hours', 95, 9000),
          attr(12, 'Power_Cycle_Count', 99, 500),
          attr(177, 'Wear_Leveling_Count', wearRemaining, 12),
          attr(187, 'Reported_Uncorrect', 100, 0),
          attr(195, 'ECC_Error_Rate', 200, 0),
          attr(197, 'Current_Pending_Sector', 100, pending),
          attr(241, 'Total_LBAs_Written', 99, 20000000000),
          attr(174, 'Unexpect_Power_Loss_Ct', 99, 7),
        ],
      },
      'power_on_time': {'hours': 9000},
      'power_cycle_count': 500,
      'temperature': {'current': 34},
    };

Map<String, dynamic> hdd({bool passed = true, int reallocated = 0, int pending = 0}) => {
      'device': {'name': '/dev/sdb', 'type': 'sat', 'protocol': 'ATA'},
      'model_name': 'ST1000LM035-1RK172',
      'user_capacity': {'bytes': 1000204886016},
      'rotation_rate': 5400,
      'smart_status': {'passed': passed},
      'ata_smart_attributes': {
        'table': [
          attr(5, 'Reallocated_Sector_Ct', 100, reallocated),
          attr(197, 'Current_Pending_Sector', 100, pending),
        ],
      },
      'power_on_time': {'hours': 30000},
      'temperature': {'current': 41},
    };

void main() {
  group('NVMe', () {
    test('parses a healthy drive', () {
      final d = DriveHealth.fromSmartctlJson(nvme())!;

      expect(d.type, DriveType.nvme);
      expect(d.model, 'WDC PC SN810 SDCPNRY-512G-1006');
      expect(d.capacityBytes, 512110190592);
      expect(d.percentUsed, 3);
      expect(d.healthPercent, 97);
      expect(d.bytesWritten, 24000000 * 512000); // 12.288 TB
      expect(d.powerOnHours, 1450);
      expect(d.powerCycles, 312);
      expect(d.temperatureC, 38);
      expect(d.unsafeShutdowns, 12);
      expect(d.mediaErrors, 0);
      expect(d.reallocatedSectors, isNull);
      expect(d.verdict, DriveVerdict.good);
      expect(d.issues, isEmpty);
    });

    test('verdict thresholds', () {
      expect(DriveHealth.fromSmartctlJson(nvme(used: 69))!.verdict, DriveVerdict.good);
      expect(DriveHealth.fromSmartctlJson(nvme(used: 70))!.verdict, DriveVerdict.caution);
      expect(DriveHealth.fromSmartctlJson(nvme(used: 89))!.verdict, DriveVerdict.caution);
      expect(DriveHealth.fromSmartctlJson(nvme(used: 90))!.verdict, DriveVerdict.bad);
      expect(DriveHealth.fromSmartctlJson(nvme(mediaErrors: 2))!.verdict, DriveVerdict.caution);
      expect(DriveHealth.fromSmartctlJson(nvme(mediaErrors: 50))!.verdict, DriveVerdict.bad);
      expect(DriveHealth.fromSmartctlJson(nvme(spare: 40))!.verdict, DriveVerdict.caution);
      expect(DriveHealth.fromSmartctlJson(nvme(spare: 5))!.verdict, DriveVerdict.bad); // below threshold 10
      expect(DriveHealth.fromSmartctlJson(nvme(criticalWarning: 4))!.verdict, DriveVerdict.bad);
      expect(DriveHealth.fromSmartctlJson(nvme(temp: 72))!.verdict, DriveVerdict.caution);
      expect(DriveHealth.fromSmartctlJson(nvme(passed: false))!.verdict, DriveVerdict.bad);
    });
  });

  group('SATA SSD', () {
    test('derives wear, writes and unsafe shutdowns from vendor attributes', () {
      final d = DriveHealth.fromSmartctlJson(sata())!;

      expect(d.type, DriveType.sataSsd);
      expect(d.healthPercent, 96);
      expect(d.percentUsed, 4);
      expect(d.bytesWritten, 20000000000 * 512); // 10.24 TB
      expect(d.powerOnHours, 9000);
      expect(d.powerCycles, 500);
      expect(d.unsafeShutdowns, 7);
      expect(d.reallocatedSectors, 0);
      expect(d.verdict, DriveVerdict.good);
    });

    test('reallocated and pending sectors lower the verdict', () {
      expect(DriveHealth.fromSmartctlJson(sata(reallocated: 3))!.verdict, DriveVerdict.caution);
      expect(DriveHealth.fromSmartctlJson(sata(reallocated: 100))!.verdict, DriveVerdict.bad);
      expect(DriveHealth.fromSmartctlJson(sata(pending: 1))!.verdict, DriveVerdict.caution);
      expect(DriveHealth.fromSmartctlJson(sata(wearRemaining: 25))!.verdict, DriveVerdict.caution);
      expect(DriveHealth.fromSmartctlJson(sata(wearRemaining: 8))!.verdict, DriveVerdict.bad);
    });
  });

  group('HDD', () {
    test('is detected by rotation rate and has no wear figure', () {
      final d = DriveHealth.fromSmartctlJson(hdd())!;
      expect(d.type, DriveType.hdd);
      expect(d.healthPercent, isNull);
      expect(d.unsafeShutdowns, isNull);
      expect(d.verdict, DriveVerdict.good);
    });

    test('failing SMART status is Bad', () {
      final d = DriveHealth.fromSmartctlJson(hdd(passed: false, pending: 8))!;
      expect(d.verdict, DriveVerdict.bad);
      expect(d.issues.map((i) => i.severity), contains(DriveVerdict.bad));
      expect(d.issues.any((i) => i.message.contains('failing')), isTrue);
    });
  });

  test('a document with no model is not a drive', () {
    expect(DriveHealth.fromSmartctlJson({'smartctl': {'exit_status': 2}}), isNull);
  });

  test('overall storage status is the worst drive; no drives is a warning', () {
    final good = DriveHealth.fromSmartctlJson(nvme())!;
    final caution = DriveHealth.fromSmartctlJson(nvme(used: 75))!;
    final bad = DriveHealth.fromSmartctlJson(hdd(passed: false))!;

    expect(statusForDrives([good]), TestStatus.pass);
    expect(statusForDrives([good, caution]), TestStatus.warning);
    expect(statusForDrives([good, caution, bad]), TestStatus.fail);
    expect(statusForDrives([]), TestStatus.warning);
  });
}
