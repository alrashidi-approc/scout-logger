-- Raw event JSON. Must stay identical to `payload::text` in ScoutStore.searchLogs.
-- Separate from events_search_trgm so the events list does not index full bodies.
CREATE INDEX CONCURRENTLY IF NOT EXISTS events_payload_trgm
  ON events USING gin ((payload::text) gin_trgm_ops);
