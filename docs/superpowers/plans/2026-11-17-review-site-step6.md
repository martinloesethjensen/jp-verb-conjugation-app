# Review site step 6: second opinions and Your contributions — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Teachers and the owner can ask a colleague for a second opinion on an item's open suggestions, conflicting suggestions show side by side with "they disagree" and accepting one declines the others; and every reviewer gets a Your contributions page that groups their changes by the signed data release they shipped in.

**Architecture:** Two independent parts, each its own PR. **Part A** (second opinions) adds an `opinion_requests` table (migration 0011), four `/api/opinion*` routes, a `waiting` inbox status, decline-the-others in `/api/decide`, and three new reply events that reuse `thread_reads` through an anchor suggestion. **Part B** (contributions) adds a `data_releases` table and `suggestions.released_in`/`before_json` (migration 0012). A finished load of a *newer* signed file version records the release and claims every exported suggestion of that dataset. `GET /api/contributions` and a `/contributions` page read it. The site learns about a release only from a signed load, so nothing changes in `make review-pull`, `make data-release` or the signing scripts.

**Tech Stack:** Rust Cloudflare Worker (`worker` crate, D1; tests run natively on an in-memory SQLite store that applies the same migrations and SQL), SvelteKit 3 / Svelte 5 static site, vitest, svelte-check.

