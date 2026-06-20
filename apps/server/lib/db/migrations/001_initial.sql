CREATE TABLE IF NOT EXISTS schema_migrations (
  version     INT PRIMARY KEY,
  applied_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS projects (
  id           TEXT PRIMARY KEY,
  name         TEXT NOT NULL,
  slug         TEXT NOT NULL UNIQUE,
  settings     JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ingest_keys (
  id           TEXT PRIMARY KEY,
  project_id   TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  key_hash     TEXT NOT NULL,
  label        TEXT,
  revoked_at   TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ingest_keys_active_hash
  ON ingest_keys (key_hash) WHERE revoked_at IS NULL;

CREATE TABLE IF NOT EXISTS issues (
  id              TEXT PRIMARY KEY,
  project_id      TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  fingerprint     TEXT NOT NULL,
  type            TEXT NOT NULL,
  title           TEXT NOT NULL,
  status          TEXT NOT NULL DEFAULT 'open',
  first_seen_at   TIMESTAMPTZ NOT NULL,
  last_seen_at    TIMESTAMPTZ NOT NULL,
  event_count     INT NOT NULL DEFAULT 1,
  affected_users  INT NOT NULL DEFAULT 0,
  top_country     TEXT,
  UNIQUE (project_id, fingerprint)
);

CREATE INDEX IF NOT EXISTS issues_project_last ON issues (project_id, last_seen_at DESC);
CREATE INDEX IF NOT EXISTS issues_project_status ON issues (project_id, status);

CREATE TABLE IF NOT EXISTS events (
  id            TEXT PRIMARY KEY,
  project_id    TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  issue_id      TEXT REFERENCES issues(id) ON DELETE SET NULL,
  type          TEXT NOT NULL,
  occurred_at   TIMESTAMPTZ NOT NULL,
  user_id       TEXT,
  session_id    TEXT,
  release       TEXT,
  environment   TEXT,
  platform      TEXT,
  app_version   TEXT,
  country       TEXT,
  region        TEXT,
  city          TEXT,
  message       TEXT,
  payload       JSONB NOT NULL DEFAULT '{}'::jsonb,
  enrichment    JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS events_project_time ON events (project_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS events_project_type ON events (project_id, type, occurred_at DESC);
CREATE INDEX IF NOT EXISTS events_project_country ON events (project_id, country, occurred_at DESC);
CREATE INDEX IF NOT EXISTS events_issue ON events (issue_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS events_user ON events (project_id, user_id, occurred_at DESC);

CREATE TABLE IF NOT EXISTS releases (
  project_id      TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  release         TEXT NOT NULL,
  environment     TEXT NOT NULL DEFAULT 'production',
  first_seen_at   TIMESTAMPTZ NOT NULL,
  last_seen_at    TIMESTAMPTZ NOT NULL,
  event_count     INT NOT NULL DEFAULT 0,
  crash_count     INT NOT NULL DEFAULT 0,
  PRIMARY KEY (project_id, release, environment)
);

CREATE TABLE IF NOT EXISTS daily_stats (
  project_id    TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  date          DATE NOT NULL,
  country       TEXT NOT NULL DEFAULT '',
  events_total  INT NOT NULL DEFAULT 0,
  errors        INT NOT NULL DEFAULT 0,
  crashes       INT NOT NULL DEFAULT 0,
  unique_users  INT NOT NULL DEFAULT 0,
  PRIMARY KEY (project_id, date, country)
);

CREATE TABLE IF NOT EXISTS user_first_seen (
  project_id    TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  user_id       TEXT NOT NULL,
  first_seen_at TIMESTAMPTZ NOT NULL,
  first_country TEXT,
  PRIMARY KEY (project_id, user_id)
);
