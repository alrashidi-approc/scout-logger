import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'country_centroids.dart';

String geoSourceLabel(String? source) => switch (source) {
      'profile' || 'mostly_profile' => 'Profile',
      'ip' || 'mostly_ip' => 'IP',
      'locale' || 'mostly_locale' => 'Locale',
      'mixed' => 'Mixed',
      _ => 'Unknown',
    };

String geoSourceDetail(Map<String, dynamic> row) {
  final ip = row['ipEvents'] as int? ?? 0;
  final profile = row['profileEvents'] as int? ?? 0;
  final locale = row['localeEvents'] as int? ?? 0;
  if (ip == 0 && profile == 0 && locale == 0) return 'No source metadata on events';
  return '$ip IP · $profile profile · $locale locale events';
}

(Color, Color) geoSourceColors(String? source) => switch (source) {
      'profile' || 'mostly_profile' => (AppTheme.success, AppTheme.success),
      'ip' || 'mostly_ip' => (AppTheme.warning, AppTheme.warning),
      'locale' || 'mostly_locale' => (AppTheme.info, AppTheme.info),
      'mixed' => (AppTheme.accentPurple, AppTheme.accentPurple),
      _ => (AppTheme.muted, AppTheme.muted),
    };

String eventGeoSourceLabel(String? source) => switch (source) {
      'profile' => 'user profile',
      'ip' => 'connection IP',
      'local_ip' => 'local network',
      'locale' || 'device_locale' => 'device locale',
      _ => 'unknown',
    };

String locationFactLabel({
  required String? connectionCode,
  required String? localeCode,
  String? city,
}) {
  final connection = connectionCode != null && connectionCode != 'LO' && connectionCode != '??'
      ? countryLabel(connectionCode)
      : null;
  final locale = localeCode != null ? countryLabel(localeCode) : null;
  if (connection == null && locale == null) return '—';
  final place = city != null && city != '—' ? '$city, ${connection ?? locale}' : (connection ?? locale!);
  if (connection != null && locale != null && connectionCode != localeCode) {
    return '$place · locale $locale';
  }
  return place;
}

class GeoSourceChip extends StatelessWidget {
  const GeoSourceChip({super.key, required this.source, this.compact = false});

  final String? source;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (fg, _) = geoSourceColors(source);
    final label = geoSourceLabel(source);
    return Tooltip(
      message: 'Connection country from client IP lookup or server IP; locale from device settings.',
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 3 : 4),
        decoration: BoxDecoration(
          color: fg.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: fg.withValues(alpha: 0.25)),
        ),
        child: Text(label, style: TextStyle(color: fg, fontSize: compact ? 10 : 11, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
