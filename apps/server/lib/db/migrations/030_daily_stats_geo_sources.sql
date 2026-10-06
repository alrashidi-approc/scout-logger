-- Geo source counters for geoBreakdown (D11). Constant defaults: no table rewrite.
-- Existing rows are filled by bin/backfill_geo_sources.dart after deploy.
ALTER TABLE daily_stats ADD COLUMN IF NOT EXISTS geo_locale INT NOT NULL DEFAULT 0;
ALTER TABLE daily_stats ADD COLUMN IF NOT EXISTS geo_ip INT NOT NULL DEFAULT 0;
ALTER TABLE daily_stats ADD COLUMN IF NOT EXISTS geo_profile INT NOT NULL DEFAULT 0;

-- One-time data backfills that run outside migrations.
CREATE TABLE IF NOT EXISTS backfills (
  name    TEXT PRIMARY KEY,
  done_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
