-- Export (plan 6): how each reviewer is credited in the public repo, the owner's stamps waiting for export,
-- and which accepted suggestions have been exported. Only new columns and tables: nothing is rebuilt.

-- The role a stamp or a PR summary names, and an optional public name (NULL: credited by role only).
ALTER TABLE users ADD COLUMN public_role TEXT NOT NULL DEFAULT 'native'
  CHECK (public_role IN ('owner', 'teacher', 'native'));
ALTER TABLE users ADD COLUMN public_name TEXT;
UPDATE users SET public_role = 'owner' WHERE role = 'admin';

-- Set when the owner marks the export batch that carried it as merged.
ALTER TABLE suggestions ADD COLUMN exported_at TEXT;

-- A stamp the owner made on a fully approved entry, waiting for export. `reviewer` is the email of the most
-- senior reviewer involved; their public name is read at export time, so they can change it until then.
CREATE TABLE stamps (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  dataset TEXT NOT NULL,
  kind TEXT NOT NULL,
  item_id TEXT NOT NULL,
  entry_id TEXT NOT NULL,
  item_title TEXT NOT NULL,
  content_hash TEXT NOT NULL,
  by_role TEXT NOT NULL CHECK (by_role IN ('owner', 'teacher', 'native')),
  reviewer TEXT NOT NULL,
  created_by TEXT NOT NULL,
  created_at TEXT NOT NULL,
  exported_at TEXT
);

CREATE UNIQUE INDEX stamps_pending ON stamps (dataset, kind, item_id) WHERE exported_at IS NULL;
