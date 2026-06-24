CREATE TABLE IF NOT EXISTS platform_settings (
  key         TEXT PRIMARY KEY,
  value       JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO platform_settings (key, value)
VALUES ('notification_channels', '{"slack": true, "whatsapp": true, "email": true}'::jsonb)
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS notification_deliveries (
  id              TEXT PRIMARY KEY,
  project_id      TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  event_id        TEXT NOT NULL,
  issue_id        TEXT,
  dedup_key       TEXT NOT NULL,
  category        TEXT NOT NULL,
  channel         TEXT NOT NULL,
  status          TEXT NOT NULL,
  error_message   TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS notification_deliveries_project_time
  ON notification_deliveries (project_id, created_at DESC);

CREATE INDEX IF NOT EXISTS notification_deliveries_dedup
  ON notification_deliveries (project_id, dedup_key, channel, created_at DESC);
