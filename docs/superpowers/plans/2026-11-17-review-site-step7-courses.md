# Review site step 7: courses on the site — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** reviewed by the owner on 2026-11-17, who chose subagent-driven execution without answering the open
questions, so the defaults below apply. PR 7A is being built; 7B–7E start once step 6 is on `main`.

**Goal:** Teachers, natives and the owner build courses (lessons of stable data ids, with goals and notes) on the
review site, propose missing grammar points from inside a lesson, send a course for review, a teacher who isn't the
author (or the owner) approves it, and `make review-pull` writes approved courses to `data/courses.json` in exactly
the shape of `docs/superpowers/specs/2026-11-17-courses-data-design.md`.

**Architecture:** New D1 tables (`courses`, `course_lessons`, `course_items`, `course_comments`, `course_reads`)
behind a new `CourseStore` trait (`review/api/src/course_store.rs`, implemented by `D1Store` and the tests'
`SqliteStore`), routes in `review/api/src/course_routes.rs`, and pages under `review/web/src/routes/courses/`.
Approval snapshots the course as `approved_json` (the courses.json course object minus `revision`, `since` and
`author`), so later edits never reach the app unreviewed. Export carries the approved snapshots; the Python pull
(the only writer of `data/`) adds `revision`, `since`, `author` credit and `withdrawn` by comparing with the
published file on `origin/main`.

**Tech Stack:** Rust Cloudflare Worker (`worker` crate, D1; native tests on in-memory SQLite running the same
migrations and SQL), SvelteKit 3 / Svelte 5 static site, vitest, svelte-check, Python 3 stdlib (`scripts/`).

