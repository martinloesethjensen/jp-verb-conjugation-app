# Review site 6: export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Accepted work on the review site reaches `data/` through one owner command, `make review-pull`, which writes a fresh data branch, review stamps and a PR summary, without the site ever holding a credential that can change the repo.

**Architecture:**
- **Who gets credited:** every user gains a public role (`owner`, `teacher`, `native`) and an optional public name.
- **Stamps:** the owner stamps a fully approved counter or grammar point on the site. A pending stamp waits in a new `stamps` table.
- **Export endpoint:** a read-only `GET /api/export` is reachable only by an Access service token. It returns accepted, not yet exported suggestions and pending stamps, verbatim from D1.
- **All rewriting happens in Python, on the owner's Mac** (no Worker CPU limit there). A format-preserving JSON writer keeps `grammar.json`'s hand formatting.
- **After the PR merges,** the owner marks the batch exported on a new admin Export page.

**Tech Stack:** Rust (workers-rs, D1, the existing SQLite test store), SvelteKit 2 / Svelte 5 static pages, Python 3 standard library (`unittest`), Swift (VerbKit, one model change).

**Spec:** `docs/superpowers/specs/2026-10-27-data-review-site-design.md`. The parts this plan implements:
- "Exporting accepted work" and "Accepted additions";
- "Fits what exists: review stamps";
- answered questions 1, 2 and 4;
- Authentication item 5.

## Global Constraints

- **Signing:** the site never signs, and nothing in this plan runs `make sign-commit` or `make data-release`. A review-pull branch is an ordinary data PR: regenerated with `update_data.py`, unsigned. The owner signs batches with `make data-release` (AGENTS rule 8). This replaces spec step 6's "the owner signs (`make sign-commit`)".
- **Export access:** the export credential is an Access service token. Its client id and secret live only in the owner's macOS Keychain:
  - service `kotobatable-review-export`, accounts `client-id` and `client-secret`;
  - the Worker learns the token's AUD and client id from Cloudflare secrets `ACCESS_EXPORT_AUD` and `ACCESS_EXPORT_CLIENT_ID`.
- **The token reads one thing:** `GET /api/export` accepts the service-token identity and nothing else does. Export is read-only.
- **No secrets or private details in committed files:** no secret, AUD tag, team domain or email. A reviewer's email never leaves D1. Export and summaries carry the public role, plus the public name when the reviewer set one.
- **Stamps:**
  - Shape: `{"by": "owner"|"teacher"|"native", "on": "YYYY-MM-DD", "sha256": "<64 hex>", "name"?: "<1–40 chars>"}`. `name` is present only when the reviewer chose a public name.
  - Scope in this plan: counters and grammar points. Verbs, words and examples are plan 7.
- **Ranking for "most senior reviewer involved":** `owner` > `teacher` > `native`.
- **Display names:** public names follow the display-name rules (`MAX_DISPLAY_NAME` = 40, trimmed, not blank).
- **Hosting:** Workers Free, about 10 ms of CPU per request. Export is plain SELECTs, with no item rewriting in the Worker.
- **Pages:** CSP with no inline styles. Svelte 5 runes. Shared components and helpers over copies (`feedback-reusable-code`).
- **Migrations:** D1 migrations are run by the owner (`npm run migrate`). The new `0006` uses only `ALTER TABLE ... ADD COLUMN` and `CREATE`, with no table rebuild.
- **Commits** end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **The data on main moved on after the site last loaded it.** An item in the site's snapshot may no longer match the file being patched. Expected: `review-pull` compares each touched file's sha256 with the site's snapshot and stops with "load the published data on the site, then pull again", writing nothing. Test: Task 7 `test_refuses_when_main_is_ahead_of_the_site`.
2. **One batch changes an entry that already has a stamp, or that is being stamped.** Expected: an old stamp whose hash no longer matches is removed and reported ("needs a new review"). A stamp requested in this batch for an entry the batch also changes is skipped and reported, and is never written stale. Either way `update_data.py` passes. Tests: Task 6 `test_change_removes_a_stale_stamp` and `test_stamp_skipped_when_the_batch_changes_its_entry`.
3. **An item has an accepted change and an accepted removal, or a part is added under a usage that's also removed.** Expected: removals apply last, and a change or addition whose target or parent is gone by then is skipped and reported, never crashing. Test: Task 6 `test_change_and_removal_of_the_same_item`.
4. **The service token is used on any other endpoint, or a reviewer calls `/api/export`.** Expected: 403 everywhere else for the token, and 403 on export for any signed-in person, admin included. Test: Task 4 `the_export_token_reads_export_only`.
5. **`grammar.json` round trip.** Expected: writing an unchanged document reproduces the file byte for byte, and an edit changes only the lines of the edited object. Test: Task 5 `test_unchanged_grammar_round_trips` and `test_one_example_edit_changes_one_line`.

