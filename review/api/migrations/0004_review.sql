-- What reviewers do with the loaded items. Every row names its target as (dataset, kind, item_id) and keeps
-- working after the item leaves the data: titles and entry ids are copied in when the row is written.

-- One approval per reviewer per target. It counts only while content_hash equals the item's current hash.
CREATE TABLE approvals (
  dataset TEXT NOT NULL,
  kind TEXT NOT NULL,
  item_id TEXT NOT NULL,
  entry_id TEXT NOT NULL,
  reviewer TEXT NOT NULL,
  content_hash TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (dataset, kind, item_id, reviewer)
);

CREATE INDEX approvals_by_entry ON approvals (dataset, entry_id);

-- A change carries the whole proposed item (proposed_json); a delete or a note carries none.
-- Accepting only changes status: nothing reaches data/ until export.
CREATE TABLE suggestions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  action TEXT NOT NULL CHECK (action IN ('change', 'delete', 'note')),
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
  decided_by TEXT
);

CREATE INDEX suggestions_by_entry ON suggestions (dataset, entry_id);
CREATE INDEX suggestions_by_status ON suggestions (status);
CREATE INDEX suggestions_by_target ON suggestions (dataset, kind, item_id);

CREATE TABLE comments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  suggestion_id INTEGER NOT NULL REFERENCES suggestions (id),
  author TEXT NOT NULL,
  body TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE INDEX comments_by_suggestion ON comments (suggestion_id);

-- Lists of items the owner asks reviewers to look at.
CREATE TABLE queues (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  created_by TEXT NOT NULL,
  created_at TEXT NOT NULL,
  archived INTEGER NOT NULL DEFAULT 0 CHECK (archived IN (0, 1))
);

CREATE TABLE queue_items (
  queue_id INTEGER NOT NULL REFERENCES queues (id),
  dataset TEXT NOT NULL,
  kind TEXT NOT NULL,
  item_id TEXT NOT NULL,
  entry_id TEXT NOT NULL,
  item_title TEXT NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  position INTEGER NOT NULL,
  PRIMARY KEY (queue_id, dataset, kind, item_id)
);

CREATE TABLE skips (
  queue_id INTEGER NOT NULL,
  dataset TEXT NOT NULL,
  kind TEXT NOT NULL,
  item_id TEXT NOT NULL,
  reviewer TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (queue_id, dataset, kind, item_id, reviewer)
);