**Spec:** `docs/superpowers/specs/2026-11-08-review-site-polish-design.md` (Roles; Reply alerts; Courses incl.
"App design (step 8)"; Decided questions; Build order 7) and `docs/superpowers/specs/2026-11-17-courses-data-design.md`.
Canvas boards (https://claude.ai/artifact/NKfDy5o7H7BbneLj9y5kzF): *Courses · list and start a course*, *Course
builder · desktop*, *Add to a lesson · phone*, *Course review and how it looks in the app*, *Course builder ·
propose a new grammar point*.

## Base and ordering

- `origin/main` (0227ca7, checked 2026-11-17) has steps 1–5 and 3b: migrations 0001–0010, `Need::Decider`,
  `Role::can_decide()/decides_all()`, `store::TIPS = ["inbox", "thread"]`.
- Step 6 (plan on local branch `claude/review-step6-51d104`, not pushed) takes **0011_opinions.sql** and
  **0012_releases.sql**. Step 7 starts at **0013**. Re-check `ls review/api/migrations` before each PR; if step 6
  hasn't merged, keep 0013+ anyway (wrangler applies missing files in name order).
- Files step 6 also touches (expect merges): `review_store.rs` (`with_reply_events!`, `Reply`), `d1.rs`,
  `tests/support/sqlite.rs`, `app.rs` (`Handler`, `ROUTES`), `review_routes.rs` (inbox, decide),
  `export_routes.rs`/`app.rs` load path (Part B), `web/src/lib/api.ts`, `replies.svelte.ts` (`replyText`),
  `routes/inbox/+page.svelte`, `SiteHeader.svelte` (B adds "Your contributions"), `dev/mock-api.ts`,
  `dev/mock-review.ts`, `review/README.md`, the polish spec's "As built" notes. **Build step 7 after step 6 merges**;
  PR 7A touches none of these except `app.rs`, `lib.rs`, `d1.rs`, `sqlite.rs` and can start in parallel.

## PR split (each ships something usable)

| PR | Ships | Migration |
|---|---|---|
| 7A | Tables, `CourseStore`, course CRUD API, data search route | 0013_courses.sql |
| 7B | Courses list and start (scratch / textbook / copy), builder desktop + phone add screen | — |
| 7C | Send for review, checks, comments, approve / ask for changes, inbox row, reply events, courses tip | 0014_course_reads.sql |
| 7D | Propose a new grammar point from a lesson (reuses `POST /api/add`) | — |
| 7E | Export: `/api/export` carries courses; `review_pull.py` fills the existing `data/courses.json`; withdraw (needs step 8's PR 8.1) | — |

## Global Constraints

- Light only; red only for seals, red-pen, unread counts, "new since your last visit", open-suggestion progress;
  green only for "Live in the app"/saved; ink pills for buttons.
- Furigana on every kanji through `Japanese.svelte` (search results, lesson items, previews).
- Touch targets ≥ 44 px (48 px in phone action bars); text ≥ 4.5:1; no horizontal page scroll; 16 px phone gutter.
- Strict CSP: no inline `style` attributes, no runtime `<style>`; component `<style>` blocks only (`npm run test:csp`).
- Only published (loaded) data goes into a course; anything missing goes through "Suggest adding it" or "Propose a new
  grammar point". No textbook text: a textbook course stores the book id and lesson numbers only.
- Nobody approves their own course or decides their own proposal (owner included). Teachers and the owner approve
  (`Role::decides_all()`); natives and reviewers don't.
- Copies are independent: credited "Copied from … by …" as text; no link, no flow-through.
- Copy says "another teacher or Martin approves it", never "Martin decides".
- Every write inserts its `audit_log` row in the same D1 batch.
- Never run `make data-release`, `make sign-commit` or `make review-pull`; no PR in this plan writes `data/` or
  `data/manifest.sig`.
- Published formats stay platform-neutral (no Apple-only assumptions).
- Tests: `cd review/api && cargo test`; `cd review/web && npm run check && npm test && npm run build && npm run test:csp`;
  `make test-py` for 7E. `make review-test` runs the review ones. No Swift tests (no Swift changes).

## Decisions this plan makes

1. **"Reviewed data" = items in the loaded published data** (`items` table), plus accepted grammar proposals made
   from the course (7D). Approvals/stamps are not required per item.
2. **Course kinds map to `items` rows:** verb = (`verbs`, `entry`), word = (`words`, `entry`), grammar = (`grammar`,
   `entry`), counter = (`counters`, `entry`), example = (`verbs`|`grammar`|`counters`, `example`), with `in` = the
   dataset. One pure function `course_kind(dataset, kind) -> Option<&str>` in `course_store.rs` and its inverse.
3. **Ids:** course and lesson ids are 6 characters from `addition::STABLE_ID_ALPHABET` (a subset of `[a-z0-9]`),
   random via `random_stable_id()`, unique among `courses.id` / within a course's lessons. Rows of exported courses
   are never deleted; a never-exported draft may be deleted outright.
4. **Status:** `draft → in_review → approved`, plus `withdrawn`. Only drafts are editable. "Ask for changes" returns
   `in_review → draft` with a required comment. Editing an approved course moves it to `draft` but keeps
   `approved_json`, so the approved version keeps shipping until a new approval ("Changes since approval aren't in
   the app yet"). The author may take an `in_review` course back to `draft`.
5. **Approval snapshot:** on approve, the Worker builds `approved_json` = `{id, title, summary, levels,
   copied_from, follows, lessons:[{id,title,goal,note,textbook_lesson,items:[{kind,id,in?}]}]}`. `levels` is
   computed from the items' `jlpt` (distinct, N5 first); the author doesn't pick levels.
6. **Approval checks** (`GET /api/course/checks`, and enforced in approve): ≥ 1 lesson; every lesson has a title, a goal
   and ≥ 1 item; no item twice in a lesson; every item is loaded or an accepted proposal; no proposal that is open,
   declined or withdrawn; `textbook_lesson` within the book's range (`first_lesson`..`lessons` from the loaded
   `grammar.json` `books`) when `follows` is set; the author ticked "nothing is copied from a textbook" (stored as
   `courses.own_words_at` on submit). Counters whose numbers above 10 are unreviewed are listed as an info line,
   not a blocker.
7. **Credit:** read at export time from the author's `public_name`/`public_role` (as stamps are), so authors can change
   it until the pull. `copied_from` is frozen text at copy time.
8. **Copy source:** any approved course (has `approved_json`); the copy gets new course and lesson ids and starts as a
   draft. Genki isn't copyable (it isn't a course); "Follow a textbook" covers it.
9. **Follow a textbook:** pick a book from the loaded `grammar.json` `books`; creates one empty lesson per book lesson,
   titled "Lesson n", `textbook_lesson = n`. Titles are then the author's.
10. **Search:** `GET /api/course/search?q=&kind=` over `items` (title/subtitle `LIKE`, case-insensitive), limited
    to 40, kinds per decision 2. Romaji is converted to hiragana by a new pure `review/api/src/romaji.rs`
    (Hepburn, the same table as VerbKit's `Romaji.toHiragana`; tests copied from VerbKit's cases) and searched as
    well.
11. **Comments and events:** `course_comments(id, course_id, lesson_id NULL, author, body, created_at)`; anyone
    may comment on a course in review or approved. Reply events (author told on comment/approve/changes asked;
    commenters told of later comments; never yourself) use a parallel `course_reads(user, course_id, read_at)`.
    `Reply` gains `course_id: Option<String>`; course events have `suggestion_id = 0`, `item_title` = course title,
    `what` ∈ `course_comment | course_approved | course_changes`. `POST /api/replies/read` accepts `courses: [ids]`.
12. **Visibility:** drafts are visible to their author and the owner; in-review and approved courses to everyone.
13. **Proposals:** `POST /api/course/propose` runs the same code as `POST /api/add` (refactor `add_routes::add` into
    `pub(crate) async fn add_one(body: AddBody, by, store, now) -> Result<(i64, bool), ApiResponse>`), restricted to
    `dataset = grammar, kind = entry`, then inserts a `course_items` row with `proposal_id` in the same request. The
    existing inbox, `/api/decide`, own-suggestion guard and reply alerts handle the rest unchanged.
14. **Export / publishing:** the site sends approved snapshots; `review_pull.py` writes `data/courses.json`:
    `revision` = published revision, +1 if the course object changed (1 if new); `since` = published value or the
    pull date; `author` from the export's credit; `withdrawn` = published ∪ site withdrawals of exported courses. A
    course whose items aren't all in the branch's data after the batch is applied is skipped and listed under
    "Skipped". The empty `data/courses.json`, its schema, the `update_data.py` checks, the manifest entry and the
    bundled copy come from step 8's PR 8.1 (owner, 2026-11-19: "Empty file first, in PR 8.1"); 7E only fills that file,
    with the same shape and ids.

## Review Focus

- **An item leaves the data after approval** (a verb is removed by a later pull). The builder marks it "No longer in
  the data", checks fail, and the pull skips the course rather than publishing a broken reference. (7A
  `missing_items_are_reported`, 7E `course_with_missing_item_is_skipped`.)
