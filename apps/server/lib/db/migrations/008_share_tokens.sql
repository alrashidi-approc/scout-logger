CREATE TABLE IF NOT EXISTS share_tokens (
  id            TEXT PRIMARY KEY,
  project_id    TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  resource_type TEXT NOT NULL CHECK (resource_type IN ('event', 'issue')),
  resource_id   TEXT NOT NULL,
  token_hash    TEXT NOT NULL UNIQUE,
  expires_at    TIMESTAMPTZ NOT NULL,
  created_by    TEXT REFERENCES dashboard_users(id) ON DELETE SET NULL,
  revoked_at    TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_share_tokens_hash ON share_tokens(token_hash) WHERE revoked_at IS NULL;
