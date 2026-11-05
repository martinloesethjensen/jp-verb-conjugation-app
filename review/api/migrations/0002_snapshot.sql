-- The published data the site has loaded: one row per file, and the browsable items inside them.
-- A file's rows are replaced in one batch, so a failed load leaves the previous snapshot intact.
CREATE TABLE snapshot_files (
  name TEXT PRIMARY KEY,
  version TEXT NOT NULL,
  sha256 TEXT NOT NULL,
  git_ref TEXT,
  item_count INTEGER NOT NULL,
  imported_at TEXT NOT NULL,
  imported_by TEXT NOT NULL,
  json TEXT
);

CREATE TABLE items (
  dataset TEXT NOT NULL,
  kind TEXT NOT NULL,
  item_id TEXT NOT NULL,
  parent_id TEXT,
  entry_id TEXT NOT NULL,
  position INTEGER NOT NULL,
  title TEXT NOT NULL,
  subtitle TEXT NOT NULL,
  jlpt TEXT,
  content_hash TEXT NOT NULL,
  json TEXT NOT NULL,
  PRIMARY KEY (dataset, kind, item_id)
);

CREATE INDEX items_by_entry ON items (dataset, entry_id);