- **Editing an approved course** must not change what ships: export keeps sending the old `approved_json` until
  re-approval. (7C `editing_an_approved_course_keeps_the_approved_snapshot`.)
- **Lesson ids survive renames, moves and copies:** reordering lessons keeps ids; a copy gets fresh ids. (7A
  `reordering_keeps_lesson_ids`, 7B `copy_gets_new_ids_and_copied_from`.)
- **Author approving their own course** through either sign-in, or a native approving, is refused with 403. (7C.)
- **Proposal decided while the course is in review** (declined): approval stays blocked and the item shows
  "Declined · remove it". (7D `declined_proposal_blocks_approval`.)

---

## PR 7A — Tables and API (migration 0013)

### Task A1: migration and `CourseStore`

**Files:** Create `review/api/migrations/0013_courses.sql`, `review/api/src/course_store.rs`; modify
`review/api/src/lib.rs`, `review/api/src/d1.rs` (`impl CourseStore for D1Store`),
`review/api/tests/support/sqlite.rs`; test `review/api/tests/course_store.rs`.

Tables (SQL fixed here):
```sql
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
```

**Interfaces (produces):** types `Course`, `Lesson`, `CourseItem { dataset, kind, item_id, course_kind, title,
subtitle, jlpt, loaded: bool, proposal: Option<ProposalState> }`, `CourseSummary`; pure fns
`course_kind(dataset, kind) -> Option<&'static str>`; trait methods `create_course`, `course(id, viewer)`,
`courses(viewer)`, `save_course_meta`, `save_lessons(course_id, &[LessonInput])` (whole outline: ids, order,
fields, items — one batch, replaces lessons/items of a draft), `delete_draft`, `set_status`, `search_items(q, kinds,
limit)`. Every write adds an `audit_log` row (`course.create`, `course.save`, …) in the same batch.

