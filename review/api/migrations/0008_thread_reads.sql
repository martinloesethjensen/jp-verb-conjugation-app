-- Reply alerts (polish step 4): when each person last saw each suggestion's thread. Unread replies and
-- decisions are worked out from comments and suggestions against this; nothing else is stored. Everyone
-- already in a thread (its author and its commenters) starts with it read, so the deploy isn't a wall of
-- red. The owner applies this by hand (npm run migrate in review/api).

CREATE TABLE thread_reads (
  user TEXT NOT NULL,
  suggestion_id INTEGER NOT NULL REFERENCES suggestions (id),
  read_at TEXT NOT NULL,
  PRIMARY KEY (user, suggestion_id)
);

INSERT OR IGNORE INTO thread_reads (user, suggestion_id, read_at)
  SELECT author, id, strftime('%Y-%m-%dT%H:%M:%fZ', 'now') FROM suggestions;

INSERT OR IGNORE INTO thread_reads (user, suggestion_id, read_at)
  SELECT author, suggestion_id, strftime('%Y-%m-%dT%H:%M:%fZ', 'now') FROM comments;
