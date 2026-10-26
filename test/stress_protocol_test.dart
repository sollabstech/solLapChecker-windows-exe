import 'package:flutter_test/flutter_test.dart';
import 'package:sollapchecker/core/models/stress.dart';
import 'package:sollapchecker/core/models/test_status.dart';

void main() {
  group('parseHelperLine', () {
    test('decodes each event type', () {
      final start = parseHelperLine(
          '{"test":"cpu","durationSec":60,"limitC":95,"device":"Intel Core i7","type":"start"}');
      expect(start, isA<StressStarted>());
      expect((start as StressStarted).durationSec, 60);
      expect(start.device, 'Intel Core i7');
      expect(start.tempSource, isNull);

      final sample = parseHelperLine(
          '{"t":3,"tempC":71.5,"clockMhz":3890.2,"loadPct":100,"cpuTempC":71.5,"type":"sample"}');
      expect(sample, isA<StressSampled>());
      final s = (sample as StressSampled).sample;
      expect(s.t, 3);
      expect(s.tempC, 71.5);
      expect(s.powerW, isNull); // omitted fields are null
      expect(s.gpuTempC, isNull);

      expect(parseHelperLine('{"message":"hot","type":"warning"}'), isA<StressWarning>());

      final err = parseHelperLine('{"code":"no-temperature","message":"nope","type":"error"}') as StressFailed;
      expect(err.code, 'no-temperature');

      final end = parseHelperLine(
          '{"test":"cpu","reason":"completed","elapsedSec":60,"samples":60,"maxTempC":82,"avgTempC":76.3,"throttled":false,"powerLimited":true,"throttleNote":"settled","type":"end"}');
      expect(end, isA<StressEnded>());
      final sum = (end as StressEnded).summary;
      expect(sum.reason, StressEndReason.completed);
      expect(sum.maxTempC, 82);
      expect(sum.powerLimited, isTrue);
    });

    test('decodes the info line with GPUs', () {
      final e = parseHelperLine('{"version":"1.0.0","admin":true,"pawnIo":false,"cpuName":"Intel Core i7",'
          '"cpuTempAvailable":false,"gpus":[{"index":0,"name":"Intel UHD","kind":"integrated","dedicatedMb":128,'
          '"hasTempSensor":true,"hasOwnTempSensor":false},{"index":1,"name":"NVIDIA RTX","kind":"dedicated",'
          '"dedicatedMb":6144,"hasTempSensor":true,"hasOwnTempSensor":true}],"type":"info"}') as HelperInfoEvent;
      expect(e.info.pawnIo, isFalse);
      expect(e.info.gpus, hasLength(2));
      expect(e.info.gpus.first.integrated, isTrue);
      expect(e.info.gpus.last.kind, 'Dedicated GPU');
      expect(e.info.gpus.last.hasOwnTempSensor, isTrue);
    });

    test('ignores noise: blank lines, log text, broken JSON, unknown types', () {
      expect(parseHelperLine(''), isNull);
      expect(parseHelperLine('Initializing sensors...'), isNull);
      expect(parseHelperLine('{"type":"sample","t":'), isNull);
      expect(parseHelperLine('{"type":"mystery"}'), isNull);
      expect(parseHelperLine('[1,2,3]'), isNull);
    });
  });

  group('StressSummary.status', () {
    StressSummary s(StressEndReason r, {double? max, bool throttled = false, bool powerLimited = false}) =>
        StressSummary(test: 'cpu', reason: r, maxTempC: max, throttled: throttled, powerLimited: powerLimited);

    test('completed and cool is a pass', () {
      expect(s(StressEndReason.completed, max: 78).status, TestStatus.pass);
    });

    test('a power limit alone is still a pass', () {
      expect(s(StressEndReason.completed, max: 80, powerLimited: true).status, TestStatus.pass);
    });

    test('thermal throttling or a 90 °C peak is a warning', () {
      expect(s(StressEndReason.completed, max: 85, throttled: true).status, TestStatus.warning);
      expect(s(StressEndReason.completed, max: 90).status, TestStatus.warning);
      expect(s(StressEndReason.completed, max: 89.9).status, TestStatus.pass);
    });

    test('hitting the safety limit fails; stopped or errored runs have no verdict', () {
      expect(s(StressEndReason.safety, max: 95).status, TestStatus.fail);
      expect(s(StressEndReason.stopped, max: 60).status, TestStatus.notTested);
      expect(s(StressEndReason.error).status, TestStatus.notTested);
    });
  });

  test('result wording', () {
    expect(
      describeStressSummary(const StressSummary(test: 'cpu', reason: StressEndReason.safety, message: 'Reached 96 °C (limit 95 °C).')),
      contains('Reached 96'),
    );
    expect(
      describeStressSummary(const StressSummary(
          test: 'cpu', reason: StressEndReason.completed, maxTempC: 92, throttled: true, throttleNote: 'Clock dropped.')),
      'Clock dropped.',
    );
    expect(
      describeStressSummary(const StressSummary(test: 'gpu', reason: StressEndReason.completed, maxTempC: 91), part: 'graphics card'),
      contains('graphics card ran very hot'),
    );
    expect(
      describeStressSummary(const StressSummary(test: 'cpu', reason: StressEndReason.completed, maxTempC: 74)),
      'Held up under full load, peak 74 °C.',
    );
  });
}