Visibility is not the store's job: `course(id)` returns any course and the routes (A2) decide who may see it.
`save_lessons` refuses an item that is neither loaded nor already in that lesson of the stored course, so an item
that later left the data stays and reads back with `loaded = false`.

Tests: `create_and_read_back`, `save_lessons_replaces_outline_in_one_batch`, `reordering_keeps_lesson_ids`,
`missing_items_are_reported` (item row absent → `loaded = false`), `only_drafts_save` (a non-draft save changes
nothing and reports it), `unloaded_new_item_is_refused`, `every_write_logs_an_audit_row`, `course_kind_round_trips`
(all five kinds; `(words, example)` → `None`), `search_items_matches_title_and_subtitle_case_insensitively`. Run `cargo test --test course_store`; commit.

### Task A2: routes and search

**Files:** Create `review/api/src/course_routes.rs`, `review/api/src/romaji.rs`; modify `app.rs` (`Handler`,
`ROUTES`, `handle` bound `S: Store + ReviewStore + CourseStore`), `worker_glue.rs`; tests `review/api/tests/courses_api.rs`,
`review/api/tests/romaji.rs`.

Routes (all `Need::Reviewer`; ownership checked in handlers): `GET /api/courses`, `GET /api/course?id=`,
`POST /api/course/create {start: "scratch"|"textbook"|"copy", title, book?, from?}`, `POST /api/course/save
{id, title, summary, lessons:[…]}` (author only, draft only, max 60 lessons × 80 items, text limits as
`text_field`), `POST /api/course/delete {id}` (author or owner, never-exported only), `GET /api/course/search?q=&kind=`,
`GET /api/books` (from the loaded grammar snapshot).

Tests (`courses_api.rs`): `only_the_author_saves` (403 for others, owner included), `saving_a_non_draft_is_409`,
`unknown_item_refused_with_400` ("not in the loaded data"), `drafts_hidden_from_others` (404 for another reviewer,
visible to the owner), `in_review_courses_visible_to_everyone`, `search_by_english_kana_kanji_and_romaji`
(`taberu` → 食べる), `search_kind_filter`, `search_caps_at_40`, `textbook_start_numbers_lessons_from_first_lesson`
(genki-2 → 13…23, titles "Lesson n"), `textbook_start_refuses_unknown_book`, `copy_gets_new_ids_and_copied_from`,
`copy_of_an_unapproved_course_refused`, `delete_refused_once_exported`, `books_need_grammar_loaded`, and the
outline limits (61st lesson or 81st item → 400). `romaji.rs`: `taberu`, `kyou`, `shinbun`/`shimbun`, `kitte`,
`kan'i`, `chotto`, uppercase input, non-romaji passes through unchanged. A course test seeds `approved_json` with raw
SQL through the SQLite test store (add a small `execute` helper in `tests/support` if none exists). Commit; then
`review/README.md` Deploying note for 0013 and open PR 7A.

## PR 7B — List, start, builder (web)

### Task B1: API client, mock, pure helpers
`review/web/src/lib/api.ts` (`Course`, `CourseSummary`, `getCourses`, `getCourse`, `createCourse`, `saveCourse`,
`searchCourseItems`, `getBooks`), `review/web/src/lib/courses.ts` (pure: `moveItem`, `addItem` (no duplicate in a
lesson), `removeItem`, `lessonFilled`, `courseStatusLabel`), mock routes in `dev/mock-api.ts`/`mock-review.ts` for every 7A route.
Tests `courses.test.ts`: `addItem` refuses a duplicate in one lesson but allows it in another; `moveItem` up/down at
both ends is a no-op; `removeItem` keeps order; `lessonFilled` false for no items or no goal; `courseStatusLabel`
for draft, in review, approved, approved-then-edited ("Changes since approval") and withdrawn.

