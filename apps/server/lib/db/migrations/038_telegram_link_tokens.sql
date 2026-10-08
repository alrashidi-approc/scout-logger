CREATE TABLE IF NOT EXISTS telegram_link_tokens (
  token_hash  TEXT PRIMARY KEY,
  project_id  TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  expires_at  TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS telegram_link_tokens_project
  ON telegram_link_tokens (project_id);
