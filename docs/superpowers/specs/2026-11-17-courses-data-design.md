# `data/courses.json` — design

Status: file, schema and checks built (step 8, PR 8.1); export pending (step 7). Written for build order
step 8 of `2026-11-08-review-site-polish-design.md` (see its "App design (step 8)" note).

As built (PR 8.1): `data/courses.json` starts empty (`"courses": []`, `"withdrawn": []`) and is required from
now on, so a bundled, signed copy exists before any course does. `schema/courses.schema.json` is written from
the Fields table, `check_courses` in `scripts/update_data.py` implements the Checks list (item ids are checked
against the loaded verbs, words, grammar and counters, and example ids per file), and `make data` gives it a
`courses` manifest entry and a bundled copy with a `courses.manifest.json` sidecar in
`Packages/VerbKit/Sources/VerbKit/Resources/`. Step 7's export pull updates this existing file. Course titles, goals and notes must use only kanji that `kanji.json` covers, or `make data` fails (relevant to step 7's export).

## Goal

One published file that carries the courses teachers and native speakers write on the review site, so
any client can list them, show a course and its lessons, and keep a learner's progress through updates
and withdrawals. It is a cross-platform contract: plain JSON with stable string ids and no Apple-only
assumptions (no App Group paths, SwiftData, `UserDefaults` or Swift `Codable` quirks).

## Rules

1. **Written by export only.** The review site's export writes the file; `make data` regenerates
   and checks it; it is signed with the batch by `make data-release`. Clients never fetch courses from
   the site.
2. **References, not content.** A course holds ids of items already in the same release's data files.
   It never repeats an item's text, and it carries no example sentence of its own.
3. **No textbook text.** A course that follows a textbook gives lesson numbers only, never the book's
   titles, text or examples. Titles, goals, notes and summaries are the author's own words (the author
   confirms this on the site).
4. **Stable ids.** Course ids and lesson ids never change and are never reused. A lesson keeps its id
   when it is renamed, moved or edited. Clients key progress on them.
5. **Withdrawals leave a tombstone.** A withdrawn course moves from `courses` to `withdrawn` (its id
   only), so clients can tell "withdrawn" from "never seen".

## Shape

```json
{
  "version": "1.0.0",
  "description": "Courses written by teachers and native speakers, approved on the review site.",
  "courses": [
    {
      "id": "c7k2mq",
      "revision": 3,
      "since": "2026-11-10",
      "title": "Everyday verbs in 10 lessons",
      "summary": "The N5 verbs you need for a normal day, one routine at a time.",
      "levels": ["N5"],
      "author": { "name": "Kenji", "role": "teacher" },
      "copied_from": null,
      "follows": null,
      "lessons": [
        {
          "id": "l4x9ta",
          "title": "Morning routine",
          "goal": "Say what you do each morning.",
          "note": "Learn the ます forms first; the plain forms come in lesson 6.",
          "textbook_lesson": null,
          "items": [
            { "kind": "verb", "id": "おきる" },
            { "kind": "word", "id": "adverb:まいあさ" },
            { "kind": "grammar", "id": "masu" },
            { "kind": "counter", "id": "ji" },
            { "kind": "example", "in": "verbs", "id": "8iij9b" }
          ]
        }
      ]
    }
  ],
  "withdrawn": ["p0lite"]
}
```

(The ids above show the format; they are not checked against the current data.)

## Fields

| Field | Type | Meaning |
|---|---|---|
| `version` | semver string | The file's version, compared like every data file's (`DataVersion`). |
| `courses[].id` | string, `[a-z0-9]{6}` | Stable course id, made by the site. |
| `courses[].revision` | integer ≥ 1 | Raised by export whenever anything in the course changes. A client compares it with the copy it last saw to decide whether to show the "updated" notice. |
| `courses[].since` | `yyyy-MM-dd` | The release date the course first shipped in. |
| `title`, `summary` | string | The author's words. `summary` is one or two sentences. |
| `levels` | array of `N5`…`N1` | JLPT levels the course covers, easiest first; may be empty. |
| `author.name` | string or absent | Public name. Absent when the author chose to be credited by role only. |
| `author.role` | `teacher`, `native` or `owner` | Clients turn it into wording ("Teacher", "Native speaker", "A teacher"). |
| `copied_from` | object or `null` | `{ "title", "author": { "name"?, "role" } }` of the original, copied in when the course was copied. Text only: it survives the original being withdrawn and creates no link (copies are independent, decided 2026-11-11). |
| `follows` | object or `null` | `{ "book": "genki-1" }` when the course follows a textbook. `book` is an id from `grammar.json`'s `books`. |
| `lessons[]` | array, ≥ 1 | In teaching order. |
| `lessons[].id` | string, `[a-z0-9]{6}` | Stable lesson id, unique within the course. |
| `lessons[].title`, `goal` | string | `goal` completes "After this lesson you can …". |
| `lessons[].note` | string or `null` | The author's note for learners. |
| `lessons[].textbook_lesson` | integer or `null` | Lesson number in `follows.book`; only when `follows` is set. |
| `lessons[].items[]` | array, ≥ 1 | In teaching order. |
| `items[].kind` | `verb`, `word`, `grammar`, `counter`, `example` | What the id points at. |
| `items[].id` | string | The item's published id: a verb id (`dict`, or `dict:kanji` for homophones), a word id (`class:dict`), a grammar point id, a counter id, or an example id. |
| `items[].in` | `verbs`, `grammar`, `counters` | Examples only: the data file the example lives in. |
| `withdrawn` | array of course ids | Courses that were published and then withdrawn. Never shrinks. |

Strings are UTF-8 and NFC. No field holds HTML or Markdown.

## Checks (export and `make data-check`)

- Every item id exists in the same release's data files, under the right kind (and file for examples).
- Every course has at least one lesson and every lesson at least one item; no item appears twice in a
  lesson.
- Course ids are unique across `courses` and `withdrawn`; lesson ids are unique within a course; an id
  in `withdrawn` never comes back to `courses`.
- `textbook_lesson` is set only when `follows` is, and lies within that book's lessons in `grammar.json`.
- `revision` never goes down for a course id between releases (checked against the published copy, like
  the verb id guard).
- Unreviewed counter numbers in a course are allowed; clients label them "unreviewed" as they do today.

## Manifest and sync

- `manifest.json` gains `"courses": { "version", "sha256" }`, like the other per-file entries, and the
  file is signed with the batch.
- The app bundles a copy and installs it like the six other bundled files
  (`2026-10-27-offline-first-launch-design.md`); CI fails a stale bundled copy.
- On iOS it is an eighth concrete sync service using `SyncVerification` (rollback rejection, hash check,
  decoding), with its own manifest type and sync state, per the U12 decision in `AGENTS.md`. The store
  persists the file before it confirms the sync.

## What a client keeps on the device

Not part of the file, but every client needs the same behaviour so progress survives a release:

- The last copy of each course the learner started (to diff for "What changed" and to keep withdrawn
  lessons).
- The learner's edits over each course lesson, keyed by `(course id, lesson id)`: added item refs,
  removed item refs, order. Items resolve against the current data; an item that has left the data is
  skipped.
- Done marks keyed by `(course id, lesson id)`.
- When a course id moves to `withdrawn`, its started lessons become the learner's own lessons (title and
  resolved items kept; goal and note dropped), with their done marks.

## Out of scope

- Courses written or edited in the app.
- Translations of titles, goals and notes.
- A live link from a copy to its original.
