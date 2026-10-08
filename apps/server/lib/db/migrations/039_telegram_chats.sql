CREATE TABLE IF NOT EXISTS telegram_chats (
  chat_id     TEXT PRIMARY KEY,
  project_id  TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS telegram_chats_project
  ON telegram_chats (project_id);