---

### Task 1: Stamps accept `native` and an optional public name

**Files:**
- Modify: `scripts/update_data.py:1773-1815` (`REVIEWERS`, `check_reviews`), `scripts/mark_reviewed.py`
- Modify: `schema/grammar.schema.json` and `schema/counters.schema.json` (`$defs.reviewStamp`)
- Modify: `review/api/src/data.rs:128-141` (`ReviewStamp`, `Reviewer`)
- Modify: `Packages/VerbKit/Sources/VerbKit/Models/ReviewStamp.swift`
- Modify: `docs/superpowers/specs/2026-10-27-review-status-design.md` (stamp shape)
- Test: `scripts/test_update_data.py`, `scripts/test_mark_reviewed.py`, `review/api/tests/data.rs`, `Packages/VerbKit/Tests/VerbKitTests/ReviewStampTests.swift` (create if absent)

**Interfaces:**
- Produces:
  - `update_data.REVIEWERS == ("owner", "teacher", "native")`;
  - `update_data.REVIEWER_RANK = {"owner": 0, "teacher": 1, "native": 2}`;
  - `mark_reviewed.stamp(entry, by, on, generated=(), name=None) -> dict`, a public version of `_stamp` that adds `"name"` only when `name` is given;
  - Rust `Reviewer::Native` and `ReviewStamp { name: Option<String> }`;
  - Swift `Reviewer.native` with `displayName` "a native speaker", and `ReviewStamp.name: String?`.

- [ ] **Step 1: Write the failing tests**
  - `test_update_data.py`:
    - `test_native_stamp_with_name_passes`: a counter stamped `{"by": "native", "name": "Aiko", ...}` with a matching hash gives no problems from `check_reviews`.
    - `test_stamp_name_must_be_short_text`: `"name": ""` and a 41-character name each give the problem `"<id>: review.name must be 1 to 40 characters"`.
    - `test_schema_accepts_native_stamp_with_name`: `schema_problems("counters", doc)` returns no problems for such a doc.
  - `test_mark_reviewed.py`, `test_name_is_written_only_when_given`: `stamp(entry, "native", "2026-11-07", name="Aiko")["name"] == "Aiko"`, and `"name" not in stamp(entry, "teacher", "2026-11-07")`.
  - `tests/data.rs`, `a_native_stamp_with_a_name_parses`: a counters file whose entry has `"review": {"by":"native","on":"2026-11-07","sha256":"<64 hex>","name":"Aiko"}` loads without error.
  - `ReviewStampTests.swift`: decoding that stamp gives `.native`, `name == "Aiko"` and `by.displayName == "a native speaker"`. A stamp without `name` decodes with `name == nil`.

- [ ] **Step 2: Run them, expect failures**

Run: `make test-py` and `cd review/api && cargo test --test data` and `make test-swift`.
Expected: the new tests FAIL. `native` is rejected and `name` is an unknown field or property.

- [ ] **Step 3: Implement**
  - Add `native` to the enums in the four places listed under Files, and an optional `name` string. In the schemas that's `"name": {"type": "string", "minLength": 1}`; the 40-character cap is checked in `check_reviews`, since the schema subset has no `maxLength`.
  - Keep `additionalProperties: false`.
  - `mark_reviewed.py` gains `--by native` (choices come from `REVIEWERS`) and `--name`.

