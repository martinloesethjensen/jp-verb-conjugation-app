-- Courses (step 7): teacher/native-authored courses, their lessons and items, and comments on them.
-- Items name a published item by (dataset, kind, item_id); a grammar proposal made from the course also
-- carries its suggestion id. Rows of exported courses are never deleted. 0011 and 0012 are reserved.
-- The owner applies this by hand (npm run migrate in review/api).

CREATE TABLE courses (
  id TEXT PRIMARY KEY, title TEXT NOT NULL, summary TEXT NOT NULL DEFAULT '',
  author TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','in_review','approved','withdrawn')),
  follows_book TEXT, copied_from_json TEXT, own_words_at TEXT,
  approved_json TEXT, approved_by TEXT, approved_at TEXT, submitted_at TEXT,
  exported_at TEXT, withdrawn_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
CREATE INDEX courses_by_author ON courses (author);
CREATE INDEX courses_by_status ON courses (status);

CREATE TABLE course_lessons (
  course_id TEXT NOT NULL REFERENCES courses (id), id TEXT NOT NULL, position INTEGER NOT NULL,
  title TEXT NOT NULL DEFAULT '', goal TEXT NOT NULL DEFAULT '', note TEXT NOT NULL DEFAULT '',
  textbook_lesson INTEGER, PRIMARY KEY (course_id, id));

CREATE TABLE course_items (
  course_id TEXT NOT NULL, lesson_id TEXT NOT NULL, position INTEGER NOT NULL,
  dataset TEXT NOT NULL, kind TEXT NOT NULL, item_id TEXT NOT NULL, proposal_id INTEGER REFERENCES suggestions (id),
  PRIMARY KEY (course_id, lesson_id, dataset, kind, item_id));

CREATE TABLE course_comments (
  id INTEGER PRIMARY KEY AUTOINCREMENT, course_id TEXT NOT NULL REFERENCES courses (id),
  lesson_id TEXT, author TEXT NOT NULL, body TEXT NOT NULL, created_at TEXT NOT NULL);
CREATE INDEX course_comments_by_course ON course_comments (course_id);
