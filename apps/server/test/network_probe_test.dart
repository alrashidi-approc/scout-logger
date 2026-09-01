import 'package:scout_server/health_check/network_probe.dart';
import 'package:test/test.dart';

void main() {
  group('extractProbeUrls', () {
    test('finds const base URLs', () {
      const script = '''
const citizenBaseUrl = 'https://mobapp.epa.gov.kw/97F5DCDFB7BA46F4B197F41C3247D88C';
const eprocess = "https://mobileserver.epa.gov.kw/EPAChatbotAPIs-context-root";
''';
      final urls = extractProbeUrls(script);
      expect(urls, hasLength(2));
      expect(urls.any((u) => u.contains('mobapp.epa.gov.kw')), isTrue);
      expect(urls.any((u) => u.contains('mobileserver.epa.gov.kw')), isTrue);
    });
  });

  group('hostsToSampleUrl', () {
    test('picks one URL per host', () {
      final map = hostsToSampleUrl([
        'https://mobapp.epa.gov.kw/a/long/path',
        'https://mobapp.epa.gov.kw/short',
      ]);
      expect(map.keys, ['mobapp.epa.gov.kw']);
      expect(map.values.single, contains('/short'));
    });
  });

  group('mergeReportWithProbe', () {
    test('attaches probe to report', () {
      final merged = mergeReportWithProbe(
        {'verdict': 'degraded', 'summary': '1/2', 'checks': []},
        {'summary': '0/1 hosts reachable', 'probes': []},
      );
      expect(merged['networkProbe'], isNotNull);
      expect(merged['verdict'], 'degraded');
    });
  });
}
