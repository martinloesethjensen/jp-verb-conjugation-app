# Review site, plan 5: the add path

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reviewers suggest new items: new parts on any entry, and new entries in every dataset.
- **New parts:** an example sentence, a common phrase, a thing counted, a usage, a pitfall.
- **New entries:** a verb, a word, a counter, a grammar point.

The owner rules on additions in the same inbox as other suggestions.

**Architecture:**
- **A fourth action, `add`.** An addition is a suggestion with `action = 'add'`. It reuses everything from plan 4: storage, comments, withdraw, the inbox, Accept, Edit then accept, Reply and Decline.
- **One pure function builds the item.** It turns the reviewer's fields into a whole new item that `update_data.py` would accept once its generated fields are filled in. It assigns ids, adds empty placeholders for generated fields, and checks the result against the strict types. It lives in `proposal.rs` beside `build_change`.
- **Ids are assigned when the suggestion is made:**
  - A part gets a fresh stable id, the same 6-character kind `stable_ids.py` makes.
  - A new verb gets its id by the verb-id rules.
  - A new word gets `class:dict`.
  - A new counter or grammar point gets the slug the reviewer types.

  Export (plan 6) keeps these ids, so nothing needs renumbering.
- **Nothing reaches `data/` here.** Accepting only marks the suggestion accepted.

**Tech Stack:** as plans 3, 3b and 4. No new crates or npm packages.

**Spec:** `docs/superpowers/specs/2026-10-27-data-review-site-design.md`. The relevant sections:
- Goals
- Decided by the owner ("Adding covers all data types")
- D1 tables
- Ids are frozen ("Adding new verbs and words is unrestricted")
- Furigana for new kanji
- Validation
- Screens: "Suggest / add forms" ("no conjugation engine in the site")
- Exporting accepted work

