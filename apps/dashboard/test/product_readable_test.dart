import 'package:flutter_test/flutter_test.dart';
import 'package:scout_dashboard/utils/product_readable.dart';

void main() {
  group('humanizeProductKey', () {
    test('aliases and splits', () {
      expect(humanizeProductKey('sec_vpn'), 'Security VPN');
      expect(humanizeProductKey('has_hw_key'), 'Has Hardware Key');
      expect(humanizeProductKey('failure_layer'), 'Failure Layer');
      expect(humanizeProductKey('appCheckProvider'), 'App Check Provider');
    });
  });

  group('productHumanLine', () {
    test('booleans become enabled/disabled', () {
      expect(productHumanLine('sec_vpn', true), 'Security VPN is enabled');
      expect(productHumanLine('sec_vpn', false), 'Security VPN is disabled');
      expect(productHumanLine('sec_vpn', 'true'), 'Security VPN is enabled');
    });

    test('scalars get Label: value', () {
      expect(productHumanLine('attempt', 'retry'), 'Attempt: Retry');
      expect(productHumanLine('outcome', 'failed_final'), 'Outcome: Failed Final');
    });

    test('skips maps and lists', () {
      expect(productHumanLine('meta', {'a': 1}), isNull);
      expect(productHumanLine('tags', ['a']), isNull);
    });
  });

  group('productReadableFrom', () {
    test('empty map yields empty', () {
      expect(productReadableFrom({}), isEmpty);
    });

    test('builds title chips and lines', () {
      final r = productReadableFrom({
        'sec_vpn': true,
        'failure_layer': 'device_guard',
        'step': '2_device_guard',
        'outcome': 'failed_final',
        'nested': {'x': 1},
      });
      expect(r['title'], 'Device Guard · at 2 Device Guard · Failed Final');
      expect(r['lines'], contains('Security VPN is enabled'));
      expect(r['lines'], isNot(contains(predicate((e) => '$e'.contains('nested')))));
      final chips = (r['chips'] as List).cast<Map>();
      expect(chips.map((c) => c['label']), containsAll(['Failure Layer', 'Step', 'Outcome']));
    });
  });
}
