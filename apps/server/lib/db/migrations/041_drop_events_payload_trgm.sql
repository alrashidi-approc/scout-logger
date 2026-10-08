-- Drops the gin_trgm index on full event JSON if a deploy started building it.
-- That build sets statement_timeout to 0, so migrate prints nothing until it
-- finishes. Advanced search reads payload text under the 5s search timeout.
DROP INDEX IF EXISTS events_payload_trgm;
