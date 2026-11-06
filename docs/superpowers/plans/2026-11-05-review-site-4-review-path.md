# Review site, plan 4: the review path

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reviewers work through the owner's queues and any item they browse: they approve it with a red 確認 seal, suggest a change, suggest removing it, leave a note for the owner, or skip. They see each other's approvals and suggestions. The owner builds queues and rules on suggestions in an inbox that shows each change as a red-pen correction.

**Architecture:** Everything a reviewer does targets one item row from plan 3, `(dataset, kind, item_id)`, and records the row's `content_hash` as it was when they acted. An approval counts only while that hash is current. A suggestion stores the whole proposed item, built on the server from the current item plus the reviewer's edited fields. A suggestion whose base hash no longer matches is shown as stale and can't be accepted unedited. The rules for which fields can be edited, which are locked, and how a proposed item is checked live in one pure Rust module (`proposal.rs`), tested natively. The pages draw their forms from the field list the API serves. A new `ReviewStore` trait (D1 and SQLite, sharing its SQL as in plan 3) holds approvals, suggestions, comments, queues and skips. Accepting a suggestion only marks it accepted; nothing reaches `data/` until export (plan 6).

**Tech Stack:** as plans 3 and 3b. No new crates or npm packages.

**Spec:** `docs/superpowers/specs/2026-10-27-data-review-site-design.md`. The relevant sections:
- D1 tables: queues, suggestions, approvals, comments
- Ids are frozen
- Furigana for new kanji
- Validation
- The site → Look and Screens
- Questions the owner answered 1 and 3

