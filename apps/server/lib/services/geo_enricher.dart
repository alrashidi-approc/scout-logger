import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

class GeoLookup {
  const GeoLookup({
    this.country,
    this.countryName,
    this.region,
    this.city,
    this.timezone,
    this.latitude,
    this.longitude,
  });

  final String? country;
  final String? countryName;
  final String? region;
  final String? city;
  final String? timezone;
  final double? latitude;
  final double? longitude;

  bool get hasCountry => country != null && country!.isNotEmpty && country != '??';

  bool get isUsable => hasCountry && country != 'LO';

  Map<String, dynamic> toJson() => {
        if (country != null) 'country': country,
        if (countryName != null) 'countryName': countryName,
        if (region != null) 'region': region,
        if (city != null) 'city': city,
        if (timezone != null) 'timezone': timezone,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      };

  static GeoLookup fromJson(dynamic raw) {
    if (raw is! Map) return const GeoLookup();
    final geo = Map<String, dynamic>.from(raw);
    return GeoLookup(
      country: geo['country']?.toString(),
      countryName: geo['countryName']?.toString(),
      region: geo['region']?.toString(),
      city: geo['city']?.toString(),
      timezone: geo['timezone']?.toString(),
      latitude: (geo['latitude'] as num?)?.toDouble(),
      longitude: (geo['longitude'] as num?)?.toDouble(),
    );
  }
}

class GeoResolution {
  const GeoResolution({
    required this.geo,
    required this.source,
    this.localeCountry,
    this.ipGeo,
  });

  final GeoLookup geo;
  final String source;
  final String? localeCountry;
  final GeoLookup? ipGeo;

  Map<String, dynamic> toEnrichmentJson() => {
        ...geo.toJson(),
        'source': source,
        if (localeCountry != null) 'localeCountry': localeCountry,
        if (ipGeo != null && ipGeo!.hasCountry) 'ipGeo': ipGeo!.toJson(),
      };
}

class GeoEnricher {
  GeoEnricher({required this.enabled});

  static const ipApiFields = 'status,country,countryCode,regionName,city,timezone,lat,lon';

  final bool enabled;

  Future<GeoLookup> lookup(Map<String, String> headers, {String? remoteIp}) async {
    if (!enabled) return const GeoLookup();

    final ip = clientIp(headers, remoteIp: remoteIp);
    if (ip == null || isPrivateIp(ip)) {
      return const GeoLookup(country: 'LO', countryName: 'Local');
    }

    return await resolveIp(ip) ?? const GeoLookup(country: '??', countryName: 'Unknown');
  }

  String? clientIp(Map<String, String> headers, {String? remoteIp}) {
    final forwarded = headers['x-forwarded-for'];
    if (forwarded != null && forwarded.isNotEmpty) {
      return forwarded.split(',').first.trim();
    }
    final real = headers['x-real-ip'];
    if (real != null && real.isNotEmpty) return real;
    return remoteIp;
  }

  String hashIp(String? ip) {
    if (ip == null || ip.isEmpty) return '';
    final truncated = ip.contains(':') ? ip : ip.split('.').take(3).join('.');
    return sha256.convert(utf8.encode(truncated)).toString().substring(0, 16);
  }

  static bool isPrivateIp(String ip) {
    if (ip == '127.0.0.1' || ip == '::1' || ip == 'localhost') return true;
    if (ip.startsWith('10.') || ip.startsWith('192.168.')) return true;
    if (ip.startsWith('172.')) {
      final second = int.tryParse(ip.split('.').elementAt(1));
      if (second != null && second >= 16 && second <= 31) return true;
    }
    return false;
  }

  static String? countryName(String? code) => _countryName(code ?? '');

