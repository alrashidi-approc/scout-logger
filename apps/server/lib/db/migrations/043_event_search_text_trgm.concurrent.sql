-- Trigram index on the search document, not on payload.
-- Built while search_text is still null, so this does not read event JSON.
-- Ingest fills new rows; SearchTextBackfill fills older ones and the index updates with them.
CREATE INDEX CONCURRENTLY IF NOT EXISTS events_search_text_trgm
  ON events USING gin (search_text gin_trgm_ops);
