/// UN M49-style subregions — matches DataReportal / We Are Social map labels.
class GeoRegion {
  const GeoRegion(this.id, this.label, this.lat, this.lng);
  final String id;
  final String label;
  final double lat;
  final double lng;
}

const geoRegions = <GeoRegion>[
  GeoRegion('northern_america', 'NORTHERN AMERICA', 52, -105),
  GeoRegion('central_america', 'CENTRAL AMERICA', 14, -88),
  GeoRegion('caribbean', 'CARIBBEAN', 20, -72),
  GeoRegion('south_america', 'SOUTH AMERICA', -15, -58),
  GeoRegion('northern_europe', 'NORTHERN EUROPE', 62, 18),
  GeoRegion('western_europe', 'WESTERN EUROPE', 49, 2),
  GeoRegion('eastern_europe', 'EASTERN EUROPE', 54, 32),
  GeoRegion('southern_europe', 'SOUTHERN EUROPE', 41, 12),
  GeoRegion('northern_africa', 'NORTHERN AFRICA', 28, 8),
  GeoRegion('western_africa', 'WESTERN AFRICA', 10, -8),
  GeoRegion('middle_africa', 'MIDDLE AFRICA', 2, 22),
  GeoRegion('eastern_africa', 'EASTERN AFRICA', 4, 38),
  GeoRegion('southern_africa', 'SOUTHERN AFRICA', -26, 24),
  GeoRegion('western_asia', 'WESTERN ASIA', 32, 48),
  GeoRegion('central_asia', 'CENTRAL ASIA', 44, 64),
  GeoRegion('eastern_asia', 'EASTERN ASIA', 36, 108),
  GeoRegion('southeast_asia', 'SOUTHEASTERN ASIA', 6, 112),
  GeoRegion('southern_asia', 'SOUTHERN ASIA', 22, 78),
  GeoRegion('oceania', 'OCEANIA', -22, 140),
];

const _countryRegion = <String, String>{
  'US': 'northern_america', 'CA': 'northern_america',
  'MX': 'central_america', 'GT': 'central_america', 'CR': 'central_america', 'PA': 'central_america',
  'CU': 'caribbean', 'DO': 'caribbean', 'JM': 'caribbean', 'HT': 'caribbean', 'PR': 'caribbean',
  'BR': 'south_america', 'AR': 'south_america', 'CL': 'south_america', 'CO': 'south_america',
  'PE': 'south_america', 'VE': 'south_america', 'EC': 'south_america', 'BO': 'south_america',
  'GB': 'northern_europe', 'IE': 'northern_europe', 'SE': 'northern_europe', 'NO': 'northern_europe',
  'DK': 'northern_europe', 'FI': 'northern_europe', 'EE': 'northern_europe', 'LV': 'northern_europe', 'LT': 'northern_europe',
  'DE': 'western_europe', 'FR': 'western_europe', 'NL': 'western_europe', 'BE': 'western_europe',
  'CH': 'western_europe', 'AT': 'western_europe', 'LU': 'western_europe',
  'PL': 'eastern_europe', 'UA': 'eastern_europe', 'RU': 'eastern_europe', 'CZ': 'eastern_europe',
  'HU': 'eastern_europe', 'RO': 'eastern_europe', 'BG': 'eastern_europe', 'SK': 'eastern_europe',
  'HR': 'eastern_europe', 'RS': 'eastern_europe',
  'ES': 'southern_europe', 'IT': 'southern_europe', 'PT': 'southern_europe', 'GR': 'southern_europe',
  'TR': 'western_asia',
  'SA': 'western_asia', 'AE': 'western_asia', 'IL': 'western_asia', 'IQ': 'western_asia', 'IR': 'western_asia',
  'KW': 'western_asia', 'QA': 'western_asia', 'BH': 'western_asia', 'OM': 'western_asia', 'JO': 'western_asia', 'LB': 'western_asia',
  'EG': 'northern_africa', 'MA': 'northern_africa', 'DZ': 'northern_africa', 'TN': 'northern_africa', 'LY': 'northern_africa',
  'NG': 'western_africa', 'GH': 'western_africa', 'CI': 'western_africa', 'SN': 'western_africa',
  'KE': 'eastern_africa', 'ET': 'eastern_africa', 'TZ': 'eastern_africa', 'UG': 'eastern_africa',
  'ZA': 'southern_africa',
  'IN': 'southern_asia', 'PK': 'southern_asia', 'BD': 'southern_asia', 'LK': 'southern_asia', 'NP': 'southern_asia',
  'CN': 'eastern_asia', 'JP': 'eastern_asia', 'KR': 'eastern_asia', 'TW': 'eastern_asia', 'HK': 'eastern_asia', 'MN': 'eastern_asia',
  'SG': 'southeast_asia', 'MY': 'southeast_asia', 'ID': 'southeast_asia', 'TH': 'southeast_asia',
  'VN': 'southeast_asia', 'PH': 'southeast_asia', 'MM': 'southeast_asia', 'KH': 'southeast_asia',
  'AU': 'oceania', 'NZ': 'oceania', 'FJ': 'oceania', 'PG': 'oceania',
  'LO': 'western_europe', '??': 'western_europe',
};

String regionForCountry(String code) =>
    _countryRegion[code.toUpperCase()] ?? 'western_europe';

GeoRegion regionById(String id) =>
    geoRegions.firstWhere((r) => r.id == id, orElse: () => geoRegions.first);

List<Map<String, dynamic>> aggregateByRegion(List<Map<String, dynamic>> points) {
  final totals = <String, int>{};
  final countries = <String, List<String>>{};
  for (final p in points) {
    final code = (p['country'] as String? ?? '').toUpperCase();
    if (code.isEmpty) continue;
    final region = regionForCountry(code);
    final count = p['count'] as int? ?? 0;
    totals[region] = (totals[region] ?? 0) + count;
    countries.putIfAbsent(region, () => []).add(code);
  }
  return [
    for (final r in geoRegions)
      if ((totals[r.id] ?? 0) > 0)
        {
          'id': r.id,
          'label': r.label,
          'lat': r.lat,
          'lng': r.lng,
          'count': totals[r.id],
          'countries': countries[r.id] ?? [],
        },
  ]..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
}

String formatGeoCount(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n >= 10000000 ? 0 : 1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}K';
  return '$n';
}
