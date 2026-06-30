-- Precompute event outcome classification at write time so dashboard
-- aggregates read cheap booleans instead of re-parsing JSONB on every scan.
-- Expressions MUST stay in sync with event_filters.dart (sqlIsErrorEvent /
-- sqlIsSuccessEvent / sqlHideSessionHeartbeat).

ALTER TABLE events ADD COLUMN IF NOT EXISTS is_heartbeat boolean
  GENERATED ALWAYS AS (
    type = 'session' AND COALESCE(payload->>'action', '') = 'heartbeat'
  ) STORED;

ALTER TABLE events ADD COLUMN IF NOT EXISTS is_error boolean
  GENERATED ALWAYS AS (
    type IN ('error', 'crash')
    OR (
      type = 'network'
      AND LOWER(COALESCE(NULLIF(payload->>'level', ''), 'error')) NOT IN ('info', 'success')
      AND COALESCE(NULLIF(payload->'network'->'readable'->>'operationalError', ''), 'true') <> 'false'
      AND (
        NULLIF(payload->'network'->>'error', '') IS NOT NULL
        OR NULLIF(payload->'network'->>'statusCode', '') IS NULL
        OR NOT ((payload->'network'->>'statusCode') ~ '^[0-9]{1,9}$' AND (payload->'network'->>'statusCode')::int < 400)
      )
    )
  ) STORED;

ALTER TABLE events ADD COLUMN IF NOT EXISTS is_success boolean
  GENERATED ALWAYS AS (
    LOWER(COALESCE(NULLIF(payload->>'level', ''), '')) = 'success'
    OR (
      type = 'network'
      AND LOWER(COALESCE(NULLIF(payload->>'level', ''), '')) IN ('info', 'success')
    )
    OR (
      type = 'network'
      AND NULLIF(payload->'network'->>'error', '') IS NULL
      AND (payload->'network'->>'statusCode') ~ '^[0-9]{1,9}$'
      AND (payload->'network'->>'statusCode')::int < 400
    )
  ) STORED;

CREATE INDEX IF NOT EXISTS events_project_error ON events (project_id, occurred_at DESC) WHERE is_error;
