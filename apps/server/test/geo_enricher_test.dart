import 'package:test/test.dart';

import 'package:scout_server/services/geo_enricher.dart';

void main() {
  final geo = GeoEnricher(enabled: true);

  test('clientIp prefers x-forwarded-for', () {
    expect(
      geo.clientIp({'x-forwarded-for': '1.2.3.4, 5.6.7.8'}, remoteIp: '9.9.9.9'),
      '1.2.3.4',
    );
  });

  test('clientIp falls back to remote address', () {
    expect(geo.clientIp({}, remoteIp: '203.0.113.10'), '203.0.113.10');
  });

  test('isPrivateIp detects local ranges', () {
    expect(GeoEnricher.isPrivateIp('127.0.0.1'), isTrue);
    expect(GeoEnricher.isPrivateIp('192.168.1.5'), isTrue);
    expect(GeoEnricher.isPrivateIp('203.0.113.10'), isFalse);
  });

  test('lookup uses Cloudflare country header', () async {
    final result = await geo.lookup({'cf-ipcountry': 'kw'});
    expect(result.country, 'KW');
    expect(result.countryName, 'Kuwait');
  });

  test('lookup marks private ip as local', () async {
    final result = await geo.lookup({}, remoteIp: '127.0.0.1');
    expect(result.country, 'LO');
    expect(result.countryName, 'Local');
  });

  test('resolveForEvent prefers device locale country', () {
    const ipGeo = GeoLookup(country: 'LO', countryName: 'Local');
    final resolved = GeoEnricher.resolveForEvent({'countryCode': 'kw'}, ipGeo);
    expect(resolved.country, 'KW');
    expect(resolved.countryName, 'Kuwait');
  });

  test('resolveForEvent falls back to ip geo', () {
    const ipGeo = GeoLookup(country: 'US', countryName: 'United States');
    expect(GeoEnricher.resolveForEvent({}, ipGeo), ipGeo);
  });
}
