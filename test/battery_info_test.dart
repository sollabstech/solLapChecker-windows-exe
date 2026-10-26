import 'package:flutter_test/flutter_test.dart';
import 'package:sollapchecker/core/models/battery_info.dart';
import 'package:sollapchecker/core/models/test_status.dart';

void main() {
  group('grading', () {
    test('boundaries: >=80 Good, 60-79 Fair, <60 Replace', () {
      expect(BatteryGrade.forHealth(100), BatteryGrade.good);
      expect(BatteryGrade.forHealth(80), BatteryGrade.good);
      expect(BatteryGrade.forHealth(79), BatteryGrade.fair);
      expect(BatteryGrade.forHealth(60), BatteryGrade.fair);
      expect(BatteryGrade.forHealth(59), BatteryGrade.replace);
      expect(BatteryGrade.forHealth(0), BatteryGrade.replace);
    });

    test('health is full / design, rounded and capped at 100', () {
      expect(const BatteryInfo(present: true, designMWh: 50000, fullChargeMWh: 42500).healthPercent, 85);
      expect(const BatteryInfo(present: true, designMWh: 50000, fullChargeMWh: 39800).healthPercent, 80);
      expect(const BatteryInfo(present: true, designMWh: 50000, fullChargeMWh: 39700).healthPercent, 79);
      expect(const BatteryInfo(present: true, designMWh: 40000, fullChargeMWh: 41000).healthPercent, 100);
    });

    test('status mapping', () {
      BatteryInfo b(int full) => BatteryInfo(present: true, designMWh: 100, fullChargeMWh: full);
      expect(b(90).testStatus, TestStatus.pass);
      expect(b(70).testStatus, TestStatus.warning);
      expect(b(40).testStatus, TestStatus.fail);
      expect(const BatteryInfo(present: true).testStatus, TestStatus.warning); // capacities unknown
      expect(const BatteryInfo.none().testStatus, TestStatus.warning);
    });
  });

  group('WMI parsing', () {
    test('full data, PowerShell single-object quirk included', () {
      final info = BatteryInfo.fromWmiJson({
        'batteries': {'design': 57000, 'manufacturer': 'SMP '},
        'full': {'full': 51300},
        'cycles': {'count': 214},
        'status': {'charging': false, 'discharging': true, 'powerOnline': false},
        'win32': {'percent': 76, 'status': 1, 'chemistry': 6},
      });

      expect(info.present, isTrue);
      expect(info.designMWh, 57000);
      expect(info.fullChargeMWh, 51300);
      expect(info.healthPercent, 90);
      expect(info.cycleCount, 214);
      expect(info.chargePercent, 76);
      expect(info.chargeState, ChargeState.discharging);
      expect(info.manufacturer, 'SMP');
      expect(info.chemistry, 'Lithium-ion');
    });

    test('unsupported cycle counter (0) is reported as unavailable', () {
      final info = BatteryInfo.fromWmiJson({
        'batteries': [
          {'design': 40000}
        ],
        'full': [
          {'full': 30000}
        ],
        'cycles': [
          {'count': 0}
        ],
      });
      expect(info.cycleCount, isNull);
      expect(info.healthPercent, 75);
    });

    test('nothing reported means no battery', () {
      final info = BatteryInfo.fromWmiJson({'batteries': [], 'full': [], 'cycles': [], 'status': [], 'win32': []});
      expect(info.present, isFalse);
    });

    test('Win32_Battery alone proves a battery exists even without capacities', () {
      final info = BatteryInfo.fromWmiJson({
        'win32': [
          {'percent': 100, 'status': 3}
        ],
      });
      expect(info.present, isTrue);
      expect(info.healthPercent, isNull);
      expect(info.chargeState, ChargeState.full);
    });
  });

  group('powercfg fallback', () {
    const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<BatteryReport xmlns="http://schemas.microsoft.com/battery/2012">
  <ReportInformation><ReportVersion>1.1</ReportVersion></ReportInformation>
  <Batteries>
    <Battery>
      <Id>DELL 4N2Z2R6</Id>
      <Manufacturer>SMP</Manufacturer>
      <SerialNumber>1234</SerialNumber>
      <Chemistry>LION</Chemistry>
      <DesignCapacity>51000</DesignCapacity>
      <FullChargeCapacity>38250</FullChargeCapacity>
      <CycleCount>388</CycleCount>
    </Battery>
  </Batteries>
</BatteryReport>''';

    test('parses capacities and cycle count', () {
      final info = BatteryInfo.fromPowercfgXml(xml);
      expect(info.designMWh, 51000);
      expect(info.fullChargeMWh, 38250);
      expect(info.healthPercent, 75);
      expect(info.cycleCount, 388);
      expect(info.manufacturer, 'SMP');
      expect(info.chemistry, 'LION');
      expect(info.source, BatterySource.powercfg);
    });

    test('a report with no batteries means none', () {
      expect(
        BatteryInfo.fromPowercfgXml('<BatteryReport><Batteries/></BatteryReport>').present,
        isFalse,
      );
    });

    test('fillFrom keeps WMI values and fills only the gaps', () {
      const wmi = BatteryInfo(present: true, designMWh: 50000, chargePercent: 80);
      final merged = wmi.fillFrom(BatteryInfo.fromPowercfgXml(xml));
      expect(merged.designMWh, 50000); // WMI wins
      expect(merged.fullChargeMWh, 38250); // gap filled
      expect(merged.cycleCount, 388);
      expect(merged.chargePercent, 80);
    });
  });
}
