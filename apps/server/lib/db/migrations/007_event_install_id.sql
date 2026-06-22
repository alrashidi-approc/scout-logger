ALTER TABLE events ADD COLUMN IF NOT EXISTS install_id TEXT;

CREATE INDEX IF NOT EXISTS events_project_install ON events (project_id, install_id)
  WHERE install_id IS NOT NULL;

UPDATE events
SET install_id = COALESCE(
  NULLIF(payload->'device'->>'installId', ''),
  NULLIF(payload->'user'->>'installId', ''),
  NULLIF(payload->'device'->>'anonymousId', ''),
  NULLIF(payload->'user'->>'anonymousId', '')
)
WHERE install_id IS NULL;
