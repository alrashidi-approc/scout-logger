ALTER TABLE notification_deliveries
  ADD COLUMN IF NOT EXISTS urgency TEXT NOT NULL DEFAULT 'normal';
