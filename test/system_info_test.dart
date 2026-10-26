import 'package:flutter_test/flutter_test.dart';
import 'package:sollapchecker/core/models/system_info.dart';
import 'package:sollapchecker/core/utils/format.dart';

void main() {
  // Shaped like the JSON SystemInfoService's PowerShell script emits,
  // including PowerShell's single-element-array-becomes-object quirk.
  final sample = <String, dynamic>{
    'computer': {'manufacturer': 'LENOVO', 'model': '21BR0010US', 'totalMemory': 17044873216},
    'product': {'version': 'ThinkPad T14 Gen 3'},
    'bios': {'version': 'N3AET67W (1.35 )', 'serial': 'PF3ABCDE', 'releaseDate': '2023-05-12'},
    'cpu': {'name': 'Intel(R) Core(TM) i7-1260P   ', 'cores': 12, 'threads': 16, 'maxMhz': 2100},
    'gpus': {
      'name': 'Intel(R) Iris(R) Xe Graphics',
      'driver': '31.0.101.4502',
      'hRes': 1920,
      'vRes': 1080,
      'refresh': 60,
    },
    'ram': [
      {'capacity': 8589934592, 'speed': 4800, 'smbiosType': 34},
      {'capacity': 8589934592, 'speed': 4800, 'smbiosType': 34},
    ],
    'disks': [
      {'model': 'WDC PC SN810 SDCPNRY-512G-1006', 'size': 512110190592},
    ],
    'os': {'caption': 'Microsoft Windows 11 Pro', 'build': '22631', 'arch': '64-bit'},
  };

  test('parses a typical Lenovo laptop', () {
    final info = SystemInfo.fromJson(sample);

    expect(info.brand, 'Lenovo');
    expect(info.model, 'ThinkPad T14 Gen 3');
    expect(info.serialNumber, 'PF3ABCDE');
    expect(info.cpu.name, 'Intel(R) Core(TM) i7-1260P');
    expect(info.cpu.summary, '12 cores / 16 threads · up to 2.10 GHz');
    expect(info.gpus, hasLength(1));
    expect(info.ramSummary, '16 GB · DDR5 4800 MHz');
    expect(info.storageSummary, '512 GB');
    expect(info.windows, 'Windows 11 Pro · build 22631 · 64-bit');
    expect(info.displayResolution, '1920 × 1080 @ 60 Hz');
  });

  test('missing and placeholder values become "Unknown" instead of throwing', () {
    final info = SystemInfo.fromJson({
      'computer': {'manufacturer': 'ASUSTeK COMPUTER INC.', 'model': 'X', 'totalMemory': 0},
      'bios': {'serial': 'To Be Filled By O.E.M.'},
    });

    expect(info.serialNumber, 'Unknown');
    expect(info.ramSummary, 'Unknown');
    expect(info.drives, isEmpty);
    expect(info.displayResolution, isNull);
  });

  test('capacity formatting', () {
    expect(formatCapacity(512110190592), '512 GB');
    expect(formatCapacity(1000204886016), '1 TB');
    expect(formatCapacity(2000398934016), '2 TB');
  });
}
