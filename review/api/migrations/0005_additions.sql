-- Suggested additions: a fourth action, 'add', with where the new item goes. SQLite can't change a CHECK in
-- place, so the table is rebuilt and its rows copied, ids included. Dropping a table that comments point at
-- would break their foreign key, so comments are set aside first and recreated, with the same ids, after.
CREATE TABLE comments_copy AS SELECT id, suggestion_id, author, body, created_at FROM comments;
DROP TABLE comments;

CREATE TABLE suggestions_new (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  action TEXT NOT NULL CHECK (action IN ('change', 'delete', 'note', 'add')),
  dataset TEXT NOT NULL,
  kind TEXT NOT NULL,
  item_id TEXT NOT NULL,
  entry_id TEXT NOT NULL,
  item_title TEXT NOT NULL,
  base_hash TEXT NOT NULL,
  proposed_json TEXT,
  furigana_json TEXT,
  dropped_blanks INTEGER NOT NULL DEFAULT 0,
  comment TEXT NOT NULL DEFAULT '',
  author TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'accepted', 'declined', 'withdrawn')),
  admin_edit_json TEXT,
  created_at TEXT NOT NULL,
  decided_at TEXT,
  decided_by TEXT,
  -- An addition's parent (null for a new entry), and its item without ids, for spotting a double tap.
  parent_kind TEXT,
  parent_id TEXT,
  fingerprint TEXT
);

INSERT INTO suggestions_new (id, action, dataset, kind, item_id, entry_id, item_title, base_hash, proposed_json,
  furigana_json, dropped_blanks, comment, author, status, admin_edit_json, created_at, decided_at, decided_by)
SELECT id, action, dataset, kind, item_id, entry_id, item_title, base_hash, proposed_json, furigana_json,
  dropped_blanks, comment, author, status, admin_edit_json, created_at, decided_at, decided_by
FROM suggestions;

DROP TABLE suggestions;
ALTER TABLE suggestions_new RENAME TO suggestions;

CREATE INDEX suggestions_by_entry ON suggestions (dataset, entry_id);
CREATE INDEX suggestions_by_status ON suggestions (status);
CREATE INDEX suggestions_by_target ON suggestions (dataset, kind, item_id);
CREATE INDEX suggestions_by_parent ON suggestions (dataset, parent_kind, parent_id);

CREATE TABLE comments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  suggestion_id INTEGER NOT NULL REFERENCES suggestions (id),
  author TEXT NOT NULL,
  body TEXT NOT NULL,
  created_at TEXT NOT NULL
);

INSERT INTO comments (id, suggestion_id, author, body, created_at)
SELECT id, suggestion_id, author, body, created_at FROM comments_copy;

DROP TABLE comments_copy;

CREATE INDEX comments_by_suggestion ON comments (suggestion_id);
