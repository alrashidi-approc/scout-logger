CREATE TABLE IF NOT EXISTS dashboard_logs (
  id           TEXT PRIMARY KEY,
  project_id   TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  user_id      TEXT REFERENCES dashboard_users(id) ON DELETE SET NULL,
  level        TEXT NOT NULL DEFAULT 'error',
  message      TEXT NOT NULL,
  route        TEXT,
  context      JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS dashboard_logs_project_time ON dashboard_logs (project_id, created_at DESC);
CREATE INDEX IF NOT EXISTS dashboard_logs_project_level ON dashboard_logs (project_id, level, created_at DESC);
