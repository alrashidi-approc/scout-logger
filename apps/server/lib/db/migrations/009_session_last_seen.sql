ALTER TABLE app_sessions ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ;

UPDATE app_sessions
SET last_seen_at = COALESCE(ended_at, started_at)
WHERE last_seen_at IS NULL;

CREATE INDEX IF NOT EXISTS app_sessions_open_last_seen
  ON app_sessions (project_id, last_seen_at DESC)
  WHERE ended_at IS NULL;