- [ ] **Step 4: Run them, expect passes**

Run the same three commands.
Expected: all pass. `make data-check` still passes, since no data changed.

- [ ] **Step 5: Commit**

`git commit -m "Stamps: a native-speaker reviewer and an optional public name"`

---

### Task 2: Public role and public name for every user

**Files:**
- Create: `review/api/migrations/0006_export.sql`. It holds this task's columns plus Task 3's `stamps` table and Task 4's `exported_at`, so the owner migrates once.
- Modify: `review/api/src/store.rs` (`User`, SQL constants), `src/d1.rs`, `tests/support/sqlite.rs`, `src/app.rs`
- Modify: `review/web/src/lib/api.ts`, `review/web/src/routes/account/+page.svelte`, `review/web/src/routes/admin/+page.svelte`, `review/web/src/dev/mock-review.ts`
- Test: `review/api/tests/app.rs`, `review/api/tests/store.rs`, `review/web/src/lib/api.test.ts`

**Interfaces:**
- Produces:
  - Migration `0006_export.sql`:
    - `users.public_role TEXT NOT NULL DEFAULT 'native' CHECK (public_role IN ('owner','teacher','native'))`, then `UPDATE users SET public_role = 'owner' WHERE role = 'admin'`.
    - `users.public_name TEXT` (NULL means anonymous).
    - `suggestions.exported_at TEXT`.
    - `CREATE TABLE stamps (id INTEGER PRIMARY KEY AUTOINCREMENT, dataset TEXT NOT NULL, kind TEXT NOT NULL, item_id TEXT NOT NULL, entry_id TEXT NOT NULL, item_title TEXT NOT NULL, content_hash TEXT NOT NULL, by_role TEXT NOT NULL CHECK (by_role IN ('owner','teacher','native')), reviewer TEXT NOT NULL, created_by TEXT NOT NULL, created_at TEXT NOT NULL, exported_at TEXT)`.
    - `CREATE UNIQUE INDEX stamps_pending ON stamps (dataset, kind, item_id) WHERE exported_at IS NULL`.
  - Rust: `User { public_role: PublicRole, public_name: Option<String>, .. }`, with `enum PublicRole { Owner, Teacher, Native }` serialized lowercase.
  - Routes:
    - `/api/me` adds `public_role` and `public_name`.
    - `POST /api/me/public-name {public_name: string | null}` (Need::Reviewer). `null` or blank means anonymous.
    - `POST /api/admin/users/role {email, public_role}` (Need::Admin). `owner` is refused for anyone but an admin (400 "only the owner is credited as the owner").
  - Web:
    - `api.ts`: `setPublicName(name: string | null)` and `setPublicRole(email, role)`; `Me` and `User` gain both fields.

- [ ] **Step 1: Write the failing tests**
  - `tests/app.rs`:
    - `a_reviewer_chooses_a_public_name`: POST `{"public_name":"Aiko"}` returns 200; `/api/me` then has `public_name == "Aiko"` and `public_role == "native"`; POST `{"public_name":null}` makes it null again; a 41-character name gets 400.
    - `the_owner_sets_a_reviewers_public_role`: a teacher role is stored; a reviewer calling the route gets 403; `owner` for a reviewer gets 400.
  - `tests/store.rs`, `migration_0006_credits_the_admin_as_owner`: after applying migrations up to 0005, adding an admin and a reviewer, then applying 0006, the admin's `public_role` is `owner` and the reviewer's is `native`. Use `with_migrations_before` and `apply_migrations_from`.

- [ ] **Step 2: Run them, expect failures**

Run: `cd review/api && cargo test --test app --test store`
Expected: FAIL (404 for the new routes, and an unknown column).

- [ ] **Step 3: Implement the migration, store, routes and audit rows** (`user.public_name`, `user.public_role`), reusing `MAX_DISPLAY_NAME` validation.

