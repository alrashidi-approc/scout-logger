ALTER TABLE issues ADD COLUMN IF NOT EXISTS assignee_user_id TEXT REFERENCES dashboard_users(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS issue_notes (
  id          TEXT PRIMARY KEY,
  project_id  TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  issue_id    TEXT NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
  author_id   TEXT REFERENCES dashboard_users(id) ON DELETE SET NULL,
  body        TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS issue_notes_issue ON issue_notes (issue_id, created_at);
