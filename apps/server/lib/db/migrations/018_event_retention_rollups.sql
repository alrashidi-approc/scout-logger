-- Type breakdown on daily rollups so charts keep counts after raw event TTL.
ALTER TABLE daily_stats ADD COLUMN IF NOT EXISTS network_total INT NOT NULL DEFAULT 0;
ALTER TABLE daily_stats ADD COLUMN IF NOT EXISTS network_success INT NOT NULL DEFAULT 0;
ALTER TABLE daily_stats ADD COLUMN IF NOT EXISTS network_error INT NOT NULL DEFAULT 0;
ALTER TABLE daily_stats ADD COLUMN IF NOT EXISTS session_total INT NOT NULL DEFAULT 0;
ALTER TABLE daily_stats ADD COLUMN IF NOT EXISTS span_total INT NOT NULL DEFAULT 0;
ALTER TABLE daily_stats ADD COLUMN IF NOT EXISTS log_total INT NOT NULL DEFAULT 0;

UPDATE daily_stats ds SET
  network_total = agg.network_total,
  network_success = agg.network_success,
  network_error = agg.network_error,
  session_total = agg.session_total,
  span_total = agg.span_total,
  log_total = agg.log_total
FROM (
  SELECT
    project_id,
    (occurred_at AT TIME ZONE 'UTC')::date AS date,
    COALESCE(country, '') AS country,
    COUNT(*) FILTER (WHERE type = 'network')::int AS network_total,
    COUNT(*) FILTER (WHERE type = 'network' AND is_success)::int AS network_success,
    COUNT(*) FILTER (WHERE type = 'network' AND is_error)::int AS network_error,
    COUNT(*) FILTER (WHERE type = 'session' AND NOT is_heartbeat)::int AS session_total,
    COUNT(*) FILTER (WHERE type = 'span')::int AS span_total,
    COUNT(*) FILTER (WHERE type = 'log')::int AS log_total
  FROM events
  GROUP BY project_id, (occurred_at AT TIME ZONE 'UTC')::date, COALESCE(country, '')
) agg
WHERE ds.project_id = agg.project_id
  AND ds.date = agg.date
  AND ds.country = agg.country;
