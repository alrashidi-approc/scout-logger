-- Nullable, no default: metadata-only on Postgres 11+. Does not rewrite event JSON.
ALTER TABLE events ADD COLUMN IF NOT EXISTS search_text TEXT;
