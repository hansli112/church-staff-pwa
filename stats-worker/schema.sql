-- npx wrangler@4 d1 execute church-install-stats --remote --file stats-worker/schema.sql
CREATE TABLE IF NOT EXISTS events (
  id INTEGER PRIMARY KEY,
  at TEXT NOT NULL,
  event TEXT NOT NULL,
  session TEXT NOT NULL,
  run_id TEXT,
  step TEXT,
  code TEXT,
  revision TEXT
);
CREATE INDEX IF NOT EXISTS events_by_event ON events (event, at);