- [ ] **Step 4: Pages**
  - **Account page:**
    - Add a "Name on published credits" control: "Stay anonymous (credited as <role wording>)" or "Use a name", with a text field.
    - Wording per role: owner "the owner", teacher "a teacher", native "a native speaker".
    - The help line says the name appears in the public repository's history.
  - **Admin reviewers list:** a role select per reviewer (Teacher, Native speaker). The owner's row shows "Owner" without a select.
  - **Mock:** answers both routes.

- [ ] **Step 5: Run `make review-test`, expect all green; commit**

`git commit -m "review: public role and public name for credits"`

---

### Task 3: The owner stamps a fully approved entry

**Files:**
- Modify: `review/api/src/review_store.rs` (SQL and trait: `stamp_for`, `add_stamp`, `withdraw_stamp`), `src/d1.rs`, `tests/support/sqlite.rs`
- Create: `review/api/src/stamp_routes.rs`
- Modify: `review/api/src/app.rs`, `review/api/src/review_routes.rs` (the review response)
- Modify: `review/web/src/lib/api.ts`, `review/web/src/lib/review.svelte.ts`, `review/web/src/routes/item/+page.svelte`, `review/web/src/dev/mock-review.ts`
- Test: `review/api/tests/stamp_api.rs` (create)

**Interfaces:**
- Consumes: Task 2's `users.public_role`, the `stamps` table.
- Produces:
  - `pub fn stampable(file: DataFile, kind: Kind) -> bool` in `stamp_routes.rs`. It's true only for `(Counters, Entry)` and `(Grammar, Entry)`; plan 7 extends it.
  - `POST /api/admin/stamp {dataset, id}` → 201 with the pending stamp, or 200 with the existing pending one.
  - `POST /api/admin/stamp/withdraw {dataset, id}` → 200.
  - `/api/review` gains `stamp: {by, name, reviewer_name, created_at} | null` and `stampable: bool`. `reviewer_name` is the site display name, for the owner's eyes.
  - Pending stamp JSON: `{id, dataset, kind, item_id, entry_id, item_title, content_hash, by, name}`, where `name` is the reviewer's current `public_name`.

Rules, in order, with the exact errors:
1. `!stampable` → 400 "only counters and grammar points take a stamp for now".
2. Any part of the entry (the entry row and every part row in `items` under it) lacks an approval at its current hash → 409 "every part needs an approval first".
3. An open suggestion on the entry, or an open addition under it → 409 "settle its open suggestions first".
4. A pending stamp exists → 200 with it.

The stamp names the most senior reviewer by role across all current approvals of the entry's parts. A tie goes to the earliest `created_at`. `content_hash` is the entry row's current `content_hash`, which equals `update_data.review_hash` for these files (see `items.rs` `excluded_from_entry_hash`).

- [ ] **Step 1: Write the failing tests** (`tests/stamp_api.rs`, seeded store, approvals made through the API):
  - `a_fully_approved_grammar_point_is_stamped_by_its_most_senior_reviewer`: a native approves every part, then a teacher approves one part. The admin's POST returns 201 with `by == "teacher"`, and `/api/review` shows the stamp.
  - `stamping_needs_every_part_approved`: one part without an approval gets 409 with the rule-2 message.
  - `stamping_waits_for_open_suggestions`: 409 with the rule-3 message.
  - `verbs_cannot_be_stamped_yet`: 400 with the rule-1 message.
  - `stamping_twice_returns_the_pending_stamp` (200, same id), and `a_reviewer_cannot_stamp` (403).
  - `withdrawing_a_stamp_frees_the_entry`: withdraw, then stamp again gives 201.

- [ ] **Step 2: Run, expect failures.** `cargo test --test stamp_api` → FAIL (404).

- [ ] **Step 3: Implement** the store functions, with shared SQL constants for both backends. Write `audit_log` rows `stamp.add` and `stamp.withdraw`. Withdrawal deletes the pending row, since the audit log keeps the history.

