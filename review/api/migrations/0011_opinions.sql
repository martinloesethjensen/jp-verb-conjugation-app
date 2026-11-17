-- Second opinions (polish step 6): a teacher or the owner asks one person what they think of an item's open
-- suggestions. A request hangs on the item, not on one suggestion: anchor_id is the oldest open suggestion
-- when it was asked (the thread the ask appears in), and pick is the suggestion the answer favours, if any.
-- It is waiting while unanswered, not cancelled, and the item still has an open suggestion; nothing else
-- is stored. The owner applies this by hand (npm run migrate in review/api).

CREATE TABLE opinion_requests (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  dataset TEXT NOT NULL,
  kind TEXT NOT NULL,
  item_id TEXT NOT NULL,
  entry_id TEXT NOT NULL,
  item_title TEXT NOT NULL,
  anchor_id INTEGER NOT NULL REFERENCES suggestions (id),
  asked_by TEXT NOT NULL,
  asked_of TEXT NOT NULL,
  question TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  answered_at TEXT,
  pick INTEGER REFERENCES suggestions (id),
  answer TEXT NOT NULL DEFAULT '',
  cancelled_at TEXT
);

-- One open request per item.
CREATE UNIQUE INDEX opinion_open ON opinion_requests (dataset, kind, item_id)
  WHERE answered_at IS NULL AND cancelled_at IS NULL;

-- The replies query starts from the people on either side of a request.
CREATE INDEX opinions_by_asked_of ON opinion_requests (asked_of);
CREATE INDEX opinions_by_asked_by ON opinion_requests (asked_by);

-- The replies query's authors branch finds requests on the item of each of a person's suggestions.
CREATE INDEX opinions_by_item ON opinion_requests (dataset, kind, item_id);
