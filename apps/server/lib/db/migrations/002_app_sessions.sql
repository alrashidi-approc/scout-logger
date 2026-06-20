-- App visits: open → close (not per-screen)
CREATE TABLE IF NOT EXISTS app_sessions (
  id           TEXT PRIMARY KEY,
  project_id   TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  user_id      TEXT,
  started_at   TIMESTAMPTZ NOT NULL,
  ended_at     TIMESTAMPTZ,
  duration_ms  INT
);

CREATE INDEX IF NOT EXISTS app_sessions_project_started ON app_sessions (project_id, started_at DESC);
CREATE INDEX IF NOT EXISTS app_sessions_project_open ON app_sessions (project_id, ended_at) WHERE ended_at IS NULL;
