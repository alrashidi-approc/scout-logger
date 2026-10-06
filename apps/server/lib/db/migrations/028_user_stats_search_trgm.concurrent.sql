-- Expression must stay identical to sqlUserStatsSearchText() in lib/util/event_filters.dart.
CREATE INDEX CONCURRENTLY IF NOT EXISTS user_stats_search_trgm ON user_stats USING gin ((
  COALESCE(user_id, '') || E'\x1f' ||
  COALESCE(email, '') || E'\x1f' ||
  COALESCE(display_name, '') || E'\x1f' ||
  COALESCE(phone, '') || E'\x1f' ||
  COALESCE(username, '') || E'\x1f' ||
  COALESCE(device_name, '') || E'\x1f' ||
  COALESCE(country, '') || E'\x1f' ||
  COALESCE(install_id, '')
) gin_trgm_ops);
