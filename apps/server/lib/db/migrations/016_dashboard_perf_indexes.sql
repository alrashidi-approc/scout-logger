-- Dashboard query performance: partial indexes aligned with migration 014 outcome columns.

CREATE INDEX IF NOT EXISTS events_project_time_nohb
  ON events (project_id, occurred_at DESC)
  WHERE NOT is_heartbeat;

CREATE INDEX IF NOT EXISTS events_project_install_time
  ON events (project_id, install_id, occurred_at DESC)
  WHERE install_id IS NOT NULL AND NOT is_heartbeat;

CREATE INDEX IF NOT EXISTS events_project_user_time_nohb
  ON events (project_id, user_id, occurred_at DESC)
  WHERE user_id IS NOT NULL AND NOT is_heartbeat;

CREATE INDEX IF NOT EXISTS events_project_success
  ON events (project_id, occurred_at DESC)
  WHERE is_success;
