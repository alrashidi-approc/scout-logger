CREATE INDEX CONCURRENTLY IF NOT EXISTS issues_title_trgm ON issues USING gin (title gin_trgm_ops);
