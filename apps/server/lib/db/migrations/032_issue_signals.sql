-- Triage signals written by the periodic issue-signals job (I4 priority, I5 spike, I6 noise).
ALTER TABLE issues ADD COLUMN IF NOT EXISTS priority INT NOT NULL DEFAULT 0;
ALTER TABLE issues ADD COLUMN IF NOT EXISTS priority_reasons TEXT[] NOT NULL DEFAULT '{}';
ALTER TABLE issues ADD COLUMN IF NOT EXISTS spike BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE issues ADD COLUMN IF NOT EXISTS spike_at TIMESTAMPTZ;
ALTER TABLE issues ADD COLUMN IF NOT EXISTS noise_reason TEXT;
