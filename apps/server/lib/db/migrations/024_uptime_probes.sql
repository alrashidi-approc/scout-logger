-- Light uptime probe history (10m cron) for outage investigation + share.
CREATE TABLE IF NOT EXISTS uptime_probes (
  id            TEXT PRIMARY KEY,
  project_id    TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  url           TEXT NOT NULL,
  status        TEXT NOT NULL,
  checked_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  latency_ms    INT,
  detail        TEXT
);

CREATE INDEX IF NOT EXISTS uptime_probes_project_time
  ON uptime_probes (project_id, checked_at DESC);

CREATE INDEX IF NOT EXISTS uptime_probes_project_url_time
  ON uptime_probes (project_id, url, checked_at DESC);

ALTER TABLE share_tokens DROP CONSTRAINT IF EXISTS share_tokens_resource_type_check;
ALTER TABLE share_tokens ADD CONSTRAINT share_tokens_resource_type_check
  CHECK (resource_type IN ('event', 'issue', 'alert', 'report', 'health_check', 'waf', 'uptime'));
