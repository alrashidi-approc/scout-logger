CREATE TABLE IF NOT EXISTS dashboard_users (
  id                   TEXT PRIMARY KEY,
  email                TEXT NOT NULL UNIQUE,
  password_hash        TEXT NOT NULL,
  display_name         TEXT,
  global_role          TEXT NOT NULL DEFAULT 'user',
  can_create_projects  BOOLEAN NOT NULL DEFAULT false,
  email_verified_at    TIMESTAMPTZ,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS project_memberships (
  user_id     TEXT NOT NULL REFERENCES dashboard_users(id) ON DELETE CASCADE,
  project_id  TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  role        TEXT NOT NULL DEFAULT 'owner',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, project_id)
);

CREATE TABLE IF NOT EXISTS email_verification_tokens (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL REFERENCES dashboard_users(id) ON DELETE CASCADE,
  token_hash  TEXT NOT NULL,
  expires_at  TIMESTAMPTZ NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_memberships_user ON project_memberships(user_id);
CREATE INDEX IF NOT EXISTS idx_memberships_project ON project_memberships(project_id);
CREATE INDEX IF NOT EXISTS idx_verify_tokens_user ON email_verification_tokens(user_id);

ALTER TABLE ingest_keys ADD COLUMN IF NOT EXISTS key_ciphertext TEXT;
