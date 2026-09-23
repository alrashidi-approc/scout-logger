-- Keep is_error in sync with sqlIsErrorEvent (exclude expected-network / non-operational).
ALTER TABLE events DROP COLUMN IF EXISTS is_error;

ALTER TABLE events ADD COLUMN is_error boolean
  GENERATED ALWAYS AS (
    type IN ('error', 'crash')
    OR (
      type = 'network'
      AND LOWER(COALESCE(NULLIF(payload->>'level', ''), 'error')) NOT IN ('info', 'success')
      AND COALESCE(NULLIF(payload->'network'->'readable'->>'operationalError', ''), 'true') <> 'false'
      AND COALESCE(NULLIF(payload->'network'->'readable'->>'faultKind', ''), '') <> 'expected'
      AND (
        NULLIF(payload->'network'->>'error', '') IS NOT NULL
        OR NULLIF(payload->'network'->>'statusCode', '') IS NULL
        OR NOT ((payload->'network'->>'statusCode') ~ '^[0-9]{1,9}$' AND (payload->'network'->>'statusCode')::int < 400)
      )
    )
  ) STORED;

CREATE INDEX IF NOT EXISTS events_project_error ON events (project_id, occurred_at DESC) WHERE is_error;
