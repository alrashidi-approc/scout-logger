ALTER TABLE share_tokens ADD COLUMN IF NOT EXISTS payload JSONB;

ALTER TABLE share_tokens DROP CONSTRAINT IF EXISTS share_tokens_resource_type_check;
ALTER TABLE share_tokens ADD CONSTRAINT share_tokens_resource_type_check
  CHECK (resource_type IN ('event', 'issue', 'alert'));