### Task B2: `/courses` list and start (board *Courses*)
`routes/courses/+page.svelte`, `lib/CourseCard.svelte`; `SiteHeader.svelte` gains "Courses" for everyone (desktop
nav and phone menu). Sections: Your courses, Waiting for a teacher (deciders only), In the app (approved; Genki card
as on the board), Start a course (three options; copy opens a picker of approved courses). Tests (`course-card.test.ts`): label and pill style per status, lessons
bar aria text ("6 of 10 lessons have items"), copy credit line, the deciders-only section hidden for a reviewer,
no inline `style` (CSP test covers the build).

### Task B3: builder `/courses/edit?id=` (board *Course builder · desktop*)
`routes/courses/edit/+page.svelte`, `lib/LessonOutline.svelte`, `lib/LessonEditor.svelte`, `lib/AddFromData.svelte`.
Autosave (debounced 800 ms, "Saved" in green), reorder by up/down buttons (44 px) plus drag on desktop, kind chips,
"Suggest adding it" link to `/add?dataset=…`. Below 960 px the outline is a list, a lesson opens full width and
"Add" goes to `/courses/add?id=&lesson=` (board *Add to a lesson · phone*, 48 px bottom bar with Done). Read-only
view for non-drafts with "Edit" (author) that warns when approved. Tests: an `autosave` helper
(`courses.ts`: debounce, one save in flight, a failed save shows the error and keeps the edit) and component tests
(`lesson-editor.test.ts`: "No longer in the data" on an unloaded item; reorder buttons labelled and ≥ 44 px; the
read-only view hides inputs; editing an approved course asks first). Commit, README Reviewing › Courses, open PR 7B.

## PR 7C — Review and approval (migration 0014)

### Task C1: submit, checks, approve, ask for changes, comments (API)
`0014_course_reads.sql` (`course_reads(user, course_id, read_at, PRIMARY KEY(user, course_id))`); routes
`GET /api/course/checks?id=`, `POST /api/course/submit {id, own_words: true}`, `POST /api/course/unsubmit`,
`POST /api/course/approve {id}` (`decides_all`, not author, checks pass → writes `approved_json` per decision 5),
`POST /api/course/changes {id, comment}`, `POST /api/course/comment {id, lesson?, body}`. Tests:
`author_cannot_approve_own_course` (owner too), `native_cannot_approve`, `approve_refused_while_checks_fail`,
`editing_an_approved_course_keeps_the_approved_snapshot`, `approved_json_matches_courses_data_shape`.

### Task C2: reply events and inbox row
Extend `with_reply_events!` with the three course events (decision 11), `Reply.course_id`, `mark_read` for courses,
`unread_count`. Inbox response gains `courses_waiting: [CourseSummary]` for `decides_all` viewers. Add `"courses"`
to `store::TIPS`. Tests in `replies_api.rs`: `author_told_of_comment_approval_and_changes`,
`commenter_told_of_later_comments`, `never_told_of_own_course_actions`, `reading_the_course_clears_its_events`,
`course_events_count_in_unread`; `inbox_api.rs`: `courses_waiting_listed_for_teachers_and_owner`,
`not_for_natives_or_reviewers`, `own_course_not_in_my_waiting_list`; `settings_api.rs`: `courses_tip_dismisses`.

### Task C3: review page `/courses/review?id=` (board *Course review*)
`routes/courses/review/+page.svelte`, `lib/CourseChecks.svelte`, `lib/CourseThread.svelte`; steps strip (Written →
In review → A teacher approves (not the author) → In the app), checks list, lessons with item chips and per-lesson
comments, Approve / Ask for changes for deciders who aren't the author, "A teacher or Martin approves this one"
otherwise, the "How it looks in the app" sketch. Inbox shows "Courses waiting for a teacher (n)". `replyText` and
reply links for course events; `<Tip id="courses">` on `/courses`. Tests: `course-checks.test.ts` (each failing check's wording, the info line for
unreviewed counters), `replies.test.ts` (`replyText` and link for each course event), and the review page shows
Approve only to a decider who isn't the author. README + spec "As built (step 7)", open PR 7C.

## PR 7D — Propose a new grammar point