- [ ] **Step 4: Item page (admin only)**
  - On a stampable entry, show "Stamp as reviewed" under the entry's review bar, enabled when `stampable` and every part is approved. Otherwise show the reason from the 409.
  - A pending stamp shows as the existing seal style, with "Stamped for export: <role wording>, <public name or 'anonymous'>" and a "Withdraw stamp" link.
  - Reviewers see nothing new.
  - The mock answers both routes.

- [ ] **Step 5: `make review-test` green; commit** `git commit -m "review: the owner stamps a fully approved counter or grammar point"`

---

### Task 4: Export endpoint, export token and the admin Export page

**Files:**
- Modify: `review/api/src/access.rs` (`Claims.common_name`, `AccessConfig.export`, `Audience::Export`), `src/auth.rs` (`Need::Export`), `src/worker_glue.rs`, `src/app.rs`
- Create: `review/api/src/export_routes.rs`
- Modify: `review/api/src/review_store.rs`, `src/d1.rs`, `tests/support/sqlite.rs` (`export_batch`, `mark_exported`)
- Create: `review/web/src/routes/admin/export/+page.svelte`
- Modify: `review/web/src/routes/admin/+page.svelte` (link), `review/web/src/lib/api.ts`, `review/web/src/dev/mock-review.ts`, `review/web/csp.test.ts` (add `admin/export.html`)
- Test: `review/api/tests/export_api.rs` (create), `review/api/tests/access.rs`

**Interfaces:**
- Produces:
  - **Access config:**
    - `AccessConfig::with_export(self, aud: &str, client_id: &str) -> AccessConfig`, which sets `export: Some(ExportAccess { aud, client_id })` only when both are non-blank and `aud` differs from the other two AUDs.
    - `Claims.common_name: Option<String>`.
    - `Claims::audience` returns `Audience::Export` for the export AUD.
  - **Authorization:** `authorize` with `Need::Export` passes only when `audience == Export`, `email` is absent and `common_name == export.client_id`. The principal is `{email: "export", display_name: "export", role: Admin}`, which never touches `users`. Every other `Need` refuses `Audience::Export`.
  - **`GET /api/export`** (Need::Export) returns this JSON:
    ```
    { "files": { "<dataset>": "<snapshot sha256>", ... },
      "suggestions": [ { "id", "action", "dataset", "kind", "item_id", "entry_id", "parent_kind", "parent_id",
                         "item_title", "item", "editable", "furigana", "comment",
                         "credit": { "role", "name" }, "decided_at" } ],
      "stamps": [ <Task 3 pending stamp JSON> ] }
    ```
    - `suggestions` holds accepted ones with `exported_at IS NULL`, ordered by `id`.
    - `item` is `admin_edit_json` when set, else `proposed_json`; null for delete and note.
    - `editable` is set for a change and null otherwise: the names in `proposal::fields(file, kind)`, plus `"particle_blanks"` when that table has `jp`.
    - `credit` is the author's `public_role` and `public_name`.
    - `stamps` holds those with `exported_at IS NULL`.
  - **`GET /api/admin/export`** (Need::Admin): the same JSON, for the Export page.
  - **`POST /api/admin/exported {suggestions: [i64], stamps: [i64]}`** (Need::Admin): sets `exported_at = now` on those rows when they are still accepted or pending. Returns the new counts. Writes the audit row `export.mark`.

- [ ] **Step 1: Write the failing tests**
  - `tests/access.rs`, `export_config_needs_a_distinct_aud_and_a_client_id`: blank values, or an AUD equal to `aud` or `admin_aud`, leave `export` as `None`.
  - `tests/export_api.rs`. Mint tokens with the test support's signer, adding a `common_name` claim and the export AUD.
    - `the_export_token_reads_export_only`: the export token gets 200 on `/api/export`; 403 on `/api/items`, `/api/admin/inbox` and `/api/me`; and 403 on export with a wrong `common_name`. A signed-in admin and a reviewer get 403 on `/api/export`.
    - `export_lists_accepted_work_once`:
      - Accept a change with an owner edit, an addition and a delete; leave one suggestion open; add one stamp. Export lists exactly those 3 suggestions and 1 stamp.
      - The change's `item` is the owner's edit and its `editable` includes `"jp"` and `"particle_blanks"`.
      - `credit` has `role` and `name`, and no `@` appears anywhere in the body.
      - After `POST /api/admin/exported` with those ids, export lists nothing.
    - `marking_exported_skips_rows_that_are_not_accepted`: an open suggestion's id in the POST stays unexported.

