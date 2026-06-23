-- Heartbeats only update app_sessions.last_seen_at. Purge stored rows and fix aggregates.
DELETE FROM events
WHERE type = 'session' AND COALESCE(payload->>'action', '') = 'heartbeat';

TRUNCATE daily_stats;

INSERT INTO daily_stats (project_id, date, country, events_total, errors, crashes, unique_users)
SELECT
  project_id,
  (occurred_at AT TIME ZONE 'UTC')::date,
  COALESCE(country, ''),
  COUNT(*)::int,
  COUNT(*) FILTER (WHERE type IN ('error', 'network'))::int,
  COUNT(*) FILTER (WHERE type = 'crash')::int,
  0
FROM events
GROUP BY project_id, (occurred_at AT TIME ZONE 'UTC')::date, COALESCE(country, '');

UPDATE releases r SET
  event_count = s.cnt,
  crash_count = s.crashes,
  first_seen_at = s.first_at,
  last_seen_at = s.last_at
FROM (
  SELECT
    project_id,
    release,
    COALESCE(environment, 'production') AS env,
    COUNT(*)::int AS cnt,
    COUNT(*) FILTER (WHERE type = 'crash')::int AS crashes,
    MIN(occurred_at) AS first_at,
    MAX(occurred_at) AS last_at
  FROM events
  WHERE release IS NOT NULL
  GROUP BY project_id, release, COALESCE(environment, 'production')
) s
WHERE r.project_id = s.project_id AND r.release = s.release AND r.environment = s.env;

UPDATE releases SET event_count = 0, crash_count = 0
WHERE NOT EXISTS (
  SELECT 1 FROM events e
  WHERE e.project_id = releases.project_id
    AND e.release = releases.release
    AND COALESCE(e.environment, 'production') = releases.environment
);