  /// Client geo package IP → server request IP → SDK locale country → device [countryCode].
  static GeoResolution resolveForEvent({
    required Map<String, dynamic> device,
    required GeoLookup ipGeo,
  }) {
    final d = _normalizedDeviceGeo(device);
    final localeCountry = _localeCountry(d);

    final sdkCountry = _sdkCountry(d);
    if (sdkCountry != null && sdkCountry.source == 'ip') {
      return GeoResolution(
        geo: GeoLookup(country: sdkCountry.code, countryName: countryName(sdkCountry.code)),
        source: 'ip',
        localeCountry: localeCountry,
        ipGeo: ipGeo.hasCountry ? ipGeo : null,
      );
    }

    if (ipGeo.isUsable) {
      return GeoResolution(geo: ipGeo, source: 'ip', localeCountry: localeCountry);
    }

    if (sdkCountry != null) {
      return GeoResolution(
        geo: GeoLookup(country: sdkCountry.code, countryName: countryName(sdkCountry.code)),
        source: sdkCountry.source,
        localeCountry: localeCountry,
        ipGeo: ipGeo.hasCountry ? ipGeo : null,
      );
    }

    if (localeCountry != null) {
      return GeoResolution(
        geo: GeoLookup(country: localeCountry, countryName: countryName(localeCountry)),
        source: 'locale',
        localeCountry: localeCountry,
        ipGeo: ipGeo.hasCountry ? ipGeo : null,
      );
    }

    return GeoResolution(geo: ipGeo, source: 'unknown', localeCountry: localeCountry);
  }

  /// Flat [device] fields plus nested [device.geo] from the client geo package.
  static Map<String, dynamic> _normalizedDeviceGeo(Map<String, dynamic> device) {
    final nested = device['geo'];
    if (nested is Map) return {...device, ...Map<String, dynamic>.from(nested)};
    return device;
  }

  static ({String code, String source})? _sdkCountry(Map<String, dynamic> device) {
    final code = device['country']?.toString().trim();
    if (code == null || code.isEmpty || code == 'LO' || code == '??') return null;
    final upper = code.toUpperCase();
    final raw = device['countrySource']?.toString().toLowerCase();
    final source = raw == 'locale' || raw == 'device_locale' ? 'locale' : 'ip';
    return (code: upper, source: source);
  }

  static String? _localeCountry(Map<String, dynamic> device) {
    for (final key in ['localeCountry', 'countryCode']) {
      final code = device[key]?.toString().trim();
      if (code != null && code.isNotEmpty && code.toLowerCase() != 'unknown') {
        return code.toUpperCase();
      }
    }
    final locale = device['locale']?.toString();
    if (locale != null && locale.contains('-')) {
      final part = locale.split('-').last.trim();
      if (part.length == 2) return part.toUpperCase();
    }
    return null;
  }

  static String? _countryName(String code) {
    const names = {
      'KW': 'Kuwait',
      'EG': 'Egypt',
      'SA': 'Saudi Arabia',
      'AE': 'United Arab Emirates',
      'US': 'United States',
      'GB': 'United Kingdom',
      'JO': 'Jordan',
      'QA': 'Qatar',
      'BH': 'Bahrain',
      'OM': 'Oman',
      'IQ': 'Iraq',
      'LB': 'Lebanon',
      'DE': 'Germany',
      'FR': 'France',
      'LO': 'Local',
    };
    return names[code.toUpperCase()];
  }

  static Future<GeoLookup?> resolveIp(String ip) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final req = await client.getUrl(
        Uri.parse('http://ip-api.com/json/$ip?fields=$ipApiFields'),
      );
      final res = await req.close().timeout(const Duration(seconds: 2));
      if (res.statusCode != 200) return null;
      return parseIpApiBody(await res.transform(utf8.decoder).join());
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static GeoLookup? parseIpApiBody(String body) {
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      if (j['status'] != 'success') return null;
      final code = j['countryCode']?.toString();
      if (code == null || code.isEmpty) return null;
      return GeoLookup(
        country: code.toUpperCase(),
        countryName: j['country']?.toString() ?? countryName(code),
        region: j['regionName']?.toString(),
        city: j['city']?.toString(),
        timezone: j['timezone']?.toString(),
        latitude: (j['lat'] as num?)?.toDouble(),
        longitude: (j['lon'] as num?)?.toDouble(),
      );
    } catch (_) {
      return null;
    }
  }
}