- [ ] **Step 2: Run, expect failures.** `cargo test --test export_api --test access` → FAIL.

- [ ] **Step 3: Implement**
  - Read `ACCESS_EXPORT_AUD` and `ACCESS_EXPORT_CLIENT_ID` as secrets in `worker_glue.rs` (missing means export disabled; `/api/export` then answers 403).
  - `export_batch` is one SELECT per table. Reuse the existing `Suggestion` row mapping where it fits, joining `users` for the credit.

- [ ] **Step 4: The Export page** (`/admin/export`)
  - The list: one row per pending suggestion and stamp, grouped like the inbox, each with a checkbox ticked by default. Every row shows a "credited as …" line.
  - Below the list: the "Mark ticked as exported" button.
  - Help line: "After the review-pull PR merges, mark what it contained."
  - Empty state: "Nothing is waiting for export."
  - Reuse `suggestionHref` for links and `ENTRY_NAMES` and `groupTitle`, moving them into `labels.ts` and `targets.ts` if they are only in the inbox.

- [ ] **Step 5: `make review-test` green; commit** `git commit -m "review: read-only export for a service token, and the admin Export page"`

---

### Task 5: A format-preserving JSON writer

**Files:**
- Create: `scripts/json_preserve.py`
- Test: `scripts/test_json_preserve.py`

**Interfaces:**
- Produces: `rewrite(old_text: str, new_doc) -> str`. It returns JSON text equal in value to `new_doc`, keeping `old_text`'s bytes for every subtree whose value is unchanged.
  - Objects keep their key order.
  - New keys go at the end.
  - List items are matched by their `"id"` when both sides have ids, else by position.
  - A changed or new value takes the style of what it replaces. When there is nothing to replace, it takes its nearest sibling's style: single-line `{ "k": v, ... }` / `[a, b]` if that was one line, else multi-line at the sibling's indent, two spaces per level.

  The span map must come from scanning `old_text` itself, which Python's `json` can't provide: a tokenizer that records each value's start and end offsets and its path.

- [ ] **Step 1: Write the failing tests**
  - `test_unchanged_grammar_round_trips`: `rewrite(text, json.loads(text)) == text` for the repository's `data/grammar.json` and `data/furigana.json`.
  - `test_one_example_edit_changes_one_line`: change one example's `en` in grammar. The result differs from the original on exactly one line, and `json.loads(result) == doc`.
  - `test_new_example_matches_its_siblings`: append an example to a usage. One new line in the inline style, the previous last example gains a trailing comma, and nothing else changes.
  - `test_removed_item_takes_its_comma_with_it`: removing the last item of a list leaves valid JSON and no other line changes.
  - `test_new_usage_is_multi_line`: appending a usage whose siblings are multi-line gives a multi-line block with inline examples.
  - `test_new_key_and_removed_key`: adding `"review"` after an entry's keys, and removing it again, round trips to the original text.

- [ ] **Step 2: Run, expect failures.** `python3 -m unittest scripts.test_json_preserve` → FAIL (no module).

- [ ] **Step 3: Implement `rewrite`.** Standard library only. `json.loads(result) == new_doc` is asserted before returning.

- [ ] **Step 4: Run, expect passes.** Same command, plus `make test-py`.

- [ ] **Step 5: Commit** `git commit -m "scripts: a JSON writer that keeps a file's hand formatting"`

---

### Task 6: Apply an export batch to the data

**Files:**
- Create: `scripts/review_export.py`
- Test: `scripts/test_review_export.py`

**Interfaces:**
- Consumes:
  - Task 1's `update_data.review_hash`, `COUNTER_GENERATED` and `REVIEWER_RANK`, and `mark_reviewed.stamp`;
  - Task 4's export JSON;
  - Task 5's `rewrite`.
