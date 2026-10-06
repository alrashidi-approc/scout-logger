-- Expression must stay identical to sqlDeviceStatsSearchText() in lib/util/event_filters.dart.
CREATE INDEX CONCURRENTLY IF NOT EXISTS device_stats_search_trgm ON device_stats USING gin ((
  COALESCE(install_id, '') || E'\x1f' ||
  COALESCE(device_name, '') || E'\x1f' ||
  COALESCE(platform, '') || E'\x1f' ||
  COALESCE(country, '')
) gin_trgm_ops);