Earlier plans: `2026-11-05-review-site-4-review-path.md` (merged, #206).

## Roadmap

1. Stable ids (#181).
2. Schemas and skeleton (#190).
3. The read path (#195).
4. The review path (#206).
5. **This plan: the add path.**
6. Export.
7. Stamps for verbs, words and examples.

## Global Constraints

- **Everything in plans 3 and 4 still holds:**
  - Access, then D1, then Origin.
  - About 10 ms of CPU per request (Workers Free).
  - No inline styles (CSP).
  - No secrets or emails in committed files.
  - The site never writes `data/` and never signs.
  - Text fields are trimmed, at most 2000 characters, and required fields can't be empty.
  - Furigana additions follow plan 4's rules.
- **What can be added, and where it goes.** A new part is appended to the end of its parent's list.

  | dataset/kind | parent kinds | list it joins |
  |---|---|---|
  | verbs/example | entry | `examples` |
  | verbs/collocation | entry | `collocations` |
  | counters/thing | entry | `things` |
  | counters/example | entry, pitfall | `examples` |
  | counters/pitfall | entry | `pitfalls` |
  | grammar/usage | entry | `usages` |
  | grammar/example | usage, pitfall | `examples` |
  | grammar/pitfall | entry | `pitfalls` |
  | verbs/entry, words/entry, counters/entry, grammar/entry | none | the dataset's list |

  Contrast examples can't be added: a contrast has no stable id to hang them on.
- **Add fields per target.** Each row lists the fields in order, with its input type in brackets; "opt" means optional. `kana` is a `text` input that also must be kana.

  | dataset/kind | fields |
  |---|---|
  | verbs/entry | `dict` (kana), `kanji` (text, opt), `type` (choice), `meaning`, `description` (long), `notes` (long), `jlpt`, `teGroup` (choice, opt), `masu_pos`, `masu_neg`, `masu_past`, `masu_past_neg`, `te`, `short_pos`, `short_neg`, `short_past`, `short_past_neg` (kana), `example_form` (form), `example_jp`, `example_en` |
  | words/entry | `class` (choice: `i-adjective`, `na-adjective`, `noun`), `dict` (kana), `kanji` (text, opt), `meaning`, `jlpt` |
  | counters/entry | `id` (slug), `counter`, `reading` (kana), `meaning`, `jlpt`, `sound` (choice: `h-b`, `h-p`, `irregular`, `k`, `plain`, `s`), `symbol` (text, default `number`) |
  | grammar/entry | `id` (slug), `title`, `summary` (long), `jlpt`, `usage_heading`, `usage_explanation` (long), `example_jp`, `example_en` |
  | grammar/usage | the plan 4 change fields, plus `example_jp` and `example_en` |
  | every other part | the plan 4 change fields for that `(dataset, kind)` |

  Some fields aren't stored under their own name:
  - The `example_*`, `usage_*` and verb form fields are placed by the builder.
  - A verb's `label` is derived from `type`: `ru` gives `Ru-verb`, `u` gives `U-verb`, `irr.` gives `Irregular`.
  - New input kinds: `kana` (hiragana or katakana, plus ー) and `slug` (`^[a-z0-9]+(-[a-z0-9]+)*$`, at most 40 characters).
- **Generated fields get empty placeholders,** so the strict types pass. `update_data.py` fills them at export.
  - Verb `forms` holds only the nine typed basic forms.
  - Word `forms` is `{}`.
  - Counter `overrides`, `readings` and `distractors` are `{}`; `things`, `examples`, `pitfalls`, `related` and `changed` are `[]`.
  - Grammar `attachment`, `conjugations`, `pitfalls` and `related` are `[]`.
- **First parts.** A new verb comes with one example, and a new grammar point with one usage holding one example. A new usage comes with one example. These are the parts `update_data.py` and the app require. Each first part gets its own fresh stable id.
- **Ids:**
  - **A stable id** is 6 characters from `abcdefghijkmnpqrstuvwxyz23456789`. It must not be used by any loaded item in the dataset, or by any open or accepted addition in the dataset. The Worker draws one with `getrandom` and retries up to 8 times.
  - **A verb id** is the kana `dict`. If an existing verb (or an open or accepted addition) already uses it, the id is `dict:kanji`. Without kanji, that's an error: "<dict> is already a verb; add its kanji so the new one gets its own id".
  - **A word id** is `class:dict`.
  - **A counter or grammar id** is the slug.
  - **A taken entry id** gives 409: "<id> is already in the data". An open addition with the same entry id gives 409: "someone already suggested adding <id>; reply on their suggestion instead".
- **Stale and gone, for additions:**
  - An addition is never stale.
  - A part addition is `gone` when its parent left the data. Plain Accept of a gone addition gives 404: "the place this was added to isn't in the loaded data".
  - An addition is `landed` once its new id is among the loaded items (after export and reload). The inbox labels it "Now in the data".
- **Messages.** Exact API strings:
  - "<field> must be written in kana"
  - "<field> must be lowercase letters, digits and hyphens"
  - "<kind> can't be added there"
  - The id messages above.
- **Copy:**
  - Buttons: "Add an example", "Add a common phrase", "Add a thing counted", "Add a usage", "Add a pitfall", "Suggest a new verb" (likewise word, counter, grammar point), and "Suggest adding it" to submit.
  - A pending addition reads "<name> suggests adding this", with "New" as its status chip.
  - Under every add form: "Forms and readings that the app works out are added when Martin exports this."

## Review Focus

- **Double taps:**
  - Submitting the same addition twice on a slow phone returns the first one (200), not a duplicate with a second fresh id.
  - The duplicate check compares the item without its ids.
  - Tests in Tasks 1 and 3.
- **The same new entry suggested twice:**
  - Two reviewers add 来る → the second gets the 409 "someone already suggested adding…".
  - Adding a verb whose kana matches an existing one: with kanji, the new verb gets `dict:kanji`; without, the error above.
  - Tests in Tasks 2 and 3.
- **The parent leaves the data:**
  - An addition on an example under a pitfall that's then removed shows "No longer in the data".
  - Plain Accept is refused, and the item page and inbox still render it.
  - Tests in Tasks 3 and 5.
- **Stable id collisions:**
  - A generated id never repeats a loaded id or an open addition's id, even when the random source hits a taken id.
  - The test injects a sequence of candidates.
  - Test in Task 2.
- **Kanji with no reading in a new verb's dictionary form or example:** the form asks for the reading, and the reading travels with the addition. Tests in Tasks 3 and 6.

---

### Task 1: Store additions (migration 0005)

**Files:**
- Create: `review/api/migrations/0005_additions.sql`
- Modify: `review/api/src/review_store.rs`, `review/api/src/d1.rs`, `review/api/tests/support/sqlite.rs`
- Test: `review/api/tests/review_store.rs`

**Interfaces:**
- Consumes: plan 4's `suggestions` table and `ReviewStore`.
- Produces:
  - **Migration.** It rebuilds `suggestions` because SQLite can't change a CHECK. It runs `PRAGMA defer_foreign_keys = true`, creates `suggestions_new` with `action CHECK IN ('change','delete','note','add')` and three new nullable columns, copies the rows, then drops, renames and recreates the indexes:
    - `parent_kind TEXT`
    - `parent_id TEXT`
    - `fingerprint TEXT`, the canonical JSON of an addition's item without its ids, used to find duplicates.
  - `NewSuggestion` gains `parent_kind: Option<String>`, `parent_id: Option<String>` and `fingerprint: Option<String>`.
  - `Suggestion` gains `parent_kind`, `parent_id` and `landed: bool`. `stale` and `gone` follow the Global Constraints rule for adds:
    - An add is never stale.
    - A part addition is gone when no item matches `(dataset, parent_kind, parent_id)`.
    - An entry addition is never gone.
    - `landed` means an item `(dataset, kind, item_id)` exists.
  - `SELECT_IDENTICAL_OPEN` matches adds by `fingerprint` (with `author`, `dataset`, `kind`, `parent_id`) instead of `item_id` and `proposed_json`.
  - New `ReviewStore` functions:

    ```rust
    async fn id_in_use(&self, dataset: &str, id: &str) -> Result<bool, StoreError>; // any loaded item_id, or an open/accepted add's item_id
    async fn open_add_for(&self, dataset: &str, kind: &str, item_id: &str) -> Result<Option<i64>, StoreError>;
    async fn additions(&self, dataset: &str, viewer: &str) -> Result<Vec<Suggestion>, StoreError>; // kind 'entry' adds, not withdrawn, newest first
    ```

  - For a part addition, `entry_id` is the parent's entry, so `entry_review` and `review_counts` pick it up unchanged. For an entry addition, `entry_id` is the new id.

- [ ] **Step 1: Write the failing tests** (SQLite, real data, as in plan 4).
  - `an_addition_is_stored_with_its_parent`: a verb-example add on たべる has `action "add"`, `parent_kind "entry"`, `parent_id "たべる"`, `stale false`, `gone false` and `landed false`, and it's listed in `entry_review("verbs","たべる")`.
  - `the_same_addition_twice_is_one_row`: two adds with the same author, parent and fingerprint, but different `item_id`s, return the same id with `created == false`.
  - `a_part_addition_goes_when_its_parent_goes`: reload verbs without たべる, and the add has `gone == true`.
  - `an_addition_lands_after_export`: reload words with a new word whose id matches an entry add's `item_id`, and it has `landed == true`.
  - `ids_in_use_cover_items_and_pending_additions`:
    - a loaded example id → true;
    - an open add's id → true;
    - a withdrawn add's id → false;
    - an unknown id → false.
  - `additions_lists_new_entries_only`: one entry add and one part add in words and verbs; `additions("verbs")` lists only the verb entry add.
  - `the_migration_keeps_existing_suggestions`: insert a plan-4-shaped suggestion and comment, run 0005, and both are still readable with `parent_kind == None`. Build the store from migrations 0001–0004, insert, then apply 0005.
- [ ] **Step 2: Run them to see them fail.** Run `cd review/api && cargo test --test review_store`.
- [ ] **Step 3: Write the migration, the SQL and both implementations.**
- [ ] **Step 4: Run the checks.** Run `cargo test --test review_store --test review_api --test inbox_api --test queues_api && cargo clippy --all-targets -- -D warnings && cargo clippy --target wasm32-unknown-unknown -- -D warnings`.
- [ ] **Step 5: Commit.** `git commit -m "review/api: store suggested additions with their parent"`

---

### Task 2: Building a new item (`proposal.rs`, pure)

**Files:**
- Modify: `review/api/src/proposal.rs`
- Test: `review/api/tests/additions.rs`

**Interfaces:**
- Consumes: `Field`, `Input`, `find_part`, `check_furigana` and the text rules from plan 4. `check_entry` and the strict part types.
- Produces:
  - `Input` gains `Kana` and `Slug` (serde: `"kana"`, `"slug"`). A `Field` may carry a default (`default: Option<&'static str>`, serialised); only counter `symbol` has one.
  - `fn add_fields(file: DataFile, kind: Kind) -> &'static [Field]`, per the Global Constraints table.
  - `fn add_parents(file: DataFile, kind: Kind) -> &'static [Kind]`. Empty for entries.
  - `fn addable_targets() -> Vec<(String, &'static [Field])>`, like `editable_targets`.
  - The builder:

    ```rust
    pub struct NewItem { pub item: Value, pub item_id: String, pub fingerprint: String }
    pub fn build_add(file: DataFile, kind: Kind, parent: Option<(&Value, Kind)>, fields: &Map<String, Value>,
                     form_ids: &BTreeSet<String>, ids: &mut dyn FnMut() -> String,
                     taken: &dyn Fn(&str) -> bool) -> Result<NewItem, String>
    ```

    - `parent` is the parent object and its kind. For a verb example, the builder needs the verb's `forms`, so the parent is the verb entry.
    - `ids()` yields candidate stable ids.
    - `taken(id)` says whether an id is in use; it covers stable ids and entry ids.
  - **What it does:**
    1. Apply the text rules.
    2. Check `kana` and `slug` fields.
    3. Refuse unknown keys with plan 4's locked message.
    4. Build the item with its placeholders and first parts.
    5. Assign ids:
       - Take the first `ids()` candidate that isn't `taken`.
       - Give up after 8 tries with "couldn't pick a new id; try again".
       - Entry ids follow the Global Constraints rules, using `taken` for the verb `dict` collision.
    6. Check the result:
       - An entry with `check_entry`; a part with its strict type.
       - A verb example's `form` with plan 4's form check against `parent.forms`.
       - A new verb's first example is checked against the nine typed forms.
    7. `fingerprint` is the canonical JSON of the item with every `id` key removed, at any depth.
  - `fn random_stable_id() -> String`, which draws from `getrandom` (wasm via the `js` feature, as `new_load_id`).

- [ ] **Step 1: Write the failing tests.**
  - `a_new_example_on_a_verb`:
    - たべる with `{form: "te", jp: "食べてから寝ます。", en: "I eat, then sleep."}` gives an example with a 6-character id from the alphabet.
    - `form` must be one the verb has: "たべる has no nasai form" for a missing one.
  - `a_new_verb_gets_its_kana_id_or_a_kanji_id`:
    - `{dict: "はしる", …}` (unused) gets id `"はしる"` and no `id` key.
    - `{dict: "きる", kanji: "斬る"}`, with `taken("きる")` true, gets id `"きる:斬る"`, written as the item's `id`.
    - `{dict: "きる"}` without kanji gives the "already a verb" message.
  - `a_new_verb_has_placeholders_and_its_first_example`:
    - `label` is derived;
    - `forms` has exactly the nine typed keys;
    - `examples` has one item with a fresh id;
    - `check_entry(Verbs, …)` passes.
  - `a_new_grammar_point_has_one_usage_with_one_example`, with all three ids distinct.
  - `a_new_counter_uses_the_symbol_default`: no `symbol` given gives `"number"`; `{id: "Hiki"}` gives the slug message.
  - `kana_fields_are_checked`: `{dict: "走る"}` gives "dict must be written in kana".
  - `ids_skip_taken_candidates`:
    - `ids` yields `"aaaaaa"`, `"bbbbbb"`, `"cccccc"` while `taken` covers the first two: the id is `"cccccc"`.
    - All candidates taken gives the give-up message.
  - `the_fingerprint_ignores_ids`: two builds with different id sequences have the same fingerprint.
  - `parents_are_checked`: a `grammar/example` with parent kind `entry` gives "example can't be added there".
  - `every_addable_target_builds_against_real_data`: for each `addable_targets()` pair, a minimal valid field set builds without error against a real parent from `data/`.
- [ ] **Step 2: Run them to see them fail.** Run `cargo test --test additions`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the checks.** Run `cargo test --test additions --test proposal && cargo clippy --all-targets -- -D warnings`.
- [ ] **Step 5: Commit.** `git commit -m "review/api: build a suggested new item with its ids and placeholders"`

---

### Task 3: The add API

**Files:**
- Modify: `review/api/src/review_routes.rs`, `review/api/src/app.rs`
- Test: `review/api/tests/add_api.rs` (seeded through `tests/support/review.rs`)

**Interfaces:**
- Consumes: Tasks 1–2, and plan 4's `reference_sets`, `suggestion_response` and `decide`.
- Produces:

  | Method, path | Need | Body or query | Success |
  |---|---|---|---|
  | `POST /api/add` | Reviewer | `{dataset, kind, parent?: {kind, id}, fields: {…}, furigana?: {…}, comment?: string}` | 201 the `Suggestion` (200 for an identical open one) |
  | `GET /api/additions` | Reviewer | `?dataset=` | 200 `{"suggestions": [Suggestion…]}` (new entries) |

  - **Rules:**
    - A part's `parent` must be loaded and of an allowed kind. Otherwise 404 with plan 4's not-loaded message, or 400 "<kind> can't be added there".
    - An entry addition takes no `parent`.
    - `taken` checks `id_in_use` for stable ids, and the dataset's loaded entry ids plus `open_add_for` for entry ids.
    - Furigana follows plan 4's rules.
    - `base_hash` is `""`.
    - `item_title`:
      - an entry's is its display title (`entryTitle` rules: `dict (kanji)`, `counter (reading)`, grammar `title`);
      - an example's or common phrase's is its `jp`;
      - a usage's or pitfall's is its `heading`;
      - a thing's is its `word`.
  - **`POST /api/admin/decide` on an addition:**
    - Plain accept is refused while `gone`.
    - `edits` rebuilds the item with `build_add`. The new values are the proposal's fields with the edits applied, and the item keeps its ids: `ids` yields the proposal's existing ids in order. The result is stored as `admin_edit_json`.
  - `GET /api/reference` gains `"add_fields": {"verbs/example": [Field…], …}` and `"add_parents": {"counters/example": ["entry","pitfall"], …}`.
  - `GET /api/admin/inbox` items for additions have `current: null`. The page shows the proposal itself.

- [ ] **Step 1: Write the failing tests.**
  - `a_reviewer_adds_an_example_and_everyone_sees_it`:
    - aiko adds a たべる example: 201, action `add`, `item_title` is the sentence.
    - ben's `GET /api/review?dataset=verbs&id=たべる` lists it.
    - `GET /api/items` gives たべる `open == 1`.
  - `the_same_addition_twice_returns_the_first`: 201 then 200, with the same id.
  - `an_example_under_a_pitfall`: a counters example with parent `{kind: "pitfall", id: "pe3v3c"}` gives 201 with `parent_id "pe3v3c"`, and `entry_id` is that pitfall's entry.
  - `wrong_parents_are_refused`:
    - an unknown parent id gives 404;
    - a grammar example on the entry gives 400;
    - an entry add with a `parent` gives 400.
  - `new_entries_and_duplicates`:
    - aiko adds the word `{class: "noun", dict: "ねこ", kanji: "猫", meaning: "cat", jlpt: "N5"}`: 201, item_id `noun:ねこ`.
    - ben adds the same: 409 "someone already suggested adding noun:ねこ; reply on their suggestion instead".
    - Adding `i-adjective:いい` gives 409 "i-adjective:いい is already in the data".
    - `GET /api/additions?dataset=words` lists the cat.
  - `a_new_verb_with_kanji_asks_nothing_when_readings_are_known_and_carries_new_ones`: a new verb whose kanji isn't in `furigana.json` passes with `furigana: {"<kanji>": "<reading>"}`, and the suggestion carries it.
  - `the_owner_edits_then_accepts_an_addition`:
    - Accept with `edits: {en: "…"}` stores `admin_edit` with the new `en` and the same ids as `proposed`.
    - A removed parent makes a plain accept 404 with the "place this was added to" message.
  - `reference_serves_add_fields`:
    - `add_fields["verbs/entry"]` includes `masu_pos`, and `dict` with input `"kana"`;
    - `add_parents["grammar/example"] == ["usage","pitfall"]`;
    - `counters/entry` `symbol` has default `"number"`.
  - `reviewers_cannot_add_with_a_foreign_origin`: 403.
- [ ] **Step 2: Run them to see them fail.** Run `cargo test --test add_api`.
- [ ] **Step 3: Implement the routes.**
- [ ] **Step 4: Run the checks.** Run `cargo test && cargo clippy --all-targets -- -D warnings && cargo clippy --target wasm32-unknown-unknown -- -D warnings && worker-build --release`.
- [ ] **Step 5: Commit.** `git commit -m "review/api: suggest new items and new entries; the owner rules on them in the inbox"`

---

### Task 4: Page helpers and the mock

**Files:**
- Modify: `review/web/src/lib/api.ts`, `review/web/src/lib/api.test.ts`, `review/web/src/lib/labels.ts`, `review/web/src/lib/targets.ts`, `review/web/src/lib/targets.test.ts`, `review/web/src/dev/mock-review.ts`

**Interfaces:**
- Consumes: Task 3's routes.
- Produces:
  - **`api.ts`:**
    - `Suggestion` gains `parent_kind`, `parent_id` and `landed`. `SuggestionAction` gains `'add'`.
    - `Field` gains `input: 'kana' | 'slug'` and `default?: string`.
    - `Reference` gains `add_fields` and `add_parents`.
    - `addItem(dataset, kind, parent: { kind: string; id: string } | null, fields, extra: { furigana?, comment? })`.
    - `getAdditions(dataset)`.
  - **`targets.ts`:** `leftBehind` leaves additions out. They're pending, not left behind.
  - **`labels.ts`:**
    - Field labels for the add-only fields: "Dictionary form", "Kanji", "Verb type", "Polite (ます)", "Polite negative", "Polite past", "Polite past negative", "て-form", "Plain", "Plain negative", "Plain past", "Plain past negative", "First example: form", "First example: Japanese", "First example: English", "First usage: heading", "First usage: explanation", "Id (lowercase, hyphens)", "Counting sound", "Symbol".
    - `ADD_LABELS`, the button text per `dataset/kind` (Global Constraints copy).
  - **Mock:** `/add` and `/additions` with in-memory ids, enough to click through. It doesn't run the full builder; it fills in the ids and placeholders the pages show.

- [ ] **Step 1: Write the failing tests.**
  - `api.test.ts`: `addItem('counters','example',{kind:'pitfall',id:'pe3v3c'},{jp:'a',en:'b'})` POSTs `/api/add` with exactly `{dataset, kind, parent, fields}`.
  - `targets.test.ts`: `leftBehind` with an open add whose item id isn't among the parts returns nothing.
- [ ] **Step 2: Run them to see them fail.** Run `cd review/web && npx vitest run src/lib`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the checks.** Run `npx vitest run src/lib && npm run check`.
- [ ] **Step 5: Commit.** `git commit -m "review/web: add API calls, add-field labels, and the mock's add routes"`

---

### Task 5: Adding parts on the item page

**Files:**
- Create: `review/web/src/lib/AddPart.svelte`, the "Add an example" button with its form for one parent and kind
- Modify:
  - `review/web/src/lib/SuggestForm.svelte`: input types `kana` and `slug`, and field defaults, used when `current` is `{}`.
  - `review/web/src/lib/SuggestionCard.svelte`: an add shows "<name> suggests adding this", the "New" chip, and "Now in the data" when `landed`. It previews the item with `PartView` instead of a red pen.
  - `review/web/src/lib/review.svelte.ts`: `EntryReview.additionsUnder(parentKind, parentId, kind)` and `add(...)`.
  - `review/web/src/routes/item/+page.svelte`

**Interfaces:**
- Consumes: Task 4, and plan 4's `SuggestForm`, `SuggestionCard`, `PartView` and `EntryReview`.
- **Behaviour:**
  - Every list on the item page that accepts additions ends with its add button: examples, common phrases, things, usages, pitfalls, and a pitfall's or usage's examples. The page reads `add_parents`, so lists that take no additions (contrast examples) have none.
  - The button opens `SuggestForm` with `fields = add_fields["<dataset>/<kind>"]`, `current = {}`, `initial` = the field defaults, and `submitLabel` "Suggest adding it". The form shows the "Forms and readings…" line.
  - Pending additions show at the end of their list as `SuggestionCard`s, newest last. Withdrawn ones are hidden.
  - The furigana questions and the live preview work as in plan 4. The preview uses `Sentence` for `jp`/`en` items, and `PartView` with the proposed item otherwise.
  - Run `svelte-autofixer` on each changed component.

- [ ] **Step 1: Write the failing test.** `SuggestionCard` server render: an `add` suggestion renders "suggests adding this" and "New", and no `<del>`.
- [ ] **Step 2: Run it to see it fail.** Run `npx vitest run src/lib`.
- [ ] **Step 3: Build it.**
- [ ] **Step 4: Run the web checks.** Run `npm run check && npm test -- --exclude src/csp.test.ts && npm run build && npm run test:csp`.
- [ ] **Step 5: Look at it** in the built site with the mock:
  - Add an example to たべる.
  - Add an example under a counter pitfall.
  - Add a usage to a grammar point.
  - Check that a pending addition appears where it would go.
  - Check at 375 px.
- [ ] **Step 6: Commit.** `git commit -m "review/web: suggest new examples, phrases, things, usages and pitfalls on the item page"`

---

### Task 6: New entries, the inbox, and docs

**Files:**
- Create: `review/web/src/routes/add/+page.svelte`. It reads `?dataset=` in `onMount` and shows the new-entry form.
- Modify:
  - `review/web/src/lib/BrowseList.svelte`: a "Suggest a new verb" (etc.) link, and a "Suggested additions" list from `getAdditions` above the items.
  - `review/web/src/routes/admin/inbox/+page.svelte`: additions grouped under their parent. The heading is "New <kind> on <parent title>", or "New verb" for entries. Accept, Edit then accept (with `add_fields`, pre-filled from the proposal), Reply and Decline. Accept is disabled while `gone`.
  - `review/web/src/csp.test.ts`: adds `add.html`.
  - `review/README.md`: an "Adding" section, and `npm run migrate` for 0005 after merge.
  - The spec's "Exporting accepted work" section, with the addition contract plan 6 reads:
    - `action add`;
    - `parent_kind` and `parent_id`;
    - the item, with ids, in `admin_edit_json` if set, else `proposed_json`;
    - placement at the end of the parent's list;
    - placeholders that `update_data.py` regenerates.

**Interfaces:**
- Consumes: Tasks 3–5.
- **Behaviour:**
  - `/add?dataset=verbs` shows "Suggest a new verb" with the verb add fields in their table order. The nine forms sit under "Forms you know" and the first example under "First example".
  - The preview shows the entered fields with `PartView`. Generated forms aren't shown.
  - On success the page shows "Sent. Martin will look at it." with links back to browse and to add another.
  - A 409 duplicate shows its message, plus a link to the browse page where the earlier suggestion is listed.

- [ ] **Step 1: Add `add.html` to `csp.test.ts`, and see it fail after a build.**
- [ ] **Step 2: Build the page, the browse additions list and the inbox rendering.** Run `svelte-autofixer` on each.
- [ ] **Step 3: Run every check.** Run `make review-test && make test-py && make check-project`.
- [ ] **Step 4: Look at it** with the mock:
  - Suggest a new word and a new verb with a kanji the snapshot lacks; answer the reading question.
  - Try the same word again.
  - As admin, edit then accept the verb, and decline the word.
  - Check at 375 px.
- [ ] **Step 5: Commit.** `git commit -m "review/web: suggest new verbs, words, counters and grammar points; additions in the inbox; docs"`
- [ ] **Step 6: After merge (owner):** run `npm run migrate` in `review/api` for 0005, and wait for Workers Builds and Pages.
