-- Natives (polish step 3b): users.role gains 'native', who accepts and declines other people's changes to
-- the Japanese fields of existing items. SQLite can't change a CHECK, so the table is rebuilt with every row
-- kept, as in 0007. The owner applies this by hand (npm run migrate in review/api).

CREATE TABLE users_new (
  email TEXT PRIMARY KEY CHECK (email = lower(email)),
  display_name TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('admin', 'teacher', 'native', 'reviewer')),
  active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
  created_at TEXT NOT NULL,
  public_role TEXT NOT NULL DEFAULT 'native' CHECK (public_role IN ('owner', 'teacher', 'native')),
  public_name TEXT
);

INSERT INTO users_new (email, display_name, role, active, created_at, public_role, public_name)
  SELECT email, display_name, role, active, created_at, public_role, public_name FROM users;

DROP TABLE users;

ALTER TABLE users_new RENAME TO users;
