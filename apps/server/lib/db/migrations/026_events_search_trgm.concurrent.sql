-- Expression must stay identical to sqlEventSearchText() in lib/util/event_filters.dart.
CREATE INDEX CONCURRENTLY IF NOT EXISTS events_search_trgm ON events USING gin ((
  COALESCE(message, '') || E'\x1f' ||
  COALESCE(user_id, '') || E'\x1f' ||
  COALESCE(session_id, '') || E'\x1f' ||
  COALESCE(install_id, '') || E'\x1f' ||
  COALESCE(payload->'network'->>'url', '') || E'\x1f' ||
  COALESCE(payload->'network'->>'traceId', '') || E'\x1f' ||
  COALESCE(COALESCE(NULLIF(payload->'device'->>'deviceName', ''), NULLIF(payload->'device'->>'deviceModel', ''), NULLIF(payload->'device'->>'model', '')), '') || E'\x1f' ||
  COALESCE(payload->'user'->>'email', '') || E'\x1f' ||
  COALESCE(payload->'user'->>'name', '') || E'\x1f' ||
  COALESCE(left(payload->>'stack', 2000), '') || E'\x1f' ||
  COALESCE(left(payload->>'stackTrace', 2000), '')
) gin_trgm_ops);