Earlier plans: `2026-11-04-review-site-3-read-path.md` and `2026-11-05-review-site-3b-stepped-load.md` (merged, #195).

## Roadmap

1. Stable ids (#181).
2. Schemas and skeleton (#190).
3. The read path (#195).
4. **This plan: the review path.**
5. The add path.
6. Export.
7. Stamps for verbs, words and examples.

## Global Constraints

- **Earlier plans' constraints still hold:**
  - Every `/api/*` request verifies Access, then D1.
  - Admin routes need the admin application and the admin role.
  - Non-GET requests need a matching `Origin`.
  - No secrets, AUD tags, team domain or emails in committed files.
  - Workers Free: about 10 ms of CPU per request.
  - No inline styles (CSP).
- **The site never writes `data/` and never signs.** Accepting a suggestion only changes its status.
- **A target** is `(dataset, kind, item_id)`, with `kind` one of `entry`, `example`, `collocation`, `usage`, `pitfall`, `thing` (plan 3's `Kind`). A target must exist in `items` when a reviewer acts on it. Anything stored about a target keeps working after the item disappears from the data.
- **Approval and stale rules use `items.content_hash`:**
  - For an entry, `content_hash` is the entry hash, which leaves out sub-items.
  - For a usage or pitfall, it is the hash of the whole object, examples included. So editing one of its examples makes earlier approvals of the usage show as "an earlier version". Accepted; noted in the copy.
- **Locked fields** (spec, "Ids are frozen"): verb `dict`, `kanji` and `id`; word `class`, `dict` (`class` is part of the word id); counter `id`; grammar `id`; every sub-item's `id`. A reviewer who thinks one is wrong leaves a note.
- **Editable fields per target.** Anything not listed is carried over unchanged from the current item.

  | dataset/kind | editable fields |
  |---|---|
  | verbs/entry | `type`, `label`, `meaning`, `description`, `notes`, `jlpt`, `teGroup` (optional) |
  | verbs/example | `form` (a form id), `jp`, `en` |
  | verbs/collocation | `jp`, `en` |
  | words/entry | `meaning`, `jlpt`, `kanji` (optional) |
  | counters/entry | `counter`, `reading`, `meaning`, `jlpt` |
  | counters/thing | `word`, `kana`, `meaning`, `fit` |
  | counters/example | `jp`, `en` |
  | counters/pitfall | `heading`, `explanation`, `wrong` (optional) |
  | grammar/entry | `title`, `summary`, `jlpt` |
  | grammar/usage | `heading`, `explanation`, `jlpt` (optional) |
  | grammar/example | `jp`, `en` |
  | grammar/pitfall | `heading`, `explanation`, `wrong` (optional) |

- **Input types:**
  - `text`: one line.
  - `long`: multi-line; `description`, `notes`, `explanation`, `summary`.
  - `jlpt`: N5–N1.
  - `choice`: verbs `type`, `label`, `teGroup` and counters `fit`. The choices are the strict enum strings from `data.rs`.
  - `form`: a form id from `forms.json`.
- **Text rules:**
  - Values are trimmed.
  - A required field can't be empty.
  - An optional field left empty is removed from the item.
  - At most 2000 characters per field, comment and reply.
- **Particle blanks** (verb and grammar examples) aren't editable. When `jp` changes, a blank whose particle still sits at its `at` offset (counted in code points, as `update_data._check_blanks`) is kept, and the others are dropped. The suggestion records how many were dropped; the owner sees "2 particle blanks dropped; mark them again at export".
- **Furigana additions:** a change may carry `furigana: {"<kanji run>": "<hiragana>"}`.
  - Every key is made only of CJK ideographs and 々, and isn't already in the loaded `furigana.json`.
  - Every value is hiragana (U+3041–U+309F, plus ー).
  - At most 20 per suggestion.
- **Messages.** Exact API error strings:
  - `"that isn't in the loaded data"`
  - `"this changed since you opened it; reload to see the new version"`
  - `"<field> can't be changed here; leave a note for Martin instead"`
  - `"nothing changed"`
  - `"<field> can't be empty"`
  - `"<field> is too long"`
  - `"there is no form called <form>"`
  - `"<dict> has no <form> form"`
  - `"readings are for kanji: <key>"`
  - `"a reading is written in hiragana: <value>"`
  - `"<key> already has a reading"`
  - `"the data changed since this was suggested; use Edit then accept"`
  - `"this suggestion has already been decided"`
  - `"only the person who suggested it can withdraw it"`
  - `"a note needs a comment"`
- **Copy** (sentence case, the marking-desk look):
  - Review actions: "Looks right", "Suggest a change", "Not sure, skip", "Suggest removing it", "Leave a note for Martin".
  - The seal reads 確認 with the reviewer's display name.
  - Admin actions: "Accept", "Edit then accept", "Reply", "Decline".
  - Stale label: "Changed since"; missing item: "No longer in the data".
  - Old approval: "<name> approved an earlier version".
- **Reviewers' names on the site** are users' `display_name`. Emails never appear in any response except `/api/me` and the admin users list (as today).

## Review Focus

- **Stale data:** the owner reloads data while a reviewer has a form open, or after a suggestion was made.
  - Submitting with the old `base_hash` gives 409 with the stale message.
  - The open suggestion lists as "Changed since".
  - Plain Accept is refused, and Edit then accept works against the current text.
  - Tests in Tasks 3 and 5.
- **Removed items:** an item with approvals, suggestions or a queue entry disappears from the data.
  - Every list still renders it from its stored title, marked "No longer in the data".
  - Queue progress counts it as done, so nobody waits on it forever.
  - No 500s.
  - Tests in Tasks 3, 4 and 5.
- **Double taps:** a reviewer taps "Looks right" twice, or submits the same suggestion twice on a slow phone.
  - An approval is one row per reviewer per target.
  - An identical open suggestion (same author, target and proposed item) returns the existing one instead of a duplicate.
  - Tests in Tasks 1 and 3.
- **Empty or unchanged edits:** a suggestion that changes nothing, empties a required field, or only adds spaces gives 400 "nothing changed" or "<field> can't be empty". Test in Task 2.
- **Two reviewers on one item:** one approves while another suggests, or both suggest.
  - Everything is kept and shown with display names.
  - Accepting one suggestion leaves the other open for the owner to decide.
  - Tests in Tasks 3 and 5.

---

### Task 1: Review storage (migration 0004, `review_store.rs`)

**Files:**
- Create: `review/api/migrations/0004_review.sql`, `review/api/src/review_store.rs`
- Modify: `review/api/src/lib.rs`, `review/api/src/d1.rs`, `review/api/tests/support/sqlite.rs`
- Test: `review/api/tests/review_store.rs`

**Interfaces:**
- Consumes: the `items` and `users` tables. `Kind` from `items.rs`.
- Produces:
  - The migration:

    ```sql
    approvals(dataset, kind, item_id, entry_id, reviewer, content_hash, created_at, PRIMARY KEY (dataset, kind, item_id, reviewer))
    suggestions(id INTEGER PRIMARY KEY AUTOINCREMENT, action CHECK IN ('change','delete','note'), dataset, kind, item_id,
      entry_id, item_title, base_hash, proposed_json NULL, furigana_json NULL, dropped_blanks INTEGER NOT NULL DEFAULT 0,
      comment NOT NULL DEFAULT '', author, status CHECK IN ('open','accepted','declined','withdrawn') DEFAULT 'open',
      admin_edit_json NULL, created_at, decided_at NULL, decided_by NULL)
    comments(id INTEGER PRIMARY KEY AUTOINCREMENT, suggestion_id REFERENCES suggestions(id), author, body, created_at)
    queues(id INTEGER PRIMARY KEY AUTOINCREMENT, title, description NOT NULL DEFAULT '', created_by, created_at,
      archived INTEGER NOT NULL DEFAULT 0 CHECK IN (0,1))
    queue_items(queue_id REFERENCES queues(id), dataset, kind, item_id, entry_id, item_title, note NOT NULL DEFAULT '',
      position INTEGER, PRIMARY KEY (queue_id, dataset, kind, item_id))
    skips(queue_id, dataset, kind, item_id, reviewer, created_at, PRIMARY KEY (queue_id, dataset, kind, item_id, reviewer))
    ```

    Indexes: `suggestions_by_entry (dataset, entry_id)`, `suggestions_by_status (status)`, `approvals_by_entry (dataset, entry_id)`. `entry_id` on approvals is filled from `items` at insert, so an entry's approvals stay findable after a part leaves the data.
  - `review_store.rs` types (serde `Serialize`):
    - `Target { dataset: String, kind: String, item_id: String }`
    - `Approval { kind, item_id, reviewer_name: String, mine: bool, current: bool, created_at }`
    - `Suggestion { id: i64, action, dataset, kind, item_id, entry_id, item_title, author_name, mine: bool, status, base_hash, proposed: Option<Value>, furigana: Option<Value>, dropped_blanks: u32, comment, admin_edit: Option<Value>, created_at, decided_at: Option<String>, stale: bool, gone: bool, comments: Vec<Comment> }`
    - `Comment { author_name, body, created_at }`
    - `QueueSummary { id, title, description, total: u32, done: u32, with_suggestion: u32, archived: bool }`
    - `QueueItem { dataset, kind, item_id, entry_id, title, note, position, gone: bool, mine: Option<String> }`, where `mine` is `"approved"`, `"suggested"` or `"skipped"`.
    - `NewSuggestion { action, target, entry_id, item_title, base_hash, proposed_json: Option<String>, furigana_json: Option<String>, dropped_blanks: u32, comment }`
    - `QueueFilter { dataset: String, kinds: Vec<String>, jlpt: Vec<String>, never_approved: bool, ids: Vec<String> }`. Empty lists mean "any". `ids` matches `item_id` exactly, within the dataset.
  - `#[allow(async_fn_in_trait)] pub trait ReviewStore`. `viewer` is the asking user's email, used for `mine`. Names come from a join on `users`. `stale` means the target's current `content_hash` ≠ `base_hash`; `gone` means the target isn't in `items`. Every write also inserts its audit row in the same batch. The audit actions are:
    - `approval.add` and `approval.remove`
    - `suggestion.add`, `suggestion.withdraw`, `suggestion.accept`, `suggestion.decline`
    - `comment.add`
    - `queue.add`, `queue.update`, `queue.note`, `queue.remove_item`
    - `queue.skip`

    The trait's functions:

    ```rust
    async fn current_hash(&self, t: &Target) -> Result<Option<(String, String, String)>, StoreError>; // (content_hash, entry_id, title)
    async fn approve(&self, t: &Target, hash: &str, reviewer: &str, now: &str) -> Result<(), StoreError>; // upsert
    async fn unapprove(&self, t: &Target, reviewer: &str, now: &str) -> Result<(), StoreError>;
    async fn add_suggestion(&self, s: &NewSuggestion, author: &str, now: &str) -> Result<i64, StoreError>; // returns an identical open one's id instead of inserting
    async fn suggestion(&self, id: i64, viewer: &str) -> Result<Option<Suggestion>, StoreError>;
    async fn withdraw(&self, id: i64, author: &str, now: &str) -> Result<(), StoreError>; // NotFound if not open; Conflict if not the author's
    async fn decide(&self, id: i64, accept: bool, admin_edit_json: Option<&str>, by: &str, now: &str) -> Result<(), StoreError>; // only from 'open', else Conflict
    async fn add_comment(&self, suggestion_id: i64, body: &str, author: &str, now: &str) -> Result<(), StoreError>;
    async fn entry_review(&self, dataset: &str, entry_id: &str, viewer: &str) -> Result<(Vec<Approval>, Vec<Suggestion>), StoreError>; // suggestions in every status, newest first
    async fn inbox(&self, status: &str, viewer: &str) -> Result<Vec<Suggestion>, StoreError>; // oldest first
    async fn review_counts(&self, dataset: &str) -> Result<Vec<(String, u32, u32)>, StoreError>; // (entry_id, approved targets, open suggestions)
    async fn queues(&self, viewer: &str, include_archived: bool) -> Result<Vec<QueueSummary>, StoreError>;
    async fn queue(&self, id: i64, viewer: &str) -> Result<Option<(QueueSummary, Vec<QueueItem>)>, StoreError>;
    async fn preview_queue(&self, f: &QueueFilter) -> Result<Vec<QueueItem>, StoreError>; // in items.position order
    async fn add_queue(&self, title: &str, description: &str, f: &QueueFilter, by: &str, now: &str) -> Result<i64, StoreError>; // one INSERT … SELECT FROM items
    async fn update_queue(&self, id: i64, title: &str, description: &str, archived: bool, by: &str, now: &str) -> Result<(), StoreError>;
    async fn set_queue_note(&self, id: i64, t: &Target, note: &str, by: &str, now: &str) -> Result<(), StoreError>;
    async fn remove_queue_item(&self, id: i64, t: &Target, by: &str, now: &str) -> Result<(), StoreError>;
    async fn skip(&self, id: i64, t: &Target, reviewer: &str, now: &str) -> Result<(), StoreError>;
    ```

  - **Counting rules:**
    - `approved targets` counts targets of the entry (the entry and its sub-items) with at least one *current* approval.
    - In a queue, `done` for the viewer counts items where any of these hold:
      - the viewer has a current approval;
      - the viewer has a suggestion on it in status open or accepted;
      - the viewer skipped it in this queue;
      - the item is gone.
    - `with_suggestion` counts items with any open suggestion.
    - `QueueItem.mine` follows the same order: approved, suggested, skipped.
  - The SQL is written once as constants in `review_store.rs`, as `store.rs` does.

- [ ] **Step 1: Write the failing tests.** They run in the SQLite store with real `words.json` and `verbs.json` loaded through `extract` and `replace_snapshot`, with users `aiko` and `ben` (reviewers) and `martin` (admin).
  - `an_approval_counts_while_the_hash_matches`: aiko approves `words/entry/i-adjective:いい` with its hash, so `entry_review` gives `current: true` with `reviewer_name` "Aiko". Reload the words snapshot with that entry's meaning changed: now `current: false`. `review_counts` drops from 1 to 0.
  - `approving_twice_is_one_row`: two `approve` calls give one approval and two audit rows.
  - `an_identical_open_suggestion_is_not_duplicated`: `add_suggestion` twice with the same author, target and `proposed_json` returns the same id. After withdrawing it, the same call makes a new one.
  - `stale_and_gone_are_computed_on_read`:
    - a suggestion whose `base_hash` differs from the current hash has `stale: true`;
    - after reloading verbs without that verb, `gone: true` and `item_title` is still the stored title.
  - `only_open_suggestions_can_be_decided_or_withdrawn`:
    - `decide` on an accepted one gives `Conflict`;
    - ben withdrawing aiko's gives `Conflict`;
    - withdrawing a declined one gives `NotFound`.
  - `queue_progress_follows_the_counting_rules`:
    - Build a queue of 4 words with `QueueFilter { dataset: "words", ids: [...4 ids] }`.
    - aiko approves one, suggests on one and skips one: `done == 3` and `mine` is `approved`, `suggested`, `skipped`, `None`.
    - ben sees `done == 0` and `with_suggestion == 1`.
    - Reload words without the fourth: aiko's `done == 4`, and that item has `gone: true`.
  - `the_filter_picks_by_kind_level_and_never_approved`:
    - `verbs` with kinds `["example"]` and jlpt `["N5"]` gives only examples of N5 verbs, in position order. An example's level is its entry's: join on `entry_id`.
    - `never_approved` leaves out a target with any approval, current or not.
  - `every_write_is_audited`: one audit row per action name listed above.
- [ ] **Step 2: Run them to see them fail.** Run `cd review/api && cargo test --test review_store`. Expected: compile errors.
- [ ] **Step 3: Write the migration, the SQL, and the SQLite and D1 implementations.** In D1 use `batch`; in SQLite use one transaction.
- [ ] **Step 4: Run the checks.** Run `cargo test && cargo clippy --all-targets -- -D warnings && cargo clippy --target wasm32-unknown-unknown -- -D warnings`. Expected: everything passes and clippy is clean.
- [ ] **Step 5: Commit.** `git commit -m "review/api: store approvals, suggestions, comments, queues and skips"`

---

### Task 2: Building a proposed item (`proposal.rs`, pure)

**Files:**
- Create: `review/api/src/proposal.rs`
- Test: `review/api/tests/proposal.rs`

**Interfaces:**
- Consumes: `DataFile`, the strict types and `check_entry` from `data.rs`. `canonical_json` and `content_hash` from `items.rs`.
- Produces:
  - `#[derive(Serialize)] struct Field { name: &'static str, input: Input, optional: bool, choices: &'static [&'static str] }`, with `enum Input { Text, Long, Jlpt, Choice, Form }` (serde lowercase).
  - `fn fields(file: DataFile, kind: Kind) -> &'static [Field]`, following the Global Constraints table. An empty slice means the target can't be edited.
  - `fn locked(file: DataFile, kind: Kind) -> &'static [&'static str]`.
  - `fn find_part<'a>(entry: &'a Value, kind: Kind, id: &str) -> Option<&'a Value>` finds the object with that stable `id` anywhere inside the entry. Plan 3's walk defines where each kind sits.
  - `struct Change { proposed: Value, dropped_blanks: u32 }`.
  - The core function:

    ```rust
    fn build_change(file: DataFile, kind: Kind, entry: &Value, item_id: &str,
                    edits: &serde_json::Map<String, Value>, form_ids: &BTreeSet<String>) -> Result<Change, String>
    ```

    1. Start from the current item: the entry for `Kind::Entry`, else `find_part`.
    2. Refuse a key that is locked (the locked message) or not in `fields` (`"<key> can't be changed here; leave a note for Martin instead"`, the same message).
    3. Apply the edits using the text rules. A `choice` or `jlpt` value must be one of its choices.
    4. Refuse when the result equals the current item: "nothing changed".
    5. For a verb example's `form`, check:
       - the form is in `form_ids`, else "there is no form called <form>";
       - the verb's `forms[<form>]` is non-empty, else "<dict> has no <form> form" (as `check_example_forms`).
    6. Apply the particle-blank rule.
    7. Validate:
       - an entry with `check_entry(file, &proposed)`;
       - a sub-item by deserialising it into its strict type, chosen by `(file, kind)`: `VerbExample`, `Collocation`, `CounterThing`, `CounterExample`, `CounterPitfall`, `Usage`, `GrammarExample`, `GrammarPitfall`.

       Serde's message is prefixed "doesn't fit the data schema: ".
  - `fn check_furigana(add: &BTreeMap<String, String>, known: &BTreeMap<String, String>) -> Result<(), String>` applies the furigana rule.

- [ ] **Step 1: Write the failing tests.** Real data loaded from `data/`.
  - `editing_a_verb_meaning_keeps_everything_else`: たべる with `{"meaning": "to eat (a meal)"}`. The proposed item equals the entry with only `meaning` replaced, and its `forms`, `examples` and `id`-less `dict` are untouched.
  - `locked_fields_are_refused`: these all give the locked message:
    - `dict` on a verb;
    - `kanji` on a verb;
    - `class` on a word;
    - `id` on an example.
  - `a_field_not_in_the_table_is_refused`: `overrides` on a counter.
  - `nothing_changed_and_empty_fields`:
    - the same meaning, or the same with spaces around it, gives "nothing changed";
    - `{"meaning": "  "}` gives "meaning can't be empty";
    - an empty optional `wrong` on a pitfall that has one removes the key.
  - `choices_are_checked`: `{"jlpt": "N6"}` gives Err, and `{"fit": "best"}` on a thing gives Err with the field name in the message.
  - `example_forms_are_checked`:
    - an unknown form id gives "there is no form called x";
    - a real form the verb lacks (pick one from `EXTRA_EXCLUDED` for a verb in the data) gives "<dict> has no <form> form".
  - `particle_blanks_follow_the_sentence`:
    - Take a verb or grammar example with blanks and change `jp` so the first blank's particle moves.
    - `dropped_blanks == 1`, and the blanks that still match stay.
    - An `en`-only edit drops nothing.
  - `long_text_is_refused`: a 2001-character `notes` gives "notes is too long".
  - `the_field_table_covers_every_kind_in_the_data`: for every `(dataset, kind)` found in `extract` over the four real files, `fields` is non-empty.
  - `furigana_additions`:
    - `{"猫": "ねこ"}` passes when 猫 is unknown;
    - `{"ねこ": "ねこ"}` gives "readings are for kanji: ねこ";
    - `{"猫": "ネコ"}` gives "a reading is written in hiragana: ネコ";
    - a key already in `furigana.json` gives "<key> already has a reading".
- [ ] **Step 2: Run them to see them fail.** Run `cargo test --test proposal`.
- [ ] **Step 3: Implement `proposal.rs`.**
- [ ] **Step 4: Run the checks.** Run `cargo test --test proposal && cargo clippy --all-targets -- -D warnings`.
- [ ] **Step 5: Commit.** `git commit -m "review/api: build and check a proposed change from a reviewer's edited fields"`

---

### Task 3: The reviewer's API: approve, suggest, comment

**Files:**
- Modify: `review/api/src/app.rs` (routes and handlers; `handle`'s store bound becomes `S: Store + ReviewStore`), `review/api/src/worker_glue.rs` (nothing beyond the bound), `review/api/tests/app.rs` callers
- Test: `review/api/tests/review_api.rs`

**Interfaces:**
- Consumes: Tasks 1 and 2.
- Produces routes. All need Reviewer; the POSTs check `Origin`.

  | Method, path | Body or query | Success |
  |---|---|---|
  | `GET /api/review` | `?dataset=&id=<entry id>` | 200 `{"parts":[{"kind","item_id","content_hash"}…], "approvals":[Approval…], "suggestions":[Suggestion…]}`. `parts` lists the entry and each sub-item in position order. |
  | `POST /api/approve` | `{dataset, kind, id, content_hash}` | 200 `{"approvals":[…]}`, the entry's list after the change |
  | `POST /api/approve/withdraw` | `{dataset, kind, id}` | 200 as above |
  | `POST /api/suggest` | `{dataset, kind, id, base_hash, action: "change"\|"delete"\|"note", edits?: {…}, furigana?: {…}, comment?: string}` | 201 the stored `Suggestion` (200 when an identical open one already existed) |
  | `POST /api/suggest/withdraw` | `{id}` | 200 the `Suggestion` |
  | `POST /api/comment` | `{suggestion_id, body}` | 201 the `Suggestion` with its comments |

  - `GET /api/items` items gain `approved: u32`, `open: u32` and `targets: u32` (= `parts + 1`), from `review_counts`.
  - `GET /api/reference` gains `"fields": {"verbs/entry": [Field…], …}` for every pair in the table.
  - **Rules:**
    - The target must be in `items`, else 404 "that isn't in the loaded data".
    - `content_hash` or `base_hash` must equal the current hash, else 409 with the stale message.
    - `change` needs `edits` and goes through `build_change`, with `form_ids` from the stored forms snapshot.
    - `delete` needs nothing else.
    - `note` needs a non-empty `comment`, else 400 "a note needs a comment".
    - `furigana` is allowed only with `change` and is checked against the stored furigana snapshot.
    - Error mapping:
      - `Conflict` from withdraw: 403 "only the person who suggested it can withdraw it";
      - `NotFound`: 409 "this suggestion has already been decided";
      - a comment on an unknown suggestion: 404.

- [ ] **Step 1: Write the failing tests.** Use the `FakeSource` and the real data, loaded through plan 3b's `load` helper.
  - `a_reviewer_approves_and_everyone_sees_it`:
    - aiko approves たべる (entry) and one example.
    - ben's `GET /api/review` shows both, named "Aiko", with `mine: false`.
    - aiko's shows `mine: true`.
    - `GET /api/items?dataset=verbs` gives たべる `approved == 2`.
  - `approving_an_old_version_is_refused`: a wrong `content_hash` gives 409 with the stale message.
  - `a_change_is_stored_as_the_whole_proposed_item`: aiko suggests a new `en` for an example. 201; `proposed` is the example with the new `en`, and `stale: false`.
  - `the_same_suggestion_twice_returns_the_first`: the second POST gives 200 with the same id.
  - `a_reload_makes_open_suggestions_stale_and_new_ones_refused`:
    - Change that example in the source data with a new signed manifest; tests sign with a generated key through `*_with_keys`, as in plan 3b.
    - The suggestion now has `stale: true`.
    - A new suggest with the old `base_hash` gives 409.
  - `locked_and_unknown_fields_come_back_as_400`: `edits: {"dict": "x"}` gives 400 with the locked message.
  - `a_note_and_a_delete`:
    - a note without a comment gives 400;
    - with one, 201 with action `note`;
    - a delete gives 201;
    - ben adds his own change on the same item, and both are listed.
  - `only_the_author_withdraws`:
    - ben withdrawing aiko's gives 403;
    - aiko gives 200, status `withdrawn`;
    - again gives 409.
  - `comments_show_on_the_suggestion`: martin comments and aiko comments. `GET /api/review` shows both, in order, with names.
  - `targets_that_left_the_data`:
    - After reloading without たべる, approving it gives 404.
    - `GET /api/review?dataset=verbs&id=たべる` still answers 200 with its suggestions marked `gone: true`, and `parts` empty.
  - `reference_serves_the_field_table`: `fields["verbs/example"]` names `form`, `jp` and `en`, and `form`'s input is `"form"`.
  - `wrong_origin_and_unknown_users`: a POST to `/api/approve` with a foreign Origin gives 403; an unknown email gives 403.
- [ ] **Step 2: Run them to see them fail.** Run `cargo test --test review_api`.
- [ ] **Step 3: Implement the routes.**
- [ ] **Step 4: Run the checks.** Run `cargo test && cargo clippy --all-targets -- -D warnings`.
- [ ] **Step 5: Commit.** `git commit -m "review/api: approve, suggest, withdraw and comment on any item"`

---

### Task 4: Queues API

**Files:**
- Modify: `review/api/src/app.rs`
- Test: `review/api/tests/queues_api.rs`

**Interfaces:**
- Consumes: Task 1's queue functions.
- Produces these routes:

  | Method, path | Need | Body or query | Success |
  |---|---|---|---|
  | `GET /api/queues` | Reviewer | | 200 `{"queues":[QueueSummary…]}`, not archived, newest first |
  | `GET /api/queue` | Reviewer | `?id=` | 200 `{"queue": QueueSummary, "items":[QueueItem…]}` in position order; 404 when unknown or archived (admin sees archived) |
  | `POST /api/queue/skip` | Reviewer | `{queue_id, dataset, kind, id}` | 200 the queue response |
  | `GET /api/admin/queues` | Admin | | 200 every queue, archived too |
  | `POST /api/admin/queues/preview` | Admin | `QueueFilter` + `ids_text` | 200 `{"count", "items": [first 50 QueueItem], "unmatched": [lines]}` |
  | `POST /api/admin/queues` | Admin | `{title, description, filter}` | 201 the queue response; 400 "a queue needs a title" or "nothing matches" |
  | `POST /api/admin/queues/update` | Admin | `{id, title, description, archived}` | 200 |
  | `POST /api/admin/queues/note` | Admin | `{queue_id, dataset, kind, id, note}` | 200 |
  | `POST /api/admin/queues/remove` | Admin | `{queue_id, dataset, kind, id}` | 200 |

  - `ids_text` is pasted text: one id per line, trimmed, blank lines ignored, at most 500 lines. Each line matches `item_id` in the filter's dataset, any kind allowed by `kinds`. Lines that match nothing come back in `unmatched` and don't block creation.
  - A queue holds at most 500 items; more gives 400 "a queue holds at most 500 items; narrow the filter".
  - Title ≤ 80 characters. Description and note follow the text rules.

- [ ] **Step 1: Write the failing tests.**
  - `the_owner_builds_a_queue_and_reviewers_work_through_it`:
    - martin previews `{dataset: "verbs", kinds: ["example"], jlpt: ["N5"]}` and gets a count above 0.
    - He creates it ("N5 verb examples") and sets a note on the first item ("Is this natural?").
    - aiko's `GET /api/queues` lists it with `done 0`.
    - `GET /api/queue` gives the first item with its note.
    - aiko skips it, approves the second through `/api/approve`, and gets `done 2`.
  - `pasted_ids_report_what_didnt_match`: `ids_text` `"たべる\nnope\n\nのむ"` gives count 2 and unmatched `["nope"]`.
  - `limits_and_empty_queues`:
    - no title gives 400;
    - a filter matching nothing gives 400 "nothing matches";
    - 501 pasted ids gives 400.
  - `archived_queues_leave_the_home_list`: after archiving, aiko's list is empty and `GET /api/queue` gives 404. martin's admin list still has it.
  - `reviewers_cannot_build_queues`: aiko gets 403 on every `/api/admin/queues*` route.
  - `a_gone_item_counts_as_done`: reload without one queued verb's example. Every reviewer's `done` includes it, and it lists with `gone: true` and its stored title.
- [ ] **Step 2: Run them to see them fail.** Run `cargo test --test queues_api`.
- [ ] **Step 3: Implement the routes.**
- [ ] **Step 4: Run the checks.** Run `cargo test && cargo clippy --all-targets -- -D warnings`.
- [ ] **Step 5: Commit.** `git commit -m "review/api: queues the owner builds and reviewers work through"`

---

### Task 5: The admin inbox API

**Files:**
- Modify: `review/api/src/app.rs`
- Test: `review/api/tests/inbox_api.rs`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces these routes:

  | Method, path | Body or query | Success |
  |---|---|---|
  | `GET /api/admin/inbox` | `?status=open` (default; also `accepted`, `declined`) | 200 `{"suggestions":[Suggestion + "current": <the target's current JSON or null>]}` |
  | `POST /api/admin/decide` | `{id, decision: "accept"\|"decline", edits?: {…}, furigana?: {…}, reply?: string}` | 200 the `Suggestion` |

  - **Rules:**
    - Accepting a `change` that is `stale` without `edits` gives 409 with the accept-stale message.
    - With `edits`, `build_change` runs against the *current* item, and the result is stored as `admin_edit_json`. This also works on a stale suggestion and on a `delete` or `note`. It is refused for a gone target (404 "that isn't in the loaded data").
    - `reply` adds a comment by the owner in the same request.
    - Deciding a decided suggestion gives 409 "this suggestion has already been decided".
    - Accepting a `delete` of a whole verb or word is allowed. The response carries `"warning": "Saved favourites, quiz history and widgets that point at <title> will be dropped when this is exported."`, and the page shows it before confirming (the page sends `confirm: true`; without it, 400 with that warning as the error).

- [ ] **Step 1: Write the failing tests.**
  - `the_owner_sees_open_suggestions_with_the_current_text`: after aiko's change, the inbox lists it with `current` equal to the example's JSON and `author_name` "Aiko".
  - `accept_decline_and_reply`:
    - martin accepts with `reply: "Thanks!"`. Status is `accepted`, it has one comment by "Martin", and it leaves `?status=open`.
    - He declines another, which goes to `?status=declined`.
  - `a_stale_change_needs_edit_then_accept`:
    - Make the suggestion stale (Task 3's reload helper).
    - A plain accept gives 409 with the message.
    - An accept with `edits: {"en": "…"}` gives 200, and `admin_edit` is the current example with that `en`.
  - `two_suggestions_on_one_item_are_decided_separately`: accepting aiko's leaves ben's open.
  - `deleting_a_verb_asks_for_confirmation`:
    - accept without `confirm` gives 400 with the warning;
    - with `confirm: true`, 200.
  - `deciding_twice_is_refused`: 409.
  - `reviewers_cannot_use_the_inbox`: 403 on both routes.
- [ ] **Step 2: Run them to see them fail.** Run `cargo test --test inbox_api`.
- [ ] **Step 3: Implement the routes.**
- [ ] **Step 4: Run the checks.** Run `cargo test && cargo clippy --all-targets -- -D warnings && cargo clippy --target wasm32-unknown-unknown -- -D warnings && worker-build --release`.
- [ ] **Step 5: Commit.** `git commit -m "review/api: the owner's inbox: accept, edit then accept, reply, decline"`

---

### Task 6: Page helpers: API calls, the red-pen diff, the mock

**Files:**
- Modify: `review/web/src/lib/api.ts`, `review/web/src/lib/api.test.ts`, `review/web/src/dev/mock-api.ts`, `review/web/src/lib/labels.ts`
- Create: `review/web/src/lib/diff.ts`, `review/web/src/lib/diff.test.ts`, `review/web/src/lib/targets.ts`, `review/web/src/lib/targets.test.ts`

**Interfaces:**
- Consumes: the routes from Tasks 3–5.
- Produces:
  - **`api.ts`:**
    - Types mirroring the Rust ones: `Approval`, `Suggestion`, `Comment`, `QueueSummary`, `QueueItem`, `Field`, `Review = { parts; approvals; suggestions }`, `InboxSuggestion = Suggestion & { current: Record<string, unknown> | null }`.
    - Functions: `getReview(dataset, id)`, `approve(target, contentHash)`, `withdrawApproval(target)`, `suggest(target, baseHash, action, { edits?, furigana?, comment? })`, `withdrawSuggestion(id)`, `comment(id, body)`, `listQueues()`, `getQueue(id)`, `skip(queueId, target)`, `adminQueues()`, `previewQueue(filter, idsText)`, `createQueue(title, description, filter)`, `updateQueue(…)`, `setQueueNote(…)`, `removeQueueItem(…)`, `getInbox(status)`, `decide(id, decision, { edits?, furigana?, reply?, confirm? })`.
    - `Reference` gains `fields: Record<string, Field[]>`.
    - `ItemSummary` gains `approved`, `open` and `targets`.
    - `type Target = { dataset: string; kind: string; id: string }`.
  - **`diff.ts`:** `type Piece = { same?: string; removed?: string; added?: string }` and `diffText(before: string, after: string): Piece[]`. A character-level LCS over code points; adjacent pieces of the same type merge. `diffFields(before, after, names: string[]): { name: string; pieces: Piece[] }[]` returns only the fields that changed, in `names` order.
  - **`targets.ts`:** `partOf(entry, kind, id)`, the TypeScript twin of `find_part`. `partsOf(dataset, entry): { kind, id, value }[]` lists the entry first, then its sub-items in document order. `unknownKanjiRuns(text, readings): string[]` gives the distinct kanji runs that `segments` (ruby.ts) leaves without a reading, which the change form asks readings for.
  - **`labels.ts`:** a field label per name ("Meaning", "Japanese" for `jp`, "English" for `en`, "Form", "Explanation"…), choice labels for verb `type` and `label` and counter `fit`, and kind names ("example", "common phrase" for collocation, "usage", "pitfall", "thing counted").
  - **The mock:** keeps approvals, suggestions, comments, queues and skips in memory per dev-server run. It implements every new route enough to click through, with content hashes taken from the loaded rows. `MOCK_ROLE=reviewer` still applies.

- [ ] **Step 1: Write the failing tests.**
  - In `diff.test.ts`:
    - `'a changed particle'`: `diffText('毎日学校に行きます', '毎日学校へ行きます')` → `[{same:'毎日学校'},{removed:'に'},{added:'へ'},{same:'行きます'}]`.
    - `'identical text is one piece'`.
    - `'all new'`: `diffText('', 'あ')` → `[{added:'あ'}]`.
    - `'only changed fields are listed'`: `diffFields({jp:'a',en:'b'},{jp:'a',en:'c'},['jp','en'])` → one entry, `en`.
  - In `targets.test.ts`:
    - `partsOf` on a grammar point fixture gives the entry, then usage, its examples, pitfall, its examples, contrast examples, in that order.
    - `unknownKanjiRuns('猫が毎日来る', {毎日:'まいにち', 来:'く'})` → `['猫']`.
  - In `api.test.ts`:
    - `approve({dataset:'verbs',kind:'example',id:'abcdef'},'h')` POSTs `/api/approve` with `{dataset,kind,id,content_hash:'h'}`.
    - `getReview('verbs','きる:切る')` encodes the id.
- [ ] **Step 2: Run them to see them fail.** Run `cd review/web && npx vitest run src/lib`.
- [ ] **Step 3: Implement the helpers and the mock routes.**
- [ ] **Step 4: Run the checks.** Run `npx vitest run src/lib && npm run check`.
- [ ] **Step 5: Commit.** `git commit -m "review/web: review API calls, the red-pen diff, and the mock's review routes"`

---

### Task 7: Reviewing on the item page

**Files:**
- Create in `review/web/src/lib/`:
  - `Seal.svelte`: the red 確認 seal with a name. It plays the press animation only when `pressed` changes to true and `prefers-reduced-motion` isn't set.
  - `RedPen.svelte`: field-by-field `diffFields` output. Removed text struck through in red, added text written above it in red, in Mincho for Japanese fields.
  - `ReviewBar.svelte`: the actions for one target, plus its approvals (seals) and suggestions.
  - `SuggestForm.svelte`: the per-target form built from `reference.fields`, with a live preview in the card style.
  - `SuggestionCard.svelte`: one suggestion with its red pen, author, status, "Changed since" or "No longer in the data", its comments, and a reply box.
- Modify: `review/web/src/routes/item/+page.svelte`, `review/web/src/app.css` (seal keyframes, red-pen styles)

**Interfaces:**
- Consumes: Task 6.
- **Behaviour and copy:**
  - The item page loads `getReview` next to `getItem`.
  - Every part with an `id` (the entry header, each example, collocation, usage, pitfall, thing) gets a `ReviewBar`:
    - "Looks right" approves and presses the seal.
    - While the viewer's approval is current, the button becomes "Approved" and a quiet "Undo" link sits beside it.
    - "Suggest a change" opens `SuggestForm` inline.
    - "Suggest removing it" and "Leave a note for Martin" open a comment box. For removal the comment is optional ("Why? (optional)"); for a note it is required.
  - Seals show each current approver's display name. An approval that isn't current shows as muted text: "<name> approved an earlier version".
  - **`SuggestForm`:**
    - Fields follow `reference.fields["<dataset>/<kind>"]`. Locked fields aren't shown.
    - A muted line under the form: "Spelling and ids can't change here. Leave a note for Martin if they're wrong."
    - `form` inputs are a select of form labels from `reference.forms`.
    - Under Japanese fields, each run from `unknownKanjiRuns` asks: "How is 猫 read?", with a hiragana input. The answers go in `furigana` and feed the preview's `extra`.
    - The preview uses `Sentence` and `Japanese` with the edited values.
    - "Send suggestion" posts. The API's message shows under the form on error. A 409 shows the stale message with a "Reload" button.
  - Open suggestions on a part are listed under it with `SuggestionCard`, newest first. Withdrawn ones are hidden; accepted or declined ones are muted with their status ("Accepted", "Declined").
  - No inline styles. Run `svelte-autofixer` on each component until it reports nothing.

- [ ] **Step 1: Write the failing tests.**
  - A component test in `review/web/src/lib/Seal.test.ts`, with vitest and `@testing-library/svelte` if already present. If it isn't, use Svelte 5's `mount` from `svelte` with jsdom: no new dependency. It checks:
    - the seal renders the name;
    - it has the `press` class only after `pressed` flips;
    - it never has `press` when `matchMedia('(prefers-reduced-motion: reduce)')` matches.
  - `RedPen.test.ts`: a changed `jp` renders one `<del>` with `に` and one `<ins>` with `へ`.
- [ ] **Step 2: Run them to see them fail.** Run `npx vitest run src/lib`.
- [ ] **Step 3: Build the components and wire up the item page.**
- [ ] **Step 4: Run the web checks.** Run `npm run check && npm test -- --exclude src/csp.test.ts && npm run build && npm run test:csp`.
- [ ] **Step 5: Look at it** in the `review-web-build` preview with the mock:
  - On たべる, approve the entry and an example, and watch the seal press.
  - Suggest a change to an example's English and see the red pen.
  - Suggest removing a collocation, and leave a note on the entry.
  - Check at 375 px and on desktop.
  - With reduced motion emulated, check that the seal appears without the press.
- [ ] **Step 6: Commit.** `git commit -m "review/web: approve with a seal, suggest changes and removals, and see others' reviews on every item"`

---

### Task 8: Queues for reviewers: home stacks and the review card

**Files:**
- Create in `review/web/src/`:
  - `lib/QueueStack.svelte`: a small paper stack with title, "12 of 30 done" and a progress bar. Done is ink; a red segment shows `with_suggestion`.
  - `lib/ReviewCard.svelte`: one queued item in the card style.
  - `routes/queue/+page.svelte`: reads `?id=` in `onMount`.
- Modify: `review/web/src/routes/+page.svelte`, `review/web/src/routes/browse/[dataset]/+page.svelte` (via `BrowseList.svelte`: "2 of 5 approved" and "1 open suggestion" per row from `approved`/`targets`/`open`), `review/web/src/csp.test.ts` (adds `queue.html`)

**Interfaces:**
- Consumes: Tasks 6 and 7 (`ReviewBar` and `SuggestForm` are reused inside the card).
- **Behaviour and copy:**
  - **Home:** "Waiting for you" lists `listQueues()` as `QueueStack`s linking to `/queue?id=…`. With no queues it keeps today's empty text. A queue with everything done shows "All done, thank you".
  - **`/queue`, one column (phones):**
    - The queue's title and progress, then the `ReviewCard` for the first item without `mine` and not gone.
    - The card shows what the item is (from `labels.ts`, e.g. "Example on たべる (食べる)").
    - The sentence on the genkō grid, with the English below.
    - The owner's note in a quiet box ("Martin asks: …").
    - "Looks right" and "Suggest a change" as the two main buttons; "Not sure, skip" and "Suggest removing it" as quieter links. "Leave a note for Martin" sits in the same quiet row.
    - After any action the next undone item slides in. Reduced motion means no slide.
    - When every item is done: "That's everything in this queue. Thank you!" with a link home.
    - Other reviewers' approvals and suggestions on the item show under the card, as on the item page.
  - **`/queue`, laptops (≥ 960px), two panes:**
    - Left: the queue's items in order, each marked done, approved (a small red dot), suggested or skipped, with the current item highlighted.
    - Right: the card.
    - Clicking an item on the left opens it on the right, done ones included.
  - The item's entry is fetched with `getItem` and `getReview`, and the part picked with `partOf`. Entries already fetched in this visit are cached in memory.

- [ ] **Step 1: Add `queue.html` to `csp.test.ts`, and see it fail after a build.** Run `npm run build && npm run test:csp`. Expected: FAIL.
- [ ] **Step 2: Build the components and pages.**
- [ ] **Step 3: Run the web checks.** Run `npm run check && npm test -- --exclude src/csp.test.ts && npm run build && npm run test:csp`.
- [ ] **Step 4: Look at it** with the mock, after creating a queue through the admin page (Task 9) or a seeded mock queue:
  - Work through five items on a 375 px phone viewport and at desktop width.
  - Check the progress bar and its red segment, the two-pane layout, skipping, the done message, and reduced motion.
- [ ] **Step 5: Commit.** `git commit -m "review/web: queues on the home page and one-at-a-time review cards"`

---

### Task 9: The owner's inbox and queue builder; docs

**Files:**
- Create: `review/web/src/routes/admin/inbox/+page.svelte`, `review/web/src/routes/admin/queues/+page.svelte`
- Modify:
  - `review/web/src/routes/admin/+page.svelte`: links to "Suggestions (3 open)" and "Queues".
  - `review/web/src/csp.test.ts`: adds `admin/inbox.html` and `admin/queues.html`.
  - `review/README.md`: "Reviewing" and "Queues" sections. Also: after merge, run `npm run migrate` for 0004.
  - `AGENTS.md`: only if a command changed.

**Interfaces:**
- Consumes: Tasks 5–7 (`RedPen`, `SuggestionCard`, `SuggestForm` in admin mode).
- **Inbox:**
  - Tabs: "Open", "Accepted", "Declined".
  - Each suggestion shows the item title (linking to its item page, at `#<id>` for a part) and the author.
  - **Change:** a red-pen diff of `current` → `proposed`, furigana additions ("猫 read as ねこ") and dropped blanks.
  - **Delete:** "Remove this example".
  - **Note:** the comment in a quiet box.
  - "Changed since" and "No longer in the data" labels.
  - The comment thread.
  - Actions: "Accept", "Edit then accept", "Reply" and "Decline".
    - "Edit then accept" opens `SuggestForm` pre-filled with the proposed values. A stale suggestion is pre-filled from the current item, with the proposal shown beside it.
    - Accept is disabled on a stale change, with the accept-stale message as its hint.
    - Accepting a whole-verb or word delete shows the warning in a confirm step, with "Accept and remove" in red.
  - Suggestions on the same item are grouped together, so counter-suggestions sit side by side.
- **Queue builder:**
  - Inputs: a title and description; a dataset select; kind checkboxes ("Entries", "Examples", "Common phrases", "Usages", "Pitfalls", "Things counted"), showing only kinds that exist in the dataset; JLPT checkboxes; "Never approved"; and a "Paste ids" textarea.
  - "Preview" shows the count, the first 50 titles and the unmatched lines.
  - "Create queue" saves it.
  - Below: the existing queues with progress, archive and unarchive, edit title and description, and per item a note field ("Your question for reviewers") and "Remove".
- Reviewers get 403 on these pages' API calls. The pages sit under `/admin*`, behind the admin Access application.

- [ ] **Step 1: Add the two pages to `csp.test.ts`, and see it fail after a build.**
- [ ] **Step 2: Build the pages.** Run `svelte-autofixer` on each.
- [ ] **Step 3: Run every check.** Run `make review-test && make test-py && make check-project`, then `cd review/web && npm run build && npm run test:csp`.
- [ ] **Step 4: Look at it** with the mock as admin:
  - Build a queue from N5 verb examples with a note.
  - As a reviewer (`MOCK_ROLE=reviewer`), approve one and suggest a change on another.
  - Back as admin, reply and accept, then edit then accept a stale one (reload mock data with `MOCK_LOADED=1` after editing it), and decline one.
  - Check the inbox at 375 px.
- [ ] **Step 5: Commit.** `git commit -m "review/web: the owner's inbox and queue builder; docs for reviewing"`
- [ ] **Step 6: After merge (owner):** run `npm run migrate` in `review/api` for migration 0004, wait for Workers Builds and Pages, then build a first small queue.
