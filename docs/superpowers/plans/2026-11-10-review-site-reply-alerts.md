# Review site reply alerts (polish spec step 4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tell reviewers when someone replies in a thread they're part of, or decides their suggestion: a bell with a red count, a Replies page, a Home section, and a "New since your last visit" line in the thread.

**Architecture:** A new table, `thread_reads(user, suggestion_id, read_at)`, records when each person last saw each thread. Unread events are computed on read from `comments` and `suggestions.decided_at`, never stored. One route lists a person's recent events with an unread flag and the unread count. Another marks threads read. Writing a suggestion, comment or decision marks that thread read for its writer. On the site, one small reactive store holds the replies; the header, the Home view and the Replies page read it. A suggestion card marks its own thread read when it shows new activity.

**Tech Stack:** Rust workers-rs Worker with D1 (tests on in-memory SQLite: `tests/support/sqlite.rs`), SvelteKit 5 static site with runes, Vitest (`svelte/server` render tests).

**Spec:** `docs/superpowers/specs/2026-11-08-review-site-polish-design.md`: Reply alerts, Principles 2 ("Red is earned": unread counts and the "new since your last visit" line are red), Layout › Header, Build order step 4.

## Global Constraints

- **Who is told** (this step): the author of a suggestion or note; anyone who commented in its thread; the author when it is accepted or declined. **Never yourself.** Second opinions (step 6) and course events (step 7) come later.
- Withdrawals aren't events. Only `accepted` and `declined` decisions are.
- No push, no service worker. The site fetches replies when it loads and after each navigation.
- **Everything before the deploy counts as read.** Migration 0008 seeds a row for every person already involved in a thread, so day one isn't a wall of red.
- Timestamps are the Worker's ISO strings (`toISOString`, `2026-11-10T12:00:00.000Z`) and compare as text. The migration seeds with `strftime('%Y-%m-%dT%H:%M:%fZ', 'now')`, which has the same shape.
- D1 migrations are run by the owner by hand (`npm run migrate` in `review/api`). Never run them against production.
- Web CSP rules stay: no `style="…"`, no `style:` directives, no transitions. Light only. Red only for the count and the new-since line. Touch targets ≥ 44 px. Furigana on every kanji (titles go through `Japanese.svelte`).
- The phone breakpoint is the site's existing `@media (max-width: 720px)`.
- Full check: `make review-test`, plus CI's `cd review/api && cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo clippy --target wasm32-unknown-unknown -- -D warnings`. Don't hold a `RefCell` borrow of the test store across an `.await`: scope it in a block. `drop()` doesn't satisfy Clippy.

## Review Focus

1. A person who commented and then gets another reply: told about the new reply, not about comments from before their own. Pinned in Task 2 (`a_commenter_hears_only_what_came_after_their_comment`).
2. Someone's own comment, or a teacher's decision with a reply on a suggestion they didn't write: never an event for the person who wrote it. Pinned in Task 2 (`nothing_you_did_yourself_is_an_event`).
3. Thread activity from before migration 0008: read. Pinned in Task 1 (`migration_0008_marks_existing_threads_read`).
4. Marking read is monotonic: an older `read_at` (two tabs) never moves it back. Pinned in Task 1 (`mark_read_never_moves_back`).
5. Replies fail to load (network or 500): the header shows no count and no error, and the rest of the page works. Pinned in Task 3 (`a_failed_load_shows_no_count`).

---

### Task 1: `thread_reads`, marking read, and the viewer's read time on suggestions

**Files:**
- Create: `review/api/migrations/0008_thread_reads.sql`
- Modify: `review/api/src/review_store.rs` (SQL, `ReviewStore` trait, `Suggestion`, `Comment`), `review/api/src/d1.rs`, `review/api/tests/support/sqlite.rs`, `review/api/src/review_routes.rs` and `review/api/src/add_routes.rs` (mark read after a write)
- Test: `review/api/tests/review_store.rs`, `review/api/tests/review_api.rs`

