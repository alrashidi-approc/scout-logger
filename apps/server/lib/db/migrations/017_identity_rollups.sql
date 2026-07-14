-- Phase B: identity rollups for fast Users / Devices / unique-user KPIs.
-- daily_stats already powers event/error/crash sums by day+country.

CREATE TABLE IF NOT EXISTS user_stats (
  project_id    TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  user_id       TEXT NOT NULL,
  first_seen_at TIMESTAMPTZ NOT NULL,
  last_seen_at  TIMESTAMPTZ NOT NULL,
  email         TEXT,
  display_name  TEXT,
  phone         TEXT,
  username      TEXT,
  platform      TEXT,
  app_version   TEXT,
  environment   TEXT,
  release       TEXT,
  country       TEXT,
  device_name   TEXT,
  locale        TEXT,
  last_route    TEXT,
  install_id    TEXT,
  PRIMARY KEY (project_id, user_id)
);

CREATE INDEX IF NOT EXISTS user_stats_project_last
  ON user_stats (project_id, last_seen_at DESC);

CREATE TABLE IF NOT EXISTS user_daily_stats (
  project_id   TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  user_id      TEXT NOT NULL,
  date         DATE NOT NULL,
  event_count  INT NOT NULL DEFAULT 0,
  error_count  INT NOT NULL DEFAULT 0,
  crash_count  INT NOT NULL DEFAULT 0,
  PRIMARY KEY (project_id, user_id, date)
);

CREATE INDEX IF NOT EXISTS user_daily_stats_project_date
  ON user_daily_stats (project_id, date);

CREATE TABLE IF NOT EXISTS device_stats (
  project_id    TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  install_id    TEXT NOT NULL,
  first_seen_at TIMESTAMPTZ NOT NULL,
  last_seen_at  TIMESTAMPTZ NOT NULL,
  device_name   TEXT,
  platform      TEXT,
  app_version   TEXT,
  environment   TEXT,
  country       TEXT,
  locale        TEXT,
  PRIMARY KEY (project_id, install_id)
);

CREATE INDEX IF NOT EXISTS device_stats_project_last
  ON device_stats (project_id, last_seen_at DESC);

CREATE TABLE IF NOT EXISTS device_daily_stats (
  project_id        TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  install_id        TEXT NOT NULL,
  date              DATE NOT NULL,
  event_count       INT NOT NULL DEFAULT 0,
  error_count       INT NOT NULL DEFAULT 0,
  crash_count       INT NOT NULL DEFAULT 0,
  guest_event_count INT NOT NULL DEFAULT 0,
  PRIMARY KEY (project_id, install_id, date)
);

CREATE INDEX IF NOT EXISTS device_daily_stats_project_date
  ON device_daily_stats (project_id, date);

CREATE TABLE IF NOT EXISTS user_device_links (
  project_id    TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  user_id       TEXT NOT NULL,
  install_id    TEXT NOT NULL,
  first_seen_at TIMESTAMPTZ NOT NULL,
  last_seen_at  TIMESTAMPTZ NOT NULL,
  event_count   INT NOT NULL DEFAULT 0,
  PRIMARY KEY (project_id, user_id, install_id)
);

CREATE INDEX IF NOT EXISTS user_device_links_device
  ON user_device_links (project_id, install_id, last_seen_at DESC);

CREATE INDEX IF NOT EXISTS user_device_links_user
  ON user_device_links (project_id, user_id, last_seen_at DESC);

-- Backfill from events (non-heartbeat). Errors use stored is_error when present.
INSERT INTO user_stats (
  project_id, user_id, first_seen_at, last_seen_at,
  email, display_name, phone, username,
  platform, app_version, environment, release, country,
  device_name, locale, last_route, install_id
)
SELECT
  e.project_id,
  e.user_id,
  MIN(e.occurred_at),
  MAX(e.occurred_at),
  MAX(NULLIF(TRIM(e.payload->'user'->>'email'), '')),
  MAX(NULLIF(TRIM(e.payload->'user'->>'name'), '')),
  MAX(NULLIF(TRIM(e.payload->'user'->>'phone'), '')),
  MAX(NULLIF(TRIM(e.payload->'user'->>'username'), '')),
  MAX(e.platform),
  MAX(e.app_version),
  MAX(e.environment),
  MAX(e.release),
  MAX(e.country),
  MAX(COALESCE(NULLIF(e.payload->'device'->>'deviceName', ''),
               NULLIF(e.payload->'device'->>'deviceModel', ''),
               NULLIF(e.payload->'device'->>'model', ''))),
  MAX(COALESCE(NULLIF(e.payload->'device'->'geo'->>'locale', ''),
               NULLIF(e.payload->'device'->>'locale', ''))),
  (ARRAY_AGG(NULLIF(e.payload->'screen'->>'currentRoute', '') ORDER BY e.occurred_at DESC)
    FILTER (WHERE NULLIF(e.payload->'screen'->>'currentRoute', '') IS NOT NULL))[1],
  (ARRAY_AGG(e.install_id ORDER BY e.occurred_at DESC)
    FILTER (WHERE e.install_id IS NOT NULL AND e.user_id <> e.install_id))[1]
