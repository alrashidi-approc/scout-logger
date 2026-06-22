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

  test('lookup marks private ip as local', () async {
    final result = await geo.lookup({}, remoteIp: '127.0.0.1');
    expect(result.country, 'LO');
    expect(result.countryName, 'Local');
  });

  test('parseIpApiBody reads country code', () {
    final result = GeoEnricher.parseIpApiBody(
      '{"status":"success","country":"Egypt","countryCode":"EG","regionName":"Cairo","city":"Cairo"}',
    );
    expect(result?.country, 'EG');
    expect(result?.countryName, 'Egypt');
  });

  test('resolveForEvent prefers IP over device locale', () {
    const ipGeo = GeoLookup(country: 'EG', countryName: 'Egypt', city: 'Cairo');
    final resolved = GeoEnricher.resolveForEvent(
      device: {'countryCode': 'US'},
      ipGeo: ipGeo,
    );
    expect(resolved.geo.country, 'EG');
    expect(resolved.source, 'ip');
    expect(resolved.localeCountry, 'US');
  });

  test('resolveForEvent prefers client geo package IP over server ingest IP', () {
    const serverIp = GeoLookup(country: 'US', countryName: 'United States');
    final resolved = GeoEnricher.resolveForEvent(
      device: {
        'locale': 'en-US',
        'languageCode': 'en',
        'countryCode': 'US',
        'country': 'EG',
        'countrySource': 'ip',
      },
      ipGeo: serverIp,
    );
    expect(resolved.geo.country, 'EG');
    expect(resolved.source, 'ip');
    expect(resolved.localeCountry, 'US');
  });

  test('resolveForEvent reads nested device.geo from geo package', () {
    const ipGeo = GeoLookup(country: 'LO', countryName: 'Local');
    final resolved = GeoEnricher.resolveForEvent(
      device: {
        'platform': 'ios',
        'geo': {
          'locale': 'en-US',
          'languageCode': 'en',
          'countryCode': 'US',
          'country': 'EG',
          'countrySource': 'ip',
        },
      },
      ipGeo: ipGeo,
    );
    expect(resolved.geo.country, 'EG');
    expect(resolved.localeCountry, 'US');
  });

  test('resolveForEvent uses SDK country when server IP is local', () {
    const ipGeo = GeoLookup(country: 'LO', countryName: 'Local');
    final resolved = GeoEnricher.resolveForEvent(
      device: {'countryCode': 'US', 'country': 'EG', 'countrySource': 'ip'},
      ipGeo: ipGeo,
    );
    expect(resolved.geo.country, 'EG');
    expect(resolved.source, 'ip');
    expect(resolved.localeCountry, 'US');
  });

  test('resolveForEvent uses locale when IP and SDK country missing', () {
    const ipGeo = GeoLookup(country: '??', countryName: 'Unknown');
    final resolved = GeoEnricher.resolveForEvent(
      device: {'countryCode': 'EG'},
      ipGeo: ipGeo,
    );
    expect(resolved.geo.country, 'EG');
    expect(resolved.source, 'locale');
  });

  test('resolveForEvent parses locale tag when countryCode missing', () {
    const ipGeo = GeoLookup(country: '??', countryName: 'Unknown');
    final resolved = GeoEnricher.resolveForEvent(
      device: {'locale': 'en-EG', 'country': 'EG', 'countrySource': 'ip'},
      ipGeo: ipGeo,
    );
    expect(resolved.localeCountry, 'EG');
  });
}