**Interfaces:**
- Produces:
  - Table `thread_reads (user TEXT NOT NULL, suggestion_id INTEGER NOT NULL REFERENCES suggestions (id), read_at TEXT NOT NULL, PRIMARY KEY (user, suggestion_id))`.
  - `pub const UPSERT_READ: &str`: `?1` user, `?2` suggestion id, `?3` read_at. Inserts the row, or on conflict sets `read_at = MAX(read_at, excluded.read_at)`, and only when the suggestion exists.
  - `ReviewStore::mark_read(&self, user: &str, ids: &[i64], now: &str) -> Result<(), StoreError>`: one batch with no audit row (reading isn't a change).
  - `Suggestion.last_read: Option<String>`: the viewer's `read_at` for this thread, `None` without a row.
  - `Comment.mine: bool`: the viewer wrote it.
- After a successful `/api/suggest`, `/api/add`, `/api/comment` and `/api/decide`, the handler calls `mark_read(&by.email, &[id], now)` for that suggestion.

- [ ] **Step 1: Write the failing tests.**
  - `review_store.rs::migration_0008_marks_existing_threads_read`: build with `with_migrations_before("0008")`. Insert users, one suggestion by Aiko and a comment on it by Ben, then `apply_migrations_from("0008")`. Both Aiko and Ben have a `thread_reads` row for it with a non-empty `read_at`. Martin (uninvolved) has none.
  - `review_store.rs::mark_read_never_moves_back`: `mark_read(AIKO, &[id], "2026-11-10T12:00:00.000Z")`, then `mark_read(AIKO, &[id], "2026-11-09T12:00:00.000Z")`. `read_at` stays the later one. `mark_read` on an unknown id writes nothing and doesn't error.
  - `review_api.rs::writing_marks_the_thread_read_for_the_writer`: Aiko suggests, so `/api/review` for that entry, as Aiko, shows `last_read` set on her suggestion and `null` for Ben. Ben comments, so Ben's `last_read` is set and the comment has `mine: true` for Ben and `mine: false` for Aiko.
- [ ] **Step 2: Run them.** `cd review/api && cargo test --test review_store --test review_api`. Expected: FAIL (no migration 0008, no `mark_read`, no `last_read`).
- [ ] **Step 3: Implement.**
  - Migration: create the table, then seed it from the same pairs the events use: `INSERT OR IGNORE INTO thread_reads SELECT author, id, <now> FROM suggestions`, then the same `FROM comments` with `author, suggestion_id`. Add a header comment saying the owner applies it by hand.
  - `suggestions_where!`: `LEFT JOIN thread_reads r ON r.user = ?1 AND r.suggestion_id = s.id`, selecting `r.read_at AS last_read`. `comments_where!`: `(c.author = ?1) AS mine`. Check every caller binds `?1` as the viewer (the inbox comments query uses `?1 IS NOT NULL` today, so it binds the viewer already).
  - `mark_read` in both stores. The handlers call it after their write succeeds. A failed `mark_read` is ignored: the write already happened.
- [ ] **Step 4: Run them.** `cargo test --no-fail-fast` and both Clippy runs. Expected: all pass.
- [ ] **Step 5: Commit.** `review-api: thread_reads (migration 0008) and the viewer's last read on suggestions`

### Task 2: The replies routes

**Files:**
- Create: `review/api/src/reply_routes.rs` (handlers, `Reply` type, SQL)
- Modify: `review/api/src/lib.rs`, `review/api/src/app.rs` (routes), `review/api/src/review_store.rs` (trait), `review/api/src/d1.rs`, `review/api/tests/support/sqlite.rs`
- Test: create `review/api/tests/replies_api.rs`

**Interfaces:**
- Consumes: `thread_reads`, `mark_read` (Task 1).
- Produces:
  - `GET /api/replies` (`Need::Reviewer`) returns `{ "unread": <count of unread events>, "replies": [Reply…] }`: the newest 50 events, newest first, each with an `unread` flag.
  - `Reply`, serialized:
    - `{ suggestion_id, what: "comment" | "accepted" | "declined", by_name, at, body, item_title, dataset, kind, item_id, entry_id, action, parent_kind, parent_id, unread }`
    - `body` is the comment text, cut to 140 characters with `…` (`""` for decisions).
  - `POST /api/replies/read` (`Need::Reviewer`, `deny_unknown_fields`) takes `{ "ids": [i64…] }` (1–200 ids) or `{ "all": true }`, and returns `{ "unread": <new count> }`. `all` marks every thread with an unread event.
  - `ReviewStore::replies(&self, viewer: &str, limit: u32) -> Result<(Vec<Reply>, u32), StoreError>`, and `ReviewStore::unread_threads(&self, viewer: &str) -> Result<Vec<i64>, StoreError>` for `all`.
- The event rule, as SQL over `?1` = viewer (write it once, as a macro, and use it for both the list and the count):
  - **A comment** `c` on suggestion `s` is an event for the viewer when `c.author <> ?1` and the viewer is involved: `s.author = ?1`, or the viewer has a comment on `s`. It's unread when `c.created_at > IFNULL(r.read_at, '')`.
  - **A decision** on `s` is an event when `s.author = ?1`, `s.status IN ('accepted', 'declined')` and `s.decided_by <> ?1`. It's unread when `s.decided_at > IFNULL(r.read_at, '')`.

- [ ] **Step 1: Write the failing tests** (`support::review` seeds Aiko, Ben, Keiko and Martin, plus `suggest_en`-style helpers copied from `inbox_api.rs`). Pass explicit timestamps by calling the store where order matters, or bump `T0`-based strings.
  - `the_author_hears_about_replies_and_decisions`: Aiko suggests. Ben comments, and Keiko accepts with a reply. Aiko's `/api/replies` has 3 events, newest first: Keiko's reply comment, `accepted` by "Keiko", and Ben's comment. `unread` is 3.
  - `a_commenter_hears_only_what_came_after_their_comment`: Aiko suggests, then Ben comments, Keiko comments, Ben comments again, and Aiko replies. Ben's unread events: only Aiko's reply.
  - `nothing_you_did_yourself_is_an_event`: Keiko accepts Aiko's suggestion with a reply. Keiko's replies are empty. A withdrawn suggestion gives its author no event.
  - `marking_read_clears_the_count`: `POST /api/replies/read {"ids":[id]}`, then `unread` is 0 and the events stay in the list with `unread: false`. `{"all": true}` clears several threads. `{}`, `{"ids": []}` and 201 ids each get 400.
  - `an_uninvolved_person_hears_nothing`: Martin, who didn't write or comment, has no events for Aiko's thread.
  - `a_long_comment_is_cut_in_the_list`: a 300-character comment comes back as 141 characters ending in `…`.
- [ ] **Step 2: Run them.** `cargo test --test replies_api`. Expected: FAIL (404 on the routes).
- [ ] **Step 3: Implement** the SQL, the store methods, the two handlers and the routes, following the interfaces above. Cut the body in Rust by characters, not bytes.
- [ ] **Step 4: Run them.** `cargo test --no-fail-fast`, `cargo fmt --check` and both Clippy runs. Expected: all pass.
- [ ] **Step 5: Commit.** `review-api: replies and marking threads read`

### Task 3: The replies store, the bell and the Replies page

**Files:**
- Create: `review/web/src/lib/replies.svelte.ts`, `review/web/src/lib/RepliesBell.svelte`, `review/web/src/lib/ReplyList.svelte`, `review/web/src/routes/replies/+page.svelte`, `review/web/src/lib/replies.test.ts`
- Modify: `review/web/src/lib/api.ts`, `review/web/src/lib/SiteHeader.svelte`, `review/web/src/routes/+layout.svelte`, `review/web/src/dev/mock-review.ts`, `review/web/src/csp.test.ts` (add `replies.html`), `review/web/src/lib/site-header.test.ts`

**Interfaces:**
- Consumes: the routes from Task 2.
- Produces:
  - `api.ts`: `type Reply`, matching Task 2. `getReplies(): Promise<{ unread: number; replies: Reply[] }>`, `markRead(ids: number[])` and `markAllRead()`, both returning `{ unread: number }`.
  - `replies.svelte.ts`, a module singleton: `export const replies = { unread: number, list: Reply[], loaded: boolean, refresh(): Promise<void>, read(id: number): void, readAll(): Promise<void> }`, state through `$state`. `read` batches ids within one microtask into a single `markRead`, then updates `unread` from the answer and flips those events' `unread` locally. Errors leave the state as it was: no throw, no message.
  - `replyText(r: Reply): string`, the line a list shows:
    - `"Ben replied"` for a comment;
    - `"Keiko accepted your suggestion"` or `"Keiko declined your suggestion"` for a decision.
  - `groupReplies(list: Reply[]): { fresh: Reply[]; earlier: Reply[] }` splits by `unread`.
  - `<RepliesBell />`:
    - Draws a bell (inline SVG, `aria-hidden`) and a red count when `unread > 0`, labelled `"Replies, N new"` or `"Replies"`.
    - Desktop: a `<details>` panel with up to 8 new replies (`ReplyList`), a **Mark all read** button, and a "See all replies" link to `/replies`.
    - Phone: a plain link to `/replies`, toggled by CSS at 720 px, like the account menu.
  - `<ReplyList replies readings />`: each reply as a link to `suggestionHref(reply)`, showing `replyText`, the item title through `Japanese`, the cut body in quotes, and the date.
  - `/replies` page: an `h1` "Replies", then "New" (with a **Mark all read** button) and "Earlier" groups. Empty: "No replies yet. When someone answers your suggestion or note, it shows up here."

- [ ] **Step 1: Write the failing tests** in `replies.test.ts`:
  - `replyText` for each of the three kinds.
  - `groupReplies` splits by `unread`.
  - **`a_failed_load_shows_no_count`**: with `fetch` stubbed to reject (the pattern in `api.test.ts`), `replies.refresh()` resolves and leaves `unread` 0 and `loaded` false.
  - `read` batching: `read(1); read(2)` in one tick sends one POST with `ids: [1, 2]`.
  - Render tests (`svelte/server`): `RepliesBell` shows the red count element with text `3` and the label "Replies, 3 new" when `unread` is 3, and no count element at 0. `ReplyList` links to `suggestionHref(...)` and shows `"Ben replied"`.
  - In `site-header.test.ts`: the header renders the bell for a signed-in user and not when signed out.
- [ ] **Step 2: Run them.** `cd review/web && npx vitest run src/lib/replies.test.ts src/lib/site-header.test.ts`. Expected: FAIL.
- [ ] **Step 3: Implement.** In `+layout.svelte`, call `replies.refresh()` once `me` is known and in `afterNavigate`. Put the bell in `SiteHeader` before the account links, on desktop and phone. The mock serves `/replies` and `/replies/read` from its in-memory suggestions and comments, using the same rule as Task 2.
- [ ] **Step 4: Run them.** `npm run check && npx vitest run --exclude src/csp.test.ts && npm run build && npm run test:csp`. Expected: all pass.
- [ ] **Step 5: Commit.** `review-web: replies bell, panel and page`

### Task 4: Home section, thread marker and marking read

**Files:**
- Modify: `review/web/src/lib/HomeView.svelte`, `review/web/src/routes/+page.svelte`, `review/web/src/lib/SuggestionCard.svelte`, `review/web/src/lib/api.ts` (`Suggestion.last_read`, `Comment.mine`)
- Test: `review/web/src/lib/home-view.test.ts`, `review/web/src/lib/suggestion-card.test.ts`, `review/web/src/lib/replies.test.ts`

**Interfaces:**
- Consumes: `replies` and `ReplyList` (Task 3); `last_read` and `Comment.mine` (Task 1).
- Produces:
  - `HomeView` gets a `replies: Reply[]` prop (the new ones). With any:
    - desktop: a "New replies" section of up to 3 (`ReplyList`) with "See all replies";
    - phone: a one-line banner link to `/replies`, reading "1 new reply" or "N new replies".
    - Both sit after the greeting, before the queues. Nothing renders when the list is empty.
  - `firstNew(s: Suggestion): number`, in `replies.svelte.ts`: the index of the first comment that isn't `mine` and is newer than `s.last_read`, or `-1`. It's also `-1` when `last_read` is null, which means the viewer isn't in the thread.
  - `SuggestionCard` draws `<p class="new-since" role="separator">New since your last visit</p>` in `--red` above the comment at `firstNew(s)`. On mount, it calls `replies.read(s.id)` when `firstNew(s) >= 0`, or when the viewer wrote it, it's decided, and `decided_at > last_read`.

- [ ] **Step 1: Write the failing tests.**
  - `firstNew`: `-1` for null `last_read`; skips `mine` comments; returns the index of the first newer one.
  - `suggestion-card.test.ts`: with `last_read` between two comments, the render puts "New since your last visit" after the first comment's body and before the second's. With `last_read` after both, there's no marker.
  - `home-view.test.ts`: with two new replies, the section "New replies" and the banner text "2 new replies" render. With none, neither does.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.** Home passes `replies.list.filter((r) => r.unread)`. Mark read from the card with `onMount`, so server render tests don't call it.
- [ ] **Step 4: Run them.** The full web check from Task 3. Then a browser check with the dev mock:
  - as Martin (owner), comment on Aiko's seeded suggestion;
  - restart with `MOCK_ROLE=reviewer` (Aiko): the bell shows 1, Home shows the section, and opening the item shows the red line;
  - the count drops to 0 after the visit.
  The mock needs a seeded suggestion by Aiko; add one if it has none.
- [ ] **Step 5: Commit.** `review-web: new replies on Home, the new-since line, and reading a thread`

### Task 5: Docs

**Files:**
- Modify: `review/README.md` (Reviewing: replies; Deploying: migration 0008), the spec's Reply alerts section (an "As built" note)

- [ ] **Step 1: README.**
  - Under Reviewing: who is told, the bell and Replies page, and that visiting a thread marks it read.
  - Under Deploying: run migration `0008_thread_reads.sql` (`npm run migrate`) just before or right after merging. Until it runs, `/api/replies` fails and the bell stays empty; every other page works.
- [ ] **Step 2: Spec "As built"**: events are computed, not stored; the 50-event window; the 140-character cut; pre-deploy activity is seeded as read; second opinions and course events are left for steps 6 and 7.
- [ ] **Step 3: Check and commit.** `make review-test` and the Clippy runs. Expected: pass. Commit: `docs: reply alerts in the review README and the polish spec`
