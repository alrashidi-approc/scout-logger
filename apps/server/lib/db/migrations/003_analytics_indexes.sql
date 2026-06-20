CREATE INDEX IF NOT EXISTS events_project_session ON events (project_id, session_id, occurred_at DESC);