**Spec:** `docs/superpowers/specs/2026-11-08-review-site-polish-design.md` (Principles; Roles; Screens rows Inbox, Second opinion, Your contributions; Reply alerts; Build order step 6). Canvas boards: *Inbox · desktop, with second opinion (click Ask)*, *Inbox · phone*, *Your contributions · desktop (try the filters)*, *Your contributions · phone* (https://claude.ai/artifact/NKfDy5o7H7BbneLj9y5kzF).

## Base and ordering

- **Step 5 is not on `origin/main`** (checked 2026-11-17). Settings and onboarding live on local branch
  `claude/review-settings` (migration 0009). `origin/main` has step 3b (`0010_native_role.sql`, `Need::Decider`,
  `review/api/src/japanese.rs`). This worktree's branch merged step 5 locally, and merging `origin/main` into it
  conflicts in `review/web/src/dev/mock-api.ts`.
- **This plan expects step 5 merged into `main` first.** Start each part from a fresh `origin/main` that has
  both 0009 and 0010. Names below follow `main` after 3b (`Need::Decider`, `Role::can_decide`), not step 5's
  pre-3b `Need::Teacher`.
- **Files step 5 also touches:**
  - `review/web/src/routes/inbox/+page.svelte` (its `<Tip id="inbox">`);
  - `review/web/src/lib/SiteHeader.svelte` (Settings link);
  - `review/web/src/dev/mock-api.ts` and `mock-review.ts`;
  - `review/web/src/routes/settings/+page.svelte` (Part B links to it for "Change how you're credited");
  - `review/README.md`.
  Step 6 adds no keyboard shortcuts.
- **Migrations:** Part A `0011_opinions.sql`, Part B `0012_releases.sql`. If Part B merges first, swap the
  numbers. Each is additive (new tables and columns, no table rebuild).
- **Two PRs:** A and B share only `SiteHeader.svelte` (B only), `README.md` and the spec's "As built" notes, so
  they can be built in either order or in parallel worktrees.

## Global Constraints

- Light only (`color-scheme: light`); no dark mode.
- Red (`--red`) only for seals, red-pen corrections, unread counts, the "new since your last visit" line and open-suggestion progress. Nothing decorative is red.
- Green (`--green`) only for "Live in the app" and saved states.
- Ink is the one strong colour: primary buttons ink-filled pills; secondary ink-outlined pills; tertiary underlined muted links.
- Furigana on every kanji, through `Japanese.svelte`.
- Touch targets ≥ 44 px (48 px in phone action bars); text ≥ 4.5:1.
- Strict CSP: no inline `style` attributes or `<style>` injected at runtime; component `<style>` blocks only (`npm run test:csp` checks the build).
- Nothing reaches the app without review; only the owner signs data releases, locally (`make data-release`). Never run `make data-release`, `make sign-commit` or `make review-pull`, and never touch `data/`.
- Nobody decides their own suggestion. Teachers decide like the owner; natives decide only Japanese-field changes (`japanese.rs`).
- Copy says "a teacher or Martin decides", never "Martin decides".
- Every write inserts its `audit_log` row in the same D1 batch (see the `ReviewStore` doc comment).
- Emails never leave the Worker for non-owners: teachers pick people by an opaque number, never by email.
- `cd review/api && cargo test` for the Worker, `cd review/web && npm run check && npm test && npm run build && npm run test:csp` for the pages; `make review-test` runs all of them.

## Decisions this plan makes (from the spec)

1. **Who may ask:** teachers and the owner (spec Roles: "Ask for a second opinion: Teacher yes, Owner yes, Native no, Reviewer no").
   Checked in the handler with a new `Role::can_ask_opinion()` (`Admin | Teacher`) on routes that need `Need::Decider`.
2. **Who may be asked, natives included:** any active person other than the asker and the authors of the item's
   open suggestions. That covers reviewers, natives and teachers. The spec says the asker "picks another reviewer"
   and that "the opinion is advice", so answering needs no deciding power.
3. **One open request per item** (`dataset, kind, item_id`), the same unit the inbox groups by. It needs at
   least one open suggestion on the item.
4. **Answer:** the person picks one of the open suggestions or "Neither", and writes a reason (required for
   Neither, optional otherwise). The answer stays visible to everyone on the item page and in the inbox.
5. **Waiting** means unanswered and not cancelled, with an open suggestion still on the item. Such groups show
   under *Waiting for an opinion* and not under *Open*. An answered request sends the group back to *Open* with
   the answer shown. Deciding every open suggestion ends the wait: nothing is stored, the condition just stops
   holding. Answering an item with no open suggestion is refused with "Already decided".
6. **Deciding while waiting is allowed** for anyone who may decide that suggestion. The owner confirmed this
   (owner decision 1).
7. **Disagreement:** an item with two or more open `change`/`delete` suggestions. Accepting one declines the
   others that the decider may decide: not their own, and for a native only the Japanese-only ones. Each declined
   suggestion gets a comment by the decider: `Declined: {author}'s suggestion was accepted instead.` Suggestions
   the decider may not decide stay open.
8. **Events reuse `thread_reads`.** A request stores `anchor_id`, the lowest open suggestion id on the item when
   it was asked. Its events point at that thread, and reading that thread reads them.
9. **Release identity:** the SHA-256 of the signed `manifest.json` bytes. A release is labelled `YYYY.MM.DD`
   from the UTC date the site first loaded it, with a `-2`, `-3` suffix for a second release on one day. The
   canvas shows "Release 2026.11.07".
10. **Claiming:** a finished load of file *F* claims a suggestion when *F*'s new version is strictly newer than
    the one loaded before. The suggestion must have `dataset = F`, `exported_at` set, `released_in` empty and
    `action <> 'note'`. Loads only succeed against a signed manifest, and `main`'s manifest is unsigned between
    a merged review-pull PR and the next `make data-release`. So the first newer load after "Mark exported" is
    the release that carried it.
11. **Before text for shipped changes:** `suggestions.before_json`, written when a suggestion is accepted (the
    target's JSON at that moment). Older accepted suggestions have none, and the page shows their proposed text
    without strike-through.

## Owner decisions (2026-11-17)

1. **Deciding while a second opinion is pending:** "Yes, deciding ends the wait". Teachers and natives
   decide as usual, and the request then ends (decision 6).
2. **Suggestions exported before this ships:** the "Earlier releases" group. Migration 0012 files every
   suggestion exported before its dataset's last load there, shown live; the rest wait for the next release.
3. **"Mark exported" after the release:** "Warning is enough". The Export page says "Mark exported before
   your next `make data-release`" (Task B4); no extra button.

## Review Focus

- **Item changes between asking and answering.** A suggestion is withdrawn, or a teacher decides the item while
  the request waits. The asked person's card should say "Already decided" rather than offer a dead form. (Task
  A2 `answering_a_decided_item_is_refused`, Task A7 card state.)
- **Someone asked who is also an author.** Asking an author of an open suggestion on the item is refused. So is
  asking yourself or an inactive person. (Task A2.)
- **Opinion events reach the right people once.** The asked person, the authors and the asker are each told
  about the right event, never about their own action. Reading the anchor thread clears all of them. (Task A4.)
- **Re-loading a version claims nothing.** A repeat load of the same version, or GitHub serving the old
  manifest and signature from cache, must not mark exported suggestions as released. (Task B1
  `reloading_the_same_version_claims_nothing`.)
- **Native accepts in a mixed disagreement.** A native accepts a Japanese-only change while an English change
  is open on the same item. The English change must stay open for a teacher. (Task A3
  `a_native_accepting_leaves_changes_they_cannot_decide_open`.)

---

## Part A — Second opinions (PR 1, migration 0011)

### Task A1: `opinion_requests` table and store methods

**Files:**
- Create: `review/api/migrations/0011_opinions.sql`
- Modify: `review/api/src/review_store.rs` (types, SQL constants, trait), `review/api/src/d1.rs` (`impl ReviewStore for D1Store`), `review/api/tests/support/sqlite.rs` (`impl ReviewStore for SqliteStore`), `review/api/src/store.rs` (`Role::can_ask_opinion`)
- Test: `review/api/tests/opinions_api.rs` (store-level tests here; route tests join in A2)

**Interfaces:**
- Produces (Rust, `review_store.rs`):
  ```rust
  pub struct OpinionRequest {
      pub id: i64, pub dataset: String, pub kind: String, pub item_id: String, pub entry_id: String,
      pub item_title: String, pub anchor_id: i64,
      pub asked_by_name: String, pub asked_of_name: String,
      pub mine_asked: bool, pub mine_to_answer: bool,
      pub question: String, pub created_at: String,
      pub answered_at: Option<String>, pub pick: Option<i64>, pub answer: String,
      pub cancelled_at: Option<String>,
      /// Unanswered, not cancelled, and the item still has an open suggestion.
      pub waiting: bool,
  }
  pub struct Candidate { pub user: i64, pub name: String, pub role: String, pub seen: Option<String> }
  // trait ReviewStore gains:
  async fn opinion_candidates(&self, t: &Target, viewer: &str) -> Result<Vec<Candidate>, StoreError>;
  async fn user_by_number(&self, user: i64) -> Result<Option<(String, String, bool)>, StoreError>; // (email, role, active)
  async fn ask_opinion(&self, t: &Target, asked_of: &str, question: &str, asker: &str, now: &str) -> Result<i64, StoreError>;
  async fn opinion(&self, id: i64, viewer: &str) -> Result<Option<OpinionRequest>, StoreError>;
  async fn cancel_opinion(&self, id: i64, asker: &str, now: &str) -> Result<(), StoreError>;
  async fn answer_opinion(&self, id: i64, pick: Option<i64>, body: &str, by: &str, now: &str) -> Result<(), StoreError>;
  async fn opinions_for_entry(&self, dataset: &str, entry_id: &str, viewer: &str) -> Result<Vec<OpinionRequest>, StoreError>;
  async fn opinions_for_targets(&self, targets: &[Target], viewer: &str) -> Result<Vec<OpinionRequest>, StoreError>;
  ```
- `store.rs`: `impl Role { pub fn can_ask_opinion(self) -> bool }`, true for `Admin` and `Teacher`.

- [ ] **Step 1: Write the migration.** `opinion_requests(id INTEGER PRIMARY KEY AUTOINCREMENT, dataset, kind, item_id, entry_id, item_title, anchor_id INTEGER NOT NULL REFERENCES suggestions(id), asked_by TEXT NOT NULL, asked_of TEXT NOT NULL, question TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, answered_at TEXT, pick INTEGER REFERENCES suggestions(id), answer TEXT NOT NULL DEFAULT '', cancelled_at TEXT)`. Add a partial unique index `opinion_open ON opinion_requests (dataset, kind, item_id) WHERE answered_at IS NULL AND cancelled_at IS NULL`, plus indexes on `asked_of` and `asked_by` for the replies query. Use the header comment style of 0008.

- [ ] **Step 2: Write failing store tests** in `tests/opinions_api.rs`, using `seeded()` and the `suggest_en` helper pattern from `inbox_api.rs`:
  - `a_second_open_request_on_one_item_is_a_conflict`: `ask_opinion` twice on one target → the second returns `Err(StoreError::Conflict)`.
  - `cancelling_needs_the_asker_and_an_open_request`: another user → `Conflict`; after cancel, a second cancel → `NotFound`.
  - `answering_records_the_pick_and_stops_waiting`: after `answer_opinion(id, Some(sid), "", BEN, T0)`, `opinion(id, MARTIN)` has `pick == Some(sid)`, `waiting == false`, `answered_at == Some(T0)`.
  - `deciding_every_open_suggestion_ends_the_wait`: decide the only open suggestion, then `opinion(id).waiting == false` with `answered_at == None`.
  - `candidates_put_people_who_have_not_seen_the_item_first`: AIKO approved the target, BEN didn't → BEN comes before AIKO, and AIKO's `seen == Some("approved")`. Neither the viewer nor the suggestion's author is listed.

- [ ] **Step 3: Run them** to see them fail: `cd review/api && cargo test --test opinions_api`. Expected: compile errors for the missing methods.

- [ ] **Step 4: Implement.** Put the SQL constants in `review_store.rs`, shared by D1 and SQLite as the existing ones are:
  - `ask_opinion` inserts with `WHERE NOT EXISTS` an open request. Zero rows changed → `Conflict`.
    `anchor_id` is `MIN(id)` of the item's open suggestions.
  - Every write adds an audit row: `opinion.ask`, `opinion.cancel` or `opinion.answer`.
  - `ask_opinion` and `answer_opinion` also upsert `thread_reads` on the anchor for the writer (`UPSERT_READS`),
    as comments do.
  - Candidates: `users.rowid AS user`, active users only. `seen` is the first of `approved`, `suggested` or
    `commented` that applies on the target. Order: unseen first, then by display name.

- [ ] **Step 5: Run the tests** and see them pass: `cargo test --test opinions_api`.

- [ ] **Step 6: Commit.** `git add review/api && git commit -m "review-api: opinion_requests (migration 0011) and their store methods"`

### Task A2: `/api/opinion*` routes and their rules

**Files:**
- Create: `review/api/src/opinion_routes.rs`
- Modify: `review/api/src/app.rs` (routes, `Handler` variants), `review/api/src/lib.rs` (`mod opinion_routes`), `review/api/src/review_routes.rs` (`GET /api/review` response gains `opinions`)
- Test: `review/api/tests/opinions_api.rs`

**Interfaces:**
- Consumes: A1's trait methods and `Role::can_ask_opinion`.
- Produces (HTTP, all JSON):
  - `GET /api/opinion/candidates?dataset&kind&id` (`Need::Decider`, asker roles only) → `{ "candidates": [{ "user": i64, "name", "role", "seen": "approved"|"suggested"|"commented"|null }] }`
  - `POST /api/opinion/ask` `{ dataset, kind, id, user: i64, question }` → `201 { "id": i64 }`
  - `POST /api/opinion/cancel` `{ id }` → `200 {}`
  - `POST /api/opinion/answer` `{ id, pick: i64|null, body }` (`Need::Reviewer`) → `200 {}`
  - `GET /api/review` adds `"opinions": [OpinionJson]` for the entry. OpinionJson holds every `OpinionRequest`
    field except the emails.

- [ ] **Step 1: Write failing route tests:**
  - `only_teachers_and_the_owner_may_ask`: AIKO (reviewer) → 403. A native (add one to the test with
    `Role::Native`) → 403. KEIKO → 201. MARTIN → 201 on another item.
  - `asking_needs_an_open_suggestion_on_the_item` → 409 `nothing open to give an opinion on`.
  - `the_asked_person_must_be_someone_else_and_not_an_author`: three cases, each 400. Yourself →
    `you can't ask yourself`. The author of an open suggestion → `they wrote one of these suggestions`. An
    inactive user → `no such reviewer`.
  - `a_native_or_reviewer_can_be_asked_and_answer`: KEIKO asks BEN (reviewer). BEN answers `{pick: null, body: "Both read oddly."}` → 200, and `GET /api/review` shows the answer to AIKO.
  - `neither_needs_a_reason`: `{pick: null, body: "  "}` → 400 `say why neither works`.
  - `the_pick_must_be_an_open_suggestion_on_the_item`: another item's suggestion id → 400.
  - `only_the_asked_person_answers`: AIKO answering BEN's request → 403.
  - `answering_a_decided_item_is_refused`: MARTIN decides the only open suggestion, then BEN answers → 409 `already decided`.
  - `only_the_asker_cancels`: MARTIN cancelling KEIKO's request → 403. KEIKO → 200.
  - `the_question_and_answer_are_capped`: longer than `proposal::MAX_TEXT` → 400.

- [ ] **Step 2: Run them** to see them fail: `cargo test --test opinions_api`.

- [ ] **Step 3: Implement `opinion_routes.rs`** with `candidates`, `ask`, `cancel` and `answer`, following
  `reply_routes.rs`/`review_routes.rs` (`tri!`, `ok`, `unavailable`, `parse` with `deny_unknown_fields`).
  Trim the question and body. `ask` resolves `user` with `user_by_number` and stores the email. Map
  `StoreError::Conflict` from `ask_opinion` to 409 `someone was already asked about this item`.

- [ ] **Step 4: Run the tests** and see them pass: `cargo test --test opinions_api`, then all of them: `cargo test`.

- [ ] **Step 5: Commit.** `git commit -am "review-api: ask, cancel and answer second opinions"`

### Task A3: Inbox `waiting`, opinions on inbox rows, and decline-the-others

**Files:**
- Modify: `review/api/src/review_store.rs` (`SELECT_INBOX_*` constants; `decide` gains `also_decline: &[i64], reason: &str`), `review/api/src/d1.rs`, `review/api/tests/support/sqlite.rs`, `review/api/src/review_routes.rs` (inbox handler and decide handler)
- Test: `review/api/tests/inbox_api.rs`

**Interfaces:**
- Consumes: `opinions_for_targets` (A1).
- Produces:
  - `GET /api/inbox?status=open|waiting|accepted|declined`. `open` leaves out suggestions whose item is waiting;
    `waiting` is exactly those. Each suggestion gains `"opinion": OpinionJson | null`: the item's open request, or
    else its newest answered one, never a cancelled one.
  - `POST /api/decide` with accept → response gains `"declined": [i64]`.
  - `ReviewStore::decide(&self, id, accept, edit, by, now, also_decline: &[i64], reason: &str)`. Every
    `also_decline` id that is still open becomes `declined` by `by` at `now` and gets a comment `reason`, all in
    the same batch, with audit `suggestion.decline`.

- [ ] **Step 1: Write failing tests** in `inbox_api.rs`:
  - `a_waiting_item_leaves_open_for_waiting`: two suggestions on one example. KEIKO asks BEN → `inbox("open")` is empty and `inbox("waiting")` has both, each with `opinion.asked_of_name == "Ben"`.
  - `an_answered_opinion_returns_the_item_to_open_with_the_answer`.
  - `accepting_one_of_two_declines_the_other_with_a_reason`: AIKO and BEN each suggest; MARTIN accepts AIKO's →
    `declined == [ben_id]`. BEN's suggestion is `declined` by MARTIN, and its comments end with
    `Declined: Aiko's suggestion was accepted instead.`
  - `accepting_never_declines_the_deciders_own_suggestion`: KEIKO and AIKO each suggest; KEIKO accepts AIKO's → KEIKO's own stays open.
  - `a_native_accepting_leaves_changes_they_cannot_decide_open`: one Japanese-only `jp` change and one `en` change on one item. The native accepts the `jp` one → the `en` change stays open.
  - `notes_and_additions_are_not_declined`: a `note` on the same item stays open.

- [ ] **Step 2: Run them** to see them fail: `cargo test --test inbox_api`.

- [ ] **Step 3: Implement.**
  - The inbox handler fetches the opinions for the listed targets and attaches them by target key.
  - Decide-with-accept lists the other open `change`/`delete` suggestions on the same target, keeping those
    where the author isn't `by.email` and the decider may decide them. Reuse the per-suggestion check that 3b
    added for natives.
  - It passes those ids and the reason to `decide`. The reason names the accepted suggestion's `author_name`.
  - Update every existing `decide(` call site to pass `&[]` and `""`.

- [ ] **Step 4: Run the tests** and see them pass: `cargo test`.

- [ ] **Step 5: Commit.** `git commit -am "review-api: waiting for an opinion in the inbox; accepting one declines the others"`

### Task A4: Second-opinion reply events

**Files:**
- Modify: `review/api/src/review_store.rs` (`with_reply_events!`, `Reply.what` doc)
- Test: `review/api/tests/replies_api.rs`

**Interfaces:**
- Produces: `GET /api/replies` events whose `what` is one of `comment`, `accepted`, `declined`,
  `opinion_asked`, `opinion_answered` or `opinion_cancelled`, with `suggestion_id` = the request's `anchor_id`
  and `body` = the question or answer (cut to `MAX_REPLY_BODY`). `Reply` and `ReplyRow` gain
  `asked_of_name: String`: the asked person's display name on opinion events, empty on the others. Who gets
  which:
  - `opinion_asked`: the asked person, plus the authors of suggestions on the item that were open when it was
    asked (`created_at <= o.created_at`, status not `withdrawn`, and `decided_at` empty or later than
    `o.created_at`).
  - `opinion_answered`: the asker and those same authors.
  - `opinion_cancelled`: the asked person.
  - Never the person who acted. Unread when newer than the viewer's `thread_reads.read_at` for `anchor_id`.

- [ ] **Step 1: Write failing tests:**
  - `the_asked_person_and_the_authors_are_told_when_asked`: KEIKO asks BEN about AIKO's suggestion → BEN and AIKO
    each get one unread `opinion_asked`, with `by_name == "Keiko"`, `asked_of_name == "Ben"` and `body` = the
    question. KEIKO gets none.
  - `the_asker_and_authors_are_told_the_answer`.
  - `the_asked_person_is_told_of_a_cancel`.
  - `reading_the_anchor_thread_reads_opinion_events`: `POST /api/replies/read {ids:[anchor]}` → the unread count is 0.

- [ ] **Step 2: Run them** to see them fail: `cargo test --test replies_api`.

- [ ] **Step 3: Implement.** Add three `UNION ALL` branches to `with_reply_events!`. Each starts from
  `opinion_requests` through its `asked_of`/`asked_by` index, or from the viewer's own suggestions on the
  target for the authors, so nothing scans every request. Keep the column list and `rank`/`seq` ordering
  intact, and give opinion events `rank` 2.

- [ ] **Step 4: Run the tests** and see them pass: `cargo test`.

- [ ] **Step 5: Commit.** `git commit -am "review-api: second-opinion reply events"`

### Task A5: Web API types, mock and pure helpers

**Files:**
- Modify: `review/web/src/lib/api.ts`, `review/web/src/lib/replies.svelte.ts` (`replyText`), `review/web/src/dev/mock-review.ts` and `mock-api.ts`
- Create: `review/web/src/lib/opinions.ts`
- Test: `review/web/src/lib/opinions.test.ts`, `review/web/src/lib/replies.test.ts`

**Interfaces:**
- Produces (TS):
  ```ts
  export type Opinion = { id: number; anchor_id: number; asked_by_name: string; asked_of_name: string;
    mine_asked: boolean; mine_to_answer: boolean; question: string; created_at: string;
    answered_at: string | null; pick: number | null; answer: string; waiting: boolean };
  export type Candidate = { user: number; name: string; role: string; seen: 'approved' | 'suggested' | 'commented' | null };
  // api.ts: InboxSuggestion gains `opinion: Opinion | null`; the review response gains `opinions: Opinion[]`;
  // Reply['what'] gains 'opinion_asked' | 'opinion_answered' | 'opinion_cancelled'; getInbox takes 'waiting'.
  export const getCandidates: (t: { dataset: string; kind: string; id: string }) => Promise<Candidate[]>;
  export const askOpinion: (t: { dataset: string; kind: string; id: string }, user: number, question: string) => Promise<number>;
  export const cancelOpinion: (id: number) => Promise<void>;
  export const answerOpinion: (id: number, pick: number | null, body: string) => Promise<void>;
  // opinions.ts
  export function disagreement(items: InboxSuggestion[]): string | null;   // banner text or null
  export function seenNote(c: Candidate): string;                          // "hasn't seen this item" | "approved it earlier" | "suggested a change" | "commented"
  export function waitingLine(o: Opinion): string;                         // "Waiting for Haruka's opinion"
  ```
- `decide` in `api.ts` returns `{ declined: number[] }`.

- [ ] **Step 1: Write failing vitest tests:**
  - `disagreement`: null for one open change. For two open changes by Kenji and Yumi →
    `"Kenji and Yumi disagree. Accepting one declines the other."` For three by A, B and C →
    `"A, B and C disagree. Accepting one declines the others."` A note doesn't count, nor does an
    accepted suggestion.
  - `seenNote`: all four values.
  - `replyText`: `opinion_asked` → `Keiko asked for your opinion`, `opinion_answered` → `Ben gave a second opinion`,
    `opinion_cancelled` → `Keiko cancelled the request for your opinion`. When the viewer is an author rather than the
    asked person, `opinion_asked` reads `Keiko asked Ben for a second opinion` (A4's `asked_of_name`).
- [ ] **Step 2: Run them** to see them fail: `cd review/web && npx vitest run src/lib/opinions.test.ts src/lib/replies.test.ts`.
- [ ] **Step 3: Implement** the helpers, the API functions and the mock routes. The mock keeps requests in
  memory and follows A2's rules for asker, asked person and authors closely enough to try them under
  `MOCK_ROLE`.
- [ ] **Step 4: Run** `npm test && npm run check` and expect them to pass.
- [ ] **Step 5: Commit.** `git commit -am "review-web: second-opinion API, mock and helpers"`

### Task A6: Inbox UI — Waiting tab, disagreement banner, Ask panel

**Files:**
- Create: `review/web/src/lib/AskOpinion.svelte`, `review/web/src/lib/OpinionStatus.svelte`
- Modify: `review/web/src/routes/inbox/+page.svelte`, `review/web/src/lib/roles.ts` (`canAskOpinion(role)`)
- Test: `review/web/src/lib/roles.test.ts`, `review/web/src/lib/ask-opinion.test.ts` (render with `@testing-library/svelte` if step 5's tests use it, otherwise test the component's exported helpers)

**Interfaces:**
- Consumes: A5's API functions and helpers.
- Produces:
  - `canAskOpinion(role: Role): boolean`, true for `admin` and `teacher`.
  - `<AskOpinion target={{dataset, kind, id}} onasked={() => void} />`
  - `<OpinionStatus opinion={Opinion} suggestions={InboxSuggestion[]} oncancel={() => void} />`

- [ ] **Step 1: Write failing tests:** `canAskOpinion` for all four roles. For `AskOpinion`, after the
  candidates load the first one is preselected, the button reads `Ask {name}`, and a failed ask shows the
  Worker's message in `ErrorLine`.
- [ ] **Step 2: Run them** to see them fail: `npx vitest run src/lib/roles.test.ts src/lib/ask-opinion.test.ts`.
- [ ] **Step 3: Implement**, matching *Inbox · desktop*:
  - **Tabs:** `TABS` gains `['waiting', 'Waiting for an opinion']` between Open and Accepted. On phones the
    segmented row already scrolls (`.tabs-scroll`).
  - **Banner:** above a group's cards when `disagreement(group.items)` returns text. A `--well` panel with the
    two-arrow icon, `aria-hidden`.
  - **Cards side by side:** the existing cards, laid out with `grid-template-columns:
    repeat(auto-fit, minmax(280px, 1fr))`.
  - **Ask panel:** below the cards for `canAskOpinion` viewers, when the group has open suggestions and no
    waiting opinion. A radiogroup of 52 px people buttons (initial, name, role · `seenNote`), the optional
    question (`<label>` + input, 44 px) and an ink `Ask {name}` button.
  - **Waiting card:** `OpinionStatus` replaces the Ask panel while an opinion is waiting. A ring dot,
    `waitingLine`, `Asked {relative date}. It shows up in their Replies. {authors} are told too.`, and
    `Cancel the request` as a `.link` button, shown only when `mine_asked`.
  - **Answered:** `OpinionStatus` shows the answer, `{name} picked {author}'s suggestion` or
    `{name} thinks neither works`, with the reason.
  - After accepting, a group whose others were declined reloads like any decision does.
  - No inline styles: classes in the component's `<style>`.
- [ ] **Step 4: Run** `npm run check && npm test && npm run build && npm run test:csp` and expect all to pass. Then try it in the mock at 390 px and 1280 px wide with `npm run dev`.
- [ ] **Step 5: Commit.** `git commit -am "review-web: waiting for an opinion, they disagree, ask for a second opinion"`

### Task A7: The asked person answers on the item page

**Files:**
- Create: `review/web/src/lib/OpinionCard.svelte`
- Modify: `review/web/src/routes/item/+page.svelte`
- Test: `review/web/src/lib/opinion-card.test.ts`

**Interfaces:**
- Consumes: `answerOpinion`, `Opinion`, and the review response's `opinions`.
- Produces: `<OpinionCard opinion={Opinion} suggestions={Suggestion[]} onanswered={() => void} />`. Replies links already open `suggestionHref(anchor)`, so the card sits above the anchor's thread.

- [ ] **Step 1: Write failing tests:** for `mine_to_answer && waiting`, a radiogroup of the open suggestions
  (author and red-pen summary) plus `Neither`, a reason textarea, and `Send` disabled until a pick is made (and,
  for Neither, until there's a reason). For `mine_to_answer && !waiting && !answered_at`, the text
  `Already decided. Thanks anyway.` and no form. For others, the asker/answer status line only.
- [ ] **Step 2: Run them** to see them fail: `npx vitest run src/lib/opinion-card.test.ts`.
- [ ] **Step 3: Implement.** The card marks its anchor read when it shows something new, the same way thread
  cards do (`replies.svelte.ts`). The question shows in a `--paper` box like the canvas's comment boxes.
  Japanese inside goes through `Japanese.svelte`.
- [ ] **Step 4: Run** `npm run check && npm test && npm run build && npm run test:csp` and expect all to pass.
- [ ] **Step 5: Commit.** `git commit -am "review-web: answer a second opinion on the item page"`

### Task A8: Docs for Part A

**Files:** `review/README.md` (Reviewing › The inbox; Replies; Deploying: migration 0011), `docs/superpowers/specs/2026-11-08-review-site-polish-design.md` (add an "As built (step 6a, date)" note under Roles or Screens, and update the Reply alerts "As built" sentence about second-opinion events)

- [ ] **Step 1:** In the README, describe second opinions: who asks, who can be asked, Waiting for an opinion,
  cancel, and that the opinion is advice. Describe disagreement and accept-declines-the-others. Add the
  migration note in the existing Deploying style ("until it runs, `/api/inbox` fails…"; say exactly what fails).
- [ ] **Step 2:** Add the spec's As-built note, with the decisions above that differ from or sharpen the spec
  (natives and reviewers may be asked; the anchor thread; deciding ends the wait).
- [ ] **Step 3:** Run `make review-test` and expect it to pass.
- [ ] **Step 4: Commit.** `git commit -am "docs: second opinions in the review README and the polish spec"`

---

## Part B — Your contributions (PR 2, migration 0012)

### Task B1: Record releases at load and claim exported suggestions

**Files:**
- Create: `review/api/migrations/0012_releases.sql`
- Modify: `review/api/src/app.rs` (`published` also returns the manifest's SHA-256; `finish_load_with_keys` passes a `ReleaseClaim`), `review/api/src/store.rs` (`Store::finish_load` signature, `ReleaseClaim`), `review/api/src/d1.rs`, `review/api/tests/support/sqlite.rs`, `review/api/src/review_routes.rs` (accepting writes `before_json`)
- Test: `review/api/tests/stepped_load.rs`, `review/api/tests/releases.rs`

**Interfaces:**
- Produces:
  ```rust
  // store.rs
  pub struct ReleaseClaim { pub manifest_sha256: String, pub date: String /* YYYY.MM.DD, UTC */, pub newer: bool }
  async fn finish_load(&self, load: &SnapshotLoad, file: &SnapshotFile, json: Option<&str>,
                       release: &ReleaseClaim, actor: &str, now: &str) -> Result<(), StoreError>;
  ```
- The migration adds:
  - `data_releases(id INTEGER PRIMARY KEY AUTOINCREMENT, manifest_sha256 TEXT UNIQUE` (NULL only for the
    backfill row)`, label TEXT NOT NULL UNIQUE, first_loaded_at TEXT)`;
  - `suggestions.released_in INTEGER REFERENCES data_releases(id)` and `suggestions.before_json TEXT`.
- The backfill inserts one row `('Earlier releases', NULL)` when any suggestion qualifies. It points at that row
  every non-note suggestion whose `exported_at` is earlier than its dataset's `snapshot_files.imported_at`.

- [ ] **Step 1: Write failing tests** with `stepped_load.rs`'s `FakeSource` and own-key signing:
  - `a_newer_signed_load_records_the_release_and_claims_exported_suggestions`: an accepted suggestion on
    `verbs`, marked exported. Load verbs at a newer version on `2026-11-07T…` → `data_releases` has label
    `2026.11.07`, and the suggestion's `released_in` points at it.
  - `reloading_the_same_version_claims_nothing`: mark exported, then load the same version again →
    `released_in` stays NULL.
  - `only_the_loaded_dataset_is_claimed`: an exported `counters` suggestion stays unclaimed by a verbs load.
  - `notes_are_never_claimed`.
  - `every_file_of_one_release_shares_its_row`: load verbs, then grammar from the same manifest → one
    `data_releases` row.
  - `a_second_release_on_one_day_gets_a_suffix`: two manifests on one date → `2026.11.07` and `2026.11.07-2`.
  - `accepting_records_the_text_before` (in `inbox_api.rs`): after accept, `before_json` equals the target's JSON
    at decide time. A declined suggestion has none.
  - `the_backfill_files_earlier_exports_under_earlier_releases` (in `releases.rs`): build
    `SqliteStore::with_migrations_before("0012")`, insert one exported suggestion before the snapshot's
    `imported_at` and one after, then `apply_migrations_from("0012")`. The first is in "Earlier releases"; the
    second is NULL.
- [ ] **Step 2: Run them** to see them fail: `cargo test --test stepped_load --test releases --test inbox_api`.
- [ ] **Step 3: Implement.**
  - In `published`, hash the manifest bytes with `source.sha256`.
  - `finish_load_with_keys` sets `newer` from the snapshot that `not_older` already reads, true when there was
    none or its version is older.
  - The D1/SQLite `finish_load` adds two statements before the three cleanup statements, each guarded by the
    load row existing, like the others in that batch:
    - an `INSERT OR IGNORE` into `data_releases` that picks the label `date`, or `date-N` for the next free N;
    - when `newer`, the `UPDATE suggestions SET released_in = …` from decision 10.
  - Accepting stores `before_json` from the same `current` JSON the decide handler already reads.
- [ ] **Step 4: Run** `cargo test` and expect it to pass.
- [ ] **Step 5: Commit.** `git add review/api && git commit -m "review-api: data releases recorded at load (migration 0012), released_in and before_json"`

### Task B2: `GET /api/contributions`

**Files:**
- Create: `review/api/src/contribution_routes.rs`
- Modify: `review/api/src/review_store.rs` (`Contributions` types, SQL, trait method), `review/api/src/d1.rs`, `review/api/tests/support/sqlite.rs`, `review/api/src/app.rs`, `review/api/src/lib.rs`
- Test: `review/api/tests/contributions_api.rs`

**Interfaces:**
- Produces:
  ```rust
  async fn contributions(&self, viewer: &str) -> Result<Contributions, StoreError>;
  ```
  HTTP `GET /api/contributions` (`Need::Reviewer`) returns:
  ```json
  { "counts": { "approved": 0, "suggested": 0, "accepted": 0, "live": 0 },
    "credit": { "name": null, "role": "teacher" },
    "releases": [{ "label": "2026.11.07", "loaded_at": "…", "changes": [Change] }],
    "accepted": [Change], "waiting": [Change], "declined": [Change],
    "datasets": [{ "dataset": "verbs", "approved": 0, "suggested": 0 }] }
  ```
  `Change` has the inbox suggestion's fields (`id, action, dataset, kind, item_id, entry_id, parent_kind,
  parent_id, item_title, proposed, admin_edit, furigana, comment, created_at, decided_at`), plus `before`
  (`before_json` for accepted, the current item for open ones, else null), `replies` (comment count) and
  `reason` (`{ "by_name", "body" }`, the decider's newest comment, declined only).
- Counts:
  - `approved`: the viewer's `approvals` rows.
  - `suggested`: suggestions not withdrawn.
  - `accepted`: status accepted.
  - `live`: `released_in` set.
- Releases come newest first by id, with "Earlier releases" last. Each list is newest first.

- [ ] **Step 1: Write failing tests:**
  - `counts_and_groups_match_the_viewers_work`: AIKO has one open suggestion, one accepted and released, one
    accepted not exported, one declined with MARTIN's comment, and one withdrawn → `suggested == 4`,
    `accepted == 2`, `live == 1`. One release with one change, `accepted.len() == 1`, `waiting.len() == 1`,
    and `declined[0].reason.body` = the comment.
  - `nobody_sees_anyone_elses_contributions`: BEN's call has no AIKO rows.
  - `credit_shows_the_public_name_and_role`.
  - `per_dataset_counts`.
- [ ] **Step 2: Run them** to see them fail: `cargo test --test contributions_api`.
- [ ] **Step 3: Implement** with plain SELECTs, one per list, batched the way `entry_review` reads.
- [ ] **Step 4: Run** `cargo test` and expect it to pass.
- [ ] **Step 5: Commit.** `git commit -am "review-api: GET /api/contributions"`

### Task B3: The Your contributions page

**Files:**
- Create: `review/web/src/routes/contributions/+page.svelte`, `review/web/src/lib/contributions.ts`, `review/web/src/lib/ContributionRow.svelte`
- Modify: `review/web/src/lib/api.ts` (`Contributions`, `getContributions`), `review/web/src/lib/SiteHeader.svelte` (desktop nav and phone menu: "Your contributions" for everyone, before Settings), `review/web/src/dev/mock-review.ts`/`mock-api.ts`
- Test: `review/web/src/lib/contributions.test.ts`, `review/web/src/lib/site-header.test.ts`

**Interfaces:**
- Produces:
  ```ts
  export type ContributionFilter = 'all' | 'live' | 'waiting' | 'declined';
  export function filterCounts(c: Contributions): Record<ContributionFilter, number>; // waiting = accepted + waiting
  export function headline(c: Contributions): string;  // "3 of your changes are in the app." | "1 of your changes is in the app." | "None of your changes are in the app yet."
  export function releaseLine(r: Release, dateFormat: (iso: string) => string): string; // "7 November · 2 of your changes"
  export function tagFor(change: Change, group: 'release' | 'accepted' | 'waiting' | 'declined'): { text: string; tone: 'live' | 'next' | 'wait' | 'no' };
  ```
  `tagFor` gives `Live in the app`, `Next release` (for a note: `Accepted`), `Waiting` or `Declined`.

- [ ] **Step 1: Write failing tests** for the four helpers, with the canvas's numbers (7 / 3 / 3 / 1), and
  for "Earlier releases", which has no date: `releaseLine` gives `2 of your changes`. The header test: the
  "Your contributions" link appears for a reviewer and on the phone menu.
- [ ] **Step 2: Run them** to see them fail: `npx vitest run src/lib/contributions.test.ts src/lib/site-header.test.ts`.
- [ ] **Step 3: Implement the page** from *Your contributions · desktop/phone*:
  - **Top:** the `lbl` title, the headline and a 確認 seal with the viewer's name (`Seal.svelte`).
  - **Counts:** a 4-up row on desktop and 2×2 on phones. The accepted count is green only when it's above 0.
  - **Filter chips:** `FilterChips.svelte`, scrolling sideways on phones.
  - **Release sections:** `Release {label}` and `releaseLine`.
  - **Other sections:** "Accepted, in the next release", "Waiting for a decision" (with `{n} replies`, which
    links to the thread) and "Declined" (with the reason, `{by_name}:` in bold).
  - **Rows:** each uses `RedPen.svelte`, `before` → `admin_edit ?? proposed`, when `before` is present.
    Otherwise it shows the proposed fields plainly. A removal shows the struck sentence and its comment.
  - **Aside:** "Your credit in the app" (name or "Credited as a teacher", a role pill, and "Change how you're
    credited" linking to `/settings`) and "By data set" (a `dl`).
  - **Tags:** `Live in the app` is the only green. `Next release` is ink-outlined; Waiting and Declined are
    muted.
  - **Empty state:** "Nothing yet. Approve or suggest a change in any queue and it shows up here."
- [ ] **Step 4: Run** `npm run check && npm test && npm run build && npm run test:csp` and expect all to pass. Then try it in the mock at 390 px and 1280 px.
- [ ] **Step 5: Commit.** `git commit -am "review-web: Your contributions"`

### Task B4: Export page hint and docs for Part B

**Files:** `review/web/src/routes/admin/export/+page.svelte`, `review/README.md` (Exporting › Each time; Deploying: migration 0012; Reviewing: Your contributions), `docs/superpowers/specs/2026-11-08-review-site-polish-design.md` (As built step 6b)

- [ ] **Step 1:** Under "Mark ticked as exported", add the line `Mark exported before your next make data-release: the next newer load credits these changes to that release.`
- [ ] **Step 2:** In the README, add a step 5 to "Each time": after `make data-release` merges, load the
  published data, which records the release and moves exported changes to "Live in the app". Add the migration
  0012 deploy note and a Your contributions paragraph. The deploy note: until the migration runs, accepting a
  suggestion fails (`before_json`), loads fail at finish, and `/contributions` fails. Run it just before
  merging.
- [ ] **Step 3:** Add the spec's As-built note: release identity, claiming rule, `before_json`, the backfill.
- [ ] **Step 4:** Run `make review-test` and expect it to pass.
- [ ] **Step 5: Commit.** `git commit -am "docs: data releases and Your contributions"`