FROM events e
WHERE e.user_id IS NOT NULL AND e.user_id <> ''
  AND NOT COALESCE(e.is_heartbeat, false)
  AND (
    (e.install_id IS NOT NULL AND e.user_id <> e.install_id)
    OR (e.install_id IS NULL AND e.user_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
  )
GROUP BY e.project_id, e.user_id
ON CONFLICT (project_id, user_id) DO NOTHING;

INSERT INTO user_daily_stats (project_id, user_id, date, event_count, error_count, crash_count)
SELECT
  e.project_id,
  e.user_id,
  (e.occurred_at AT TIME ZONE 'UTC')::date,
  COUNT(*)::int,
  COUNT(*) FILTER (WHERE COALESCE(e.is_error, false))::int,
  COUNT(*) FILTER (WHERE e.type = 'crash')::int
FROM events e
WHERE e.user_id IS NOT NULL AND e.user_id <> ''
  AND NOT COALESCE(e.is_heartbeat, false)
  AND (
    (e.install_id IS NOT NULL AND e.user_id <> e.install_id)
    OR (e.install_id IS NULL AND e.user_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
  )
GROUP BY e.project_id, e.user_id, (e.occurred_at AT TIME ZONE 'UTC')::date
ON CONFLICT (project_id, user_id, date) DO NOTHING;

INSERT INTO device_stats (
  project_id, install_id, first_seen_at, last_seen_at,
  device_name, platform, app_version, environment, country, locale
)
SELECT
  e.project_id,
  e.install_id,
  MIN(e.occurred_at),
  MAX(e.occurred_at),
  MAX(COALESCE(NULLIF(e.payload->'device'->>'deviceName', ''),
               NULLIF(e.payload->'device'->>'deviceModel', ''),
               NULLIF(e.payload->'device'->>'model', ''))),
  MAX(e.platform),
  MAX(e.app_version),
  MAX(e.environment),
  MAX(e.country),
  MAX(COALESCE(NULLIF(e.payload->'device'->'geo'->>'locale', ''),
               NULLIF(e.payload->'device'->>'locale', '')))
FROM events e
WHERE e.install_id IS NOT NULL AND NOT COALESCE(e.is_heartbeat, false)
GROUP BY e.project_id, e.install_id
ON CONFLICT (project_id, install_id) DO NOTHING;

INSERT INTO device_daily_stats (project_id, install_id, date, event_count, error_count, crash_count, guest_event_count)
SELECT
  e.project_id,
  e.install_id,
  (e.occurred_at AT TIME ZONE 'UTC')::date,
  COUNT(*)::int,
  COUNT(*) FILTER (WHERE COALESCE(e.is_error, false))::int,
  COUNT(*) FILTER (WHERE e.type = 'crash')::int,
  COUNT(*) FILTER (WHERE e.user_id IS NOT NULL AND e.user_id = e.install_id)::int
FROM events e
WHERE e.install_id IS NOT NULL AND NOT COALESCE(e.is_heartbeat, false)
GROUP BY e.project_id, e.install_id, (e.occurred_at AT TIME ZONE 'UTC')::date
ON CONFLICT (project_id, install_id, date) DO NOTHING;

INSERT INTO user_device_links (project_id, user_id, install_id, first_seen_at, last_seen_at, event_count)
SELECT
  e.project_id,
  e.user_id,
  e.install_id,
  MIN(e.occurred_at),
  MAX(e.occurred_at),
  COUNT(*)::int
FROM events e
WHERE e.install_id IS NOT NULL
  AND e.user_id IS NOT NULL AND e.user_id <> ''
  AND e.user_id <> e.install_id
  AND NOT COALESCE(e.is_heartbeat, false)
GROUP BY e.project_id, e.user_id, e.install_id
ON CONFLICT (project_id, user_id, install_id) DO NOTHING;
