-- Settings and onboarding (polish step 5): one row per person, created on their first change. No row means
-- every default. Preferences aren't data changes, so they write no audit rows. The owner applies this by
-- hand (npm run migrate in review/api).

CREATE TABLE user_settings (
  user TEXT PRIMARY KEY,
  welcome_seen_at TEXT,
  tour_seen_at TEXT,
  tips_on INTEGER NOT NULL DEFAULT 1 CHECK (tips_on IN (0, 1)),
  tips_dismissed TEXT NOT NULL DEFAULT '[]',
  shortcuts_on INTEGER NOT NULL DEFAULT 1 CHECK (shortcuts_on IN (0, 1))
);
