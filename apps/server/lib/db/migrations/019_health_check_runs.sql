CREATE TABLE IF NOT EXISTS health_check_runs (
  id            TEXT PRIMARY KEY,
  project_id    TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  status        TEXT NOT NULL,
  started_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  finished_at   TIMESTAMPTZ,
  exit_code     INT,
  stdout        TEXT,
  stderr        TEXT,
  report        JSONB,
  triggered_by  TEXT,
  duration_ms   INT
);

CREATE INDEX IF NOT EXISTS health_check_runs_project_time
  ON health_check_runs (project_id, started_at DESC);
