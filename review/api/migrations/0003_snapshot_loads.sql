-- A load in progress. Workers Free allows ~10 ms of CPU per request, so a big file is loaded in
-- slices (one request each) into items_staging, then swapped into items in one batch at the end.
CREATE TABLE snapshot_loads (
  load_id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  version TEXT NOT NULL,
  sha256 TEXT NOT NULL,
  git_ref TEXT,
  slices TEXT NOT NULL,
  started_by TEXT NOT NULL,
  started_at TEXT NOT NULL
);

CREATE TABLE snapshot_load_slices (
  load_id TEXT NOT NULL,
  slice INTEGER NOT NULL,
  PRIMARY KEY (load_id, slice)
);

CREATE TABLE items_staging (
  load_id TEXT NOT NULL,
  slice INTEGER NOT NULL,
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
  PRIMARY KEY (load_id, kind, item_id)
);