- Produces:
  - `apply_batch(batch: dict, docs: dict[str, dict], today: str) -> Report`. It mutates `docs`, keyed `verbs`, `words`, `counters`, `grammar` and `furigana`.
  - `Report` is a dataclass:
    - `applied: list[Line]`, `skipped: list[Line]`, `notes: list[Line]`;
    - `stamps_written: list[Line]`, `stamps_removed: list[Line]`;
    - `suggestion_ids: list[int]`, `stamp_ids: list[int]`: what was written, for the Export page.
  - `Line(text: str, credit: str)`. `credit` is the public name, else the role wording ("a teacher", "a native speaker", "the owner").
  - `locate(entry, kind, item_id) -> tuple[list, int] | None`: finds a part the way `items.rs` `entry_rows` lists them.
    - examples: `examples`, `usages[*].examples`, `pitfalls[*].examples`, `contrasts[*].examples`;
    - collocations: `collocations`; usages: `usages`; pitfalls: `pitfalls`; things: `things`.
  - `entry_of(docs, dataset, entry_id) -> dict | None`. The id rules are:
    - verbs: `id`, else `dict`;
    - words: `class:dict`;
    - counters and grammar: `id`.
  - `summary_markdown(report) -> str`: the PR body, with sections "Changes", "Added", "Removed", "Stamps", "Skipped", "Notes for you" and a final line listing the suggestion and stamp ids.

Order:
1. Check requested stamps against the data before any change: the entry's `review_hash(entry, generated)` must equal `content_hash`, else the stamp is skipped as "changed since it was stamped".
2. Changes. Set or remove each key in `editable` from `item`. Other keys are untouched.
3. Additions. Append to the parent list, keyed by `parent_kind`, or to the file's top list for a new entry.
4. Furigana. Add the keys missing from `furigana["readings"]`. An existing key with a different reading is reported under "Skipped".
5. Removals. A part comes out of its list; an entry comes out of its file.
6. Stamps:
   - Requested stamps whose entry this batch didn't touch are written with `stamp(entry, by, today, generated, name)`.
   - Any existing `review` stamp whose hash no longer matches is removed, listed under `stamps_removed` as "<title>: changed, needs a new review".
   - Notes go only to the report.

A suggestion whose target or parent can't be found is skipped with "no longer in the data", never raised.

- [ ] **Step 1: Write the failing tests.** Small hand-built docs, plus one test on the real `data/` copies.
  - `test_change_sets_only_editable_keys`: an item whose `forms` differ from the data, with `editable` excluding `forms`, leaves `forms` as it was. A key absent from `item` but listed in `editable` is removed.
  - `test_addition_goes_to_its_parent`: an example under a usage lands at the end of that usage's `examples`. A new word lands at the end of `words`.
  - `test_change_and_removal_of_the_same_item`: both apply in order, the item is gone, and nothing raises. A change to an already-removed item is "Skipped: no longer in the data".
  - `test_change_removes_a_stale_stamp`: a stamped counter whose meaning changes loses `review` and appears in `stamps_removed`.
  - `test_stamp_skipped_when_the_batch_changes_its_entry`: the stamp shows under "Skipped", and no `review` is written.
  - `test_stamp_written_with_name`: the result is `{"by":"native","on":today,"sha256":...,"name":"Aiko"}`, and `update_data.check_reviews` on the result gives no problems.
  - `test_furigana_added_once`: a reading that already exists with a different value is reported, not overwritten.
  - `test_summary_has_no_email`: the markdown names credits only, and contains every applied item's title.

- [ ] **Step 2: Run, expect failures.** `python3 -m unittest scripts.test_review_export` → FAIL.

- [ ] **Step 3: Implement.** Pure functions, with no file or network access.

- [ ] **Step 4: Run, expect passes**, plus `make test-py`.

- [ ] **Step 5: Commit** `git commit -m "scripts: apply accepted review work and stamps to the data"`

---

### Task 7: `make review-pull`

