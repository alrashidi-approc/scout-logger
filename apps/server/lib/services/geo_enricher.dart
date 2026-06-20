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

class GeoEnricher {
  GeoEnricher({required this.enabled});

  final bool enabled;

  Future<GeoLookup> lookup(Map<String, String> headers, {String? remoteIp}) async {
    if (!enabled) return const GeoLookup();

    final cfCountry = headers['cf-ipcountry'];
    if (cfCountry != null && cfCountry.isNotEmpty && cfCountry != 'XX') {
      return GeoLookup(
        country: cfCountry.toUpperCase(),
        countryName: countryName(cfCountry),
      );
    }

    final ip = clientIp(headers, remoteIp: remoteIp);
    if (ip == null || isPrivateIp(ip)) {
      return const GeoLookup(country: 'LO', countryName: 'Local');
    }

    return await _resolveIp(ip) ?? GeoLookup(country: '??', countryName: 'Unknown');
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

  /// Prefer device locale country (reliable on mobile) over IP lookup.
  static GeoLookup resolveForEvent(Map<String, dynamic> device, GeoLookup ipGeo) {
    final code = device['countryCode']?.toString().trim();
    if (code == null || code.isEmpty || code.toLowerCase() == 'unknown') return ipGeo;
    final upper = code.toUpperCase();
    return GeoLookup(country: upper, countryName: countryName(upper));
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

  Future<GeoLookup?> _resolveIp(String ip) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final req = await client.getUrl(
        Uri.parse('http://ip-api.com/json/$ip?fields=status,country,countryCode,regionName,city,timezone,lat,lon'),
      );
      final res = await req.close().timeout(const Duration(seconds: 2));
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      final j = jsonDecode(body) as Map<String, dynamic>;
      if (j['status'] != 'success') return null;
      final code = j['countryCode']?.toString();
      return GeoLookup(
        country: code,
        countryName: j['country']?.toString() ?? countryName(code),
        region: j['regionName']?.toString(),
        city: j['city']?.toString(),
        timezone: j['timezone']?.toString(),
        latitude: (j['lat'] as num?)?.toDouble(),
        longitude: (j['lon'] as num?)?.toDouble(),
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