### Task D1: API
Refactor `add_routes::add` into `add_one` (decision 13) with no behaviour change (existing `add_api.rs` must pass
untouched), add `POST /api/course/propose {course, lesson, fields, furigana?, comment?}` (author, draft, grammar
entry only). Course items with `proposal_id` report `proposal: open|accepted|declined|withdrawn`. Tests:
`proposal_lands_in_inbox_and_lesson`, `author_cannot_accept_own_proposal_in_own_course`,
`declined_proposal_blocks_approval`, `accepted_proposal_counts_as_present`.

### Task D2: page `/courses/propose?id=&lesson=` (board *propose a new grammar point*)
Reuse `SuggestForm.svelte` with `reference.add_fields["grammar/entry"]` (as `/add` does); preview on the genkō grid;
"Proposed · waiting for a teacher" dashed pill in the lesson; "Withdraw the proposal" calls `/api/suggest/withdraw`
and removes the item. Inbox suggestion card shows "For the course “…”, lesson n". Tests: proposal pill per state
(open, accepted, declined "remove it", withdrawn), withdraw removes the item, the form shows the Worker's message for
a taken id. README, open PR 7D.

## PR 7E — Export to `data/courses.json`

### Task E1: Worker export and withdraw
`export_routes::batch` adds `courses: [{course: approved_json, credit: {role, name}, site_id}]` for approved (and
approved-then-edited) courses and `withdrawn_courses: [ids]` of exported-then-withdrawn ones; `mark` accepts
`courses: [ids]` (sets `exported_at`). `POST /api/course/withdraw {id}` (author or owner). Tests in `export_api.rs`:
`export_sends_approved_snapshot_not_draft_edits`, `export_skips_drafts_and_in_review`, `credit_read_at_export_time`,
`withdrawn_listed_only_when_exported_before`, `mark_exported_sets_course_exported_at`; `courses_api.rs`:
`withdraw_by_author_or_owner_only`, `withdrawing_a_never_exported_course_leaves_no_tombstone`.

### Schema and checks: not here

Step 8's PR 8.1 (plan `docs/superpowers/plans/2026-11-17-courses-in-the-app.md`, branch
`claude/courses-app-plan-a6316b`) adds the empty `data/courses.json`, `schema/courses.schema.json`, the
`update_data.py` checks, the manifest entry and the bundled copy. **7E starts only once PR 8.1 is on `main`.** If
8.1's checks or schema disagree with what this plan's export produces, follow 8.1 and the data-design spec.

### Task E2: pull fills the file
`scripts/review_export.py` gains `apply_courses(batch, docs, published, today)` (decision 14) and the summary gains
"Courses: …" and "Course ids: …" in its last line; `scripts/review_pull.py` rewrites the existing `data/courses.json` (key order as
the data-design spec shows, NFC) and runs `update_data.py`, whose 8.1 checks then guard it. Tests in `scripts/test_review_export.py`: new course gets revision 1 and today's
`since`; unchanged course keeps revision; changed course +1; `course_with_missing_item_is_skipped`; withdrawn union;
an empty published file (8.1's) fills correctly; the result passes 8.1's `update_data.py` checks.
The Export page's "Tick these" accepts course ids. Update the data-design spec's status to "built (site side)",
README Exporting, open PR 7E. Never run `make review-pull` to try it: tests use fixtures.

## Open questions for the owner

1. **Second check.** The *Course review* board shows "Second check (Yumi)" before a teacher approves. The spec says
   one teacher's approval is enough. This plan makes comments open to everyone but no required second check. OK?
2. **Who sees drafts?** Plan: author and owner only. Should teachers see drafts too (to help early)?
3. **Who may withdraw a published course?** Plan: the author or the owner. Should a teacher be able to?
4. **Levels computed, not chosen.** Plan computes `levels` from the items at approval. Or should authors pick them?
5. ~~Step 7 or 8 for the file?~~ **Settled 2026-11-19:** the empty file, schema, checks, manifest entry and bundled
   copy come first, in step 8's PR 8.1; 7E stays in step 7 and only fills the file.
6. **"In the app since …"** on the list board needs the release a course shipped in. Step 6 Part B records releases
   from signed loads; courses.json isn't loaded by the site. Plan shows "Exported" with the date until then. Wire it to
   step 6's releases later?