**Files:**
- Create: `scripts/review_pull.py`
- Modify: `Makefile` (`review-pull` target, in the help list)
- Modify: `review/README.md`: a new "Exporting" section covering the one-time setup (a third Access application for the path `review.martinloeseth.dev/api/export` with a Service Auth policy, a service token, the two Worker secrets, the Keychain items) and the routine (pull, push, PR, `make data-release` later, mark exported)
- Modify: `docs/superpowers/specs/2026-10-27-data-review-site-design.md` (export steps 5–6: signing by batch, `exported_at` instead of an `exported` status, marking on the Export page)
- Modify: `AGENTS.md`: add `make review-pull` to the command table, as an owner-only command like `make data-release`
- Test: `scripts/test_review_pull.py`

**Interfaces:**
- Consumes: Task 4's export JSON, Task 6's `apply_batch` and `summary_markdown`, Task 5's `rewrite`, and `update_data`'s `dump_verbs`, `dump_words` and `dump_counters`.
- Produces: `main(argv=None, fetch=None) -> int`.
  - Options:
    - `--from-file PATH` reads the batch from a file instead of the network;
    - `--summary PATH` also writes the summary to PATH;
    - `--today YYYY-MM-DD`;
    - `--no-commit`.
  - `fetch` is a callable for tests.
  - Exit codes: 0 done, 1 refused (with the reason on stderr), 2 when `update_data.py` failed.

Steps of a run:
1. Refuse when the working tree is dirty ("commit or set aside your changes first").
2. Fetch the batch: `GET https://review.martinloeseth.dev/api/export` with headers `CF-Access-Client-Id` and `CF-Access-Client-Secret`, read with `security find-generic-password -s kotobatable-review-export -a <account> -w`. An empty batch prints "Nothing to export." and exits 0.
3. `git fetch origin`, then `git switch -c review-pull/<today> origin/main`. If that branch exists, append `-2`, `-3` and so on.
4. For every dataset the batch touches, plus `furigana` when any suggestion carries readings, the sha256 of `data/<name>.json` must equal `files[name]`. Otherwise switch back, delete the branch, and refuse: "The site's copy of <name>.json is older than main: load the published data on the site, then pull again. If main has unreleased data changes, run make data-release first."
5. Apply the batch.
   - Write verbs, words and counters with their `dump_*`.
   - Write grammar and furigana with `rewrite(old_text, doc)`.
   - Run `python3 scripts/update_data.py`. On failure, print its output plus "the batch had suggestions <ids>; fix the data or decline the culprit on the site", leave the branch for inspection, and exit 2.
6. `git add -A` and commit "Review pull <today>: <n> changes, <m> stamps" with the commit trailer. Print the summary and "Next: git push -u origin <branch>, open a PR with the summary above, and after it merges mark the batch exported at /admin/export."

- [ ] **Step 1: Write the failing tests** (in a temporary clone: `git clone --quiet --local <repo> <tmp>`, run `main([... , "--from-file", batch])` with `cwd` set to the clone):
  - `test_pull_writes_a_branch_with_the_change`:
    - The batch changes one grammar example's `en`, with `files` taken from the clone's current data shas.
    - Expect exit 0, branch `review-pull/2026-11-07`, and one commit whose diff touches that example's line in `data/grammar.json` plus what `update_data.py` regenerates.
    - `make data-check` passes in the clone.
  - `test_refuses_when_main_is_ahead_of_the_site`: a wrong `files["grammar"]` gives exit 1 with the message above. No branch remains and the files are untouched.
  - `test_refuses_a_dirty_tree`: exit 1.
  - `test_empty_batch_does_nothing`: exit 0 and no branch.

- [ ] **Step 2: Run, expect failures.** `python3 -m unittest scripts.test_review_pull` → FAIL.

- [ ] **Step 3: Implement**, then the Makefile target `review-pull: ## Owner only: pull accepted review work into a data branch`, then the docs.

- [ ] **Step 4: Run** `make test-py`, `make review-test` and `make check-project`. Expected: all pass.

- [ ] **Step 5: Commit** `git commit -m "make review-pull: accepted review work into a data branch with a PR summary"`
