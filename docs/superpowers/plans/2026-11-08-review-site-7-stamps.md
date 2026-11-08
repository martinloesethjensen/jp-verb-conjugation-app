# Review site 7: stamps for verbs, words and examples Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Verbs, words and individual verb example sentences can carry the same `review` stamp that counters and grammar points already have. The stamp goes from a full approval on the site, through `make review-pull`, into `data/`, and the app shows it.

**Architecture:**
- **What each stamp covers:**
  - A verb's stamp covers its authored fields and its collocations. It leaves out the generated `forms` and the `examples`.
  - Each verb example has its own stamp, covering that example's JSON.
  - A word's stamp covers everything except the generated `forms`.
- **Shared rules, mirrored once per language:**
  - Python keeps the hash rules in one table, `update_data.STAMP_GENERATED`.
  - The Worker keeps them in `items::excluded_from_entry_hash`.
  - The Worker decides what a stamp needs approved through one SQL fragment, `covered!()`.
- **App:** the existing `ReviewStatusPill` appears on the verb page. A small check appears on reviewed example rows. Settings and the verb list count the reviewed items.
- **No `data/` change in this plan.** Nothing gets stamped here. The first real stamps arrive through a later `make review-pull`, which the owner signs as usual.

**Tech Stack:**
- Python 3 standard library (`unittest`)
- Rust (workers-rs, D1, the SQLite test store)
- SvelteKit 2 / Svelte 5 static pages (vitest)
- Swift (VerbKit, SwiftUI)

**Spec:** `docs/superpowers/specs/2026-10-27-data-review-site-design.md`. The parts this plan implements:
- "Delivery order" step 7;
- "Fits what exists: review stamps", the scope gap.

Also: `docs/superpowers/specs/2026-10-27-review-status-design.md`, the stamp contract and the app wording.

## Decisions (owner, 2026-11-08)

1. **Examples are reviewed separately:** each verb example has its own stamp, and the verb's stamp leaves them out.
2. **Common phrases are part of the verb's stamp:** editing one un-reviews the verb.
3. **Words:** stamps in the data and on the site. In the app, only a count in Settings › Content review.
4. **A reviewed example shows a small check** in the theme's "good" colour. Unreviewed examples show nothing.

## Global Constraints

- **Signing:** never run `make data-release`, `make sign-commit` or `make review-pull`. This plan writes nothing under `data/`. `make data-check` must pass on the unchanged data at every commit.
- **Stamp shape, unchanged:** `{"by": "owner"|"teacher"|"native", "on": "YYYY-MM-DD", "sha256": "<64 hex>", "name"?: "<1–40 chars>"}`.
- **Hashes:**
  - The hash is SHA-256 of the canonical JSON, `json.dumps(v, sort_keys=True, separators=(",", ":"), ensure_ascii=False)`. It always leaves out the object's own `review`, plus:
    - verb: `("forms", "examples")`;
    - word: `("forms",)`;
    - verb example: nothing else;
    - counters and grammar: unchanged.
  - Python and Rust must produce the same bytes.
- **Where example stamps are allowed:** only on verb examples (`verbs.json` → `verbs[].examples[]`). Grammar and counter examples stay covered by their entry's stamp. The schema rejects a `review` anywhere else.
- **Ids:**
  - verb: `ud.verb_id` (explicit `id`, else `dict`);
  - word: `"<class>:<dict>"`;
  - example: its stable `id`.
  - These are the ids the site's `items` table already uses.
- **App wording:** "Not yet reviewed" / "Reviewed" (owner decision, 2026-10-27). There is no per-row pill in lists. The only per-row marker is a check on a reviewed example, never a marker on an unreviewed one.
- **Hosting:** Workers Free, about 10 ms of CPU per request. Stamp readiness stays in SQL, with no extra item parsing in the Worker.
- **Pages:** CSP with no inline styles. Svelte 5 runes. Shared helpers over copies.
- **Migrations:** none. If one seems needed, stop and ask.
- **Commits** end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Python and Rust disagree on a verb, word or example hash.** Every site stamp would then be skipped as "changed since it was stamped". Expected: both produce the same hex for the same fixture. Tests:
   - Task 1 `test_hashes_match_the_worker_fixtures`;
   - Task 4 `verb_word_and_example_hashes_match_pythons`. Both pin the same constants.
2. **Writing an example's stamp disturbs another hash.** Expected: stamping an example changes neither the verb's stamp hash nor that example's hash on the site. Tests:
   - Task 1 `test_example_stamp_keeps_the_verb_stamp_valid`;
   - Task 4 `an_example_hash_ignores_its_review`.
3. **A batch changes one example of a verb that has stamps.** Expected:
   - that example's old stamp is removed and reported;
   - the verb's stamp and the other examples' stamps stay;
   - a requested stamp on the changed example is skipped.

   Test: Task 3 `test_example_change_removes_only_its_stamp`.
4. **Verb readiness and examples.** Expected:
   - A verb is ready when its entry row and collocations are approved, whatever its examples' state.
   - An open suggestion on an example doesn't block the verb. One on a collocation does.
   - An example is ready on its own approval alone.

   Test: Task 5 `verb_readiness_skips_examples_and_examples_stand_alone`.
5. **`dump_verbs` reformats the published file.** Expected: the unchanged `verbs.json` round-trips byte for byte, and a stamped example stays on one line. Test: Task 1 `test_dump_verbs_round_trips_and_keeps_a_stamped_example_on_one_line`.

---

### Task 1: Pipeline: stamps on verbs, words and verb examples

**Files:**
- Modify: `scripts/update_data.py`:
  - `REVIEWERS` block near line 1774: the new constants and `check_reviews`;
  - `run()`, the verbs and words sections;
  - `dump_verbs`, line 1557.
- Modify: `schema/verbs.schema.json` (add `$defs.reviewStamp`, copied from `counters.schema.json`; optional `review` on a verb and on a verb example), `schema/words.schema.json` (same def, optional `review` on a word)
- Modify: `schema/README.md` (where stamps may appear)
- Test: `scripts/test_update_data.py`, `scripts/test_schemas.py`

**Interfaces:**
- Produces:
  - `ud.VERB_GENERATED = ("forms", "examples")`
  - `ud.WORD_GENERATED = ("forms",)`
  - `ud.STAMP_GENERATED: dict[str, tuple]` = `{"counters": COUNTER_GENERATED, "grammar": (), "verbs": VERB_GENERATED, "words": WORD_GENERATED, "example": ()}`. The `"example"` key is for a verb example's own stamp.
  - `ud.word_id(word) -> str`, which returns `f"{word['class']}:{word['dict']}"`.
  - `ud.check_reviews(entries, generated=(), key=None)`. `key` maps an entry to the name used in messages, and defaults to `entry.get("id", "<no id>")`.

- [ ] **Step 1: Write the failing tests** in `scripts/test_update_data.py`, as a new class `VerbWordExampleStampTests`:
  - **`test_hashes_match_the_worker_fixtures`:**
    - Set `VERB = {"dict": "たべる", "kanji": "食べる", "type": "ru", "label": "Ru-verb", "meaning": "to eat", "description": "d", "jlpt": "N5", "forms": {"te": "たべて"}, "examples": [EXAMPLE], "collocations": [{"id": "c1aaaa", "jp": "ご飯を食べる", "en": "eat a meal"}]}`.
    - Set `EXAMPLE = {"id": "e1aaaa", "form": "te", "jp": "食べて", "en": "Eat."}` and `WORD = {"class": "i-adjective", "dict": "たかい", "kanji": "高い", "meaning": "tall", "forms": {"te": "たかくて"}}`.
    - Assert `review_hash(VERB, VERB_GENERATED)`, `review_hash(EXAMPLE)` and `review_hash(WORD, WORD_GENERATED)` equal three hex constants.
    - To get the constants, compute them once with the current `review_hash` and paste them. Record them in the ledger: Task 4 pins the same three.
  - **`test_example_stamp_keeps_the_verb_stamp_valid`:** stamp the verb, then add `"review"` to its example. `check_reviews` over the verb (with `VERB_GENERATED`) and over the example both return `[]`.
  - **`test_a_collocation_edit_makes_the_verb_stamp_stale`:** after the edit, `check_reviews([verb], VERB_GENERATED, key=verb_id)` returns one problem starting with `"たべる was edited after review"`.
  - **`test_run_rejects_a_stale_example_stamp`:** copy the real `data/` to a temp dir, as the existing `run()` tests do. Put a stamp with a wrong `sha256` on the first example of the first verb. `run(...)` returns exit code 1, and a message names that example's id and says "was edited after review".
  - **`test_run_accepts_valid_stamps_on_a_verb_an_example_and_a_word`:** same setup, with correct stamps. `run(..., check=False)` returns 0. `verbs.json` then still holds the example's stamp on one line.
  - **`test_dump_verbs_round_trips_and_keeps_a_stamped_example_on_one_line`:**
    - `dump_verbs(json.loads(published_text)) == published_text` for the real `data/verbs.json`.
    - With a stamp added to one example, that example's output is exactly one line: `{ "id": …, "form": …, "jp": …, "en": …, "review": { "by": "teacher", "on": "2026-11-08", "sha256": "…" } }`.

  In `scripts/test_schemas.py`:
  - **`test_review_stamps_are_allowed_only_where_the_pipeline_checks_them`:**
    - A stamp validates on a verb, a verb example and a word.
    - A stamp is rejected on a grammar example and on a counter example.
    - Use `json_schema` the way the other schema tests do.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python3 -m unittest scripts.test_update_data.VerbWordExampleStampTests scripts.test_schemas -v`
Expected: FAIL, because `VERB_GENERATED` is undefined, the schema rejects `review`, and the stamped example dumps on several lines.

- [ ] **Step 3: Implement**
  - Add the constants, `word_id` and the `key` parameter to `check_reviews`.
  - In `run()`, check stamps right after the verb ids are checked, and before any `apply_*`:
    - `check_reviews(verbs_doc["verbs"], VERB_GENERATED, key=verb_id)`;
    - `check_reviews([ex for v in verbs_doc["verbs"] for ex in v.get("examples", [])])`;
    - report problems under the heading "verbs.json has invalid review stamps:".
  - Inside the existing `words_doc` branch, run `check_reviews(words_doc["words"], WORD_GENERATED, key=word_id)` along with `check_words`.
  - Extend `dump_verbs` so an example whose last key is `review` renders on one line, with the stamp inline in `mark_reviewed._inline`'s style: `{ "by": …, … }`.
    - Move `_inline` into `update_data` as `inline_object(obj) -> str`. `mark_reviewed` then uses that, so the format lives in one place.
  - Update the schemas and `schema/README.md`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 -m unittest scripts.test_update_data scripts.test_schemas scripts.test_mark_reviewed -v`, then `make data-check`
Expected: all pass, and `make data-check` reports the data is up to date.

- [ ] **Step 5: Commit**

```bash
git add scripts/update_data.py scripts/mark_reviewed.py scripts/test_update_data.py scripts/test_schemas.py schema/
git commit -m "Pipeline: review stamps on verbs, words and verb examples"
```

### Task 2: `mark_reviewed.py` stamps verbs, words and examples

**Files:**
- Modify: `scripts/mark_reviewed.py`
- Test: `scripts/test_mark_reviewed.py`

**Interfaces:**
- Consumes: `ud.STAMP_GENERATED`, `ud.verb_id`, `ud.word_id`, `ud.dump_verbs`, `ud.dump_words`, `ud.inline_object` (Task 1).
- Produces: `stamp_entries(entries, ids, key, generated, by, on, name=None, noun="entry")`, a generic setter that mutates in place. `stamp_counters` becomes a call to it.
  - The CLI's `kind` accepts `counters`, `grammar`, `verbs`, `words`, `examples`.
  - `examples` stamps verb examples by their stable id, searching every verb.
  - An unknown id raises `ValueError(f"no {noun} with id {id!r}")`.

- [ ] **Step 1: Write the failing tests:**
  - `test_stamps_a_verb_by_its_id_leaving_others_alone`, with an explicit-id verb `"きる:切る"` and a plain one.
  - `test_stamps_an_example_by_its_stable_id`.
  - `test_stamps_a_word_by_class_and_dict` (`"i-adjective:たかい"`).
  - `test_unknown_example_id_is_an_error`, with the message `"no example with id 'zzzzzz'"`.
  - `test_main_writes_verbs_json_that_update_data_accepts`: in a temp copy of `data/`, `main(["examples", <first example id>, "--by", "teacher", "--on", "2026-11-08", "--data-dir", tmp])` returns 0. `ud.run(tmp, check=True)` then returns 0.

- [ ] **Step 2: Run them to verify they fail**

Run: `python3 -m unittest scripts.test_mark_reviewed -v`
Expected: FAIL, because `stamp_entries` is undefined and the argparse choices refuse `examples`.

- [ ] **Step 3: Implement** `stamp_entries` and the three new kinds. Verbs and examples write through `ud.dump_verbs`, and words through `ud.dump_words`. Update the module docstring's usage lines.

- [ ] **Step 4: Run them to verify they pass**

Run: `python3 -m unittest scripts.test_mark_reviewed -v`
Expected: PASS

- [ ] **Step 5: Commit** with the message `"mark_reviewed: verbs, words and verb examples"`.

### Task 3: `review_export` writes and clears the new stamps

**Files:**
- Modify: `scripts/review_export.py` (`STAMPED`, `entry_id`, stamp check (step 1), stamp write and stale sweep (step 6))
- Test: `scripts/test_review_export.py`

**Interfaces:**
- Consumes:
  - Task 1's `ud.STAMP_GENERATED`, `ud.verb_id`, `ud.word_id`.
  - A batch stamp row, which already carries `kind`, `item_id`, `entry_id` and `content_hash` (`export_routes.rs`).
- Produces: `stamp_target(docs, t) -> (obj, generated) | None`.
  - For `kind == "entry"`, it returns the entry and `STAMP_GENERATED[dataset]`.
  - For `kind == "example"` in `verbs`, it returns the example found with `locate` under `t["entry_id"]`, and `()`.
  - Otherwise it returns None and the stamp is reported as skipped: "can't be stamped".

- [ ] **Step 1: Write the failing tests.** Reuse the file's fixture helpers, and add a small verbs and words doc with stable ids.
  - **`test_writes_a_verb_stamp_and_an_example_stamp`:** both written, `update_data.check_reviews` clean on both, and both ids in `report.stamp_ids`.
  - **`test_writes_a_word_stamp`.**
  - **`test_example_change_removes_only_its_stamp`:**
    - Setup: the verb and examples A and B already stamped. The batch changes A's `en` and requests a new stamp on A.
    - Result: A's old stamp is removed and listed under `stamps_removed`, and the new stamp is skipped with "this batch also changes it".
    - The verb's and B's stamps are unchanged.
  - **`test_a_collocation_change_makes_the_verb_stamp_go`:** the verb's stamp is removed. The examples' stamps stay.
  - **`test_a_meaning_change_skips_a_requested_verb_stamp_but_not_an_example_stamp`.**
  - **`entry_id` consistency:** `entry_id` returns `ud.verb_id` / `ud.word_id` results. This is already covered by the existing tests, which must still pass.

- [ ] **Step 2: Run them to verify they fail**

Run: `python3 -m unittest scripts.test_review_export -v`
Expected: FAIL, with a `KeyError: 'verbs'` from `STAMPED`, or the stamp is not written.

- [ ] **Step 3: Implement**
  - Replace `STAMPED` with `ud.STAMP_GENERATED`.
  - Track what the batch touches as a set of `(dataset, kind, item_id)`, together with the entry each part belongs to.
  - A requested stamp is skipped when the batch touches anything it covers:
    - for counters, grammar and words, any part of the entry;
    - for a verb entry, the entry or a collocation;
    - for an example, that example.
  - The step-6 sweep re-hashes every existing stamp under each touched entry: the entry's own stamp and, for verbs, each example's. It removes the ones that no longer match, titled by the item's `item_title` when the batch has one, else its id.

- [ ] **Step 4: Run them to verify they pass**

Run: `python3 -m unittest scripts.test_review_export scripts.test_review_pull -v`, then `make test-py`
Expected: all pass.

- [ ] **Step 5: Commit** with the message `"review_export: write and clear stamps on verbs, words and examples"`.

### Task 4: Worker: data types and hashes

**Files:**
- Modify: `review/api/src/data.rs` (`review: Option<ReviewStamp>` on `Verb`, `VerbExample`, `Word`)
- Modify: `review/api/src/items.rs`:
  - `excluded_from_entry_hash`: Verbs becomes `&["review", "forms", "examples"]`;
  - `Rows::push`: a sub-item's hash leaves out its top-level `review`. The stored `json` keeps it.
- Test: `review/api/tests/items.rs`, `review/api/tests/data.rs`

**Interfaces:**
- Produces: `pub fn item_hash(value: &Value) -> String` in `items.rs`, which hashes the canonical JSON without the top-level `review`. `Rows::push` uses it for every non-entry kind.

- [ ] **Step 1: Write the failing tests** in `tests/items.rs`:
  - **`verb_word_and_example_hashes_match_pythons`:** the same `VERB`, `EXAMPLE` and `WORD` objects as Task 1. `entry_hash(DataFile::Verbs, &verb)`, `item_hash(&example)` and `entry_hash(DataFile::Words, &word)` equal Task 1's three constants.
  - **`an_example_hash_ignores_its_review`:**
    - `item_hash(&example)` is the same with and without a `review` key.
    - `entry_hash(DataFile::Verbs, &verb)` is the same before and after an example gains a review.
  - **Update `a_verb_or_word_hash_covers_only_its_authored_fields`:** changing a verb's collocation now changes its entry hash. Changing an example or a form doesn't.
  - In `tests/data.rs`, **`stamps_parse_on_verbs_examples_and_words`:** a verbs file and a words file with stamps parse, and an unknown key inside a stamp fails.

- [ ] **Step 2: Run them to verify they fail**

Run: `cd review/api && cargo test --test items --test data`
Expected: FAIL, because `item_hash` is not found and serde rejects the unknown field `review`.

- [ ] **Step 3: Implement** the three `review` fields, `item_hash` and the Verbs exclusion change. Update the doc comment on `excluded_from_entry_hash`: verbs now match `update_data.VERB_GENERATED`.

- [ ] **Step 4: Run them to verify they pass**

Run: `cd review/api && cargo test && cargo clippy --all-targets -- -D warnings`
Expected: all pass, with no warnings.

- [ ] **Step 5: Commit** with the message `"review api: verb, word and example stamps parse; verb hash covers collocations"`.

### Task 5: Worker: what can be stamped, and when

**Files:**
- Modify: `review/api/src/stamp_routes.rs`:
  - `stampable`;
  - `NOT_STAMPABLE` becomes `"this can't take a stamp"`;
  - `EntryBody` gains an optional `kind`;
  - `ready` takes a `&Target`.
- Modify: `review/api/src/review_store.rs`:
  - a `covered!()` macro;
  - `SELECT_STAMP_READINESS` and `senior_approval!` use it;
  - `SELECT_READY_TO_STAMP`;
  - `ReadyEntry` gains fields;
  - `stamp_readiness(&self, t: &Target)`.
- Modify: `review/api/src/d1.rs` and `review/api/tests/support/sqlite.rs` (the new binds), `review/api/src/review_routes.rs` (call `ready` with the entry's `Target`)
- Test: `review/api/tests/stamp_api.rs`

**Interfaces:**
- Consumes: `Target { dataset, kind, item_id }`, as it exists.
- Produces:
  - `pub fn stampable(file: DataFile, kind: Kind) -> bool`. True for `(Counters | Grammar | Verbs | Words, Entry)` and `(Verbs, Example)`.
  - `ReadyEntry { dataset, kind, item_id, entry_id, entry_title, title }`, all `String`.
  - The `POST /api/admin/stamp` and `/withdraw` bodies take `{dataset, id, kind?}`, where `kind` defaults to `"entry"`.
  - `covered!()` is the SQL condition on an `items i` row, with `?1` dataset, `?2` kind and `?3` item id:

```sql
i.dataset = ?1 AND ((?2 = 'entry' AND i.entry_id = ?3 AND NOT (i.dataset = 'verbs' AND i.kind = 'example'))
                 OR (?2 <> 'entry' AND i.kind = ?2 AND i.item_id = ?3))
```

  Open suggestions use the same shape on `suggestions`, with columns `dataset`, `kind`, `item_id` and `entry_id`. `SELECT_READY_TO_STAMP` is the existing entry query, widened to all four datasets with the verbs/example exclusion inline. It is joined by `UNION ALL` to the verb examples that are approved, have no open suggestion, have no pending stamp and have no `$.review`. Both sides return `entry_title` from the entry row, and are ordered by dataset, entry position, then position.

- [ ] **Step 1: Write the failing tests** in `tests/stamp_api.rs`, using the file's existing setup helpers:
  - **`verb_readiness_skips_examples_and_examples_stand_alone`:**
    - Load a verb with two examples and one collocation, then approve the entry and the collocation only.
    - `POST /api/admin/stamp {dataset: "verbs", id}` returns 201.
    - An open suggestion on example 1 doesn't change that.
    - An open suggestion on the collocation turns a fresh attempt into 409 `"settle its open suggestions first"`.
    - Approve example 2, and `{…, kind: "example", id: <ex2>}` returns 201, naming that example's approver.
    - Example 1, unapproved, returns 409 `"every part needs an approval first"`.
  - **`words_take_a_stamp`:** approve a word, and the stamp returns 201.
  - **`ready_list_includes_verbs_words_and_verb_examples`:** `GET /api/admin/stampable` lists the verb, the approved example (with the verb as `entry_title`) and the word. Not the unapproved example.
  - **`grammar_examples_cannot_be_stamped_alone`:** `{dataset: "grammar", kind: "example", …}` returns 400 `"this can't take a stamp"`.
  - **Update** the existing `NOT_STAMPABLE` test for verbs, which must now succeed.

- [ ] **Step 2: Run them to verify they fail**

Run: `cd review/api && cargo test --test stamp_api`
Expected: FAIL. Verbs return 400 `"only counters and grammar points take a stamp for now"`.

- [ ] **Step 3: Implement** the changes listed under Files. `review_routes::review` keeps passing the entry `Target`.

- [ ] **Step 4: Run them to verify they pass**

Run: `cd review/api && cargo test && cargo clippy --all-targets -- -D warnings`
Expected: all pass.

- [ ] **Step 5: Commit** with the message `"review api: stamps for verbs, words and verb examples"`.

### Task 6: Export page: stamp examples grouped by verb

**Files:**
- Modify: `review/web/src/lib/api.ts` (`ReadyEntry`; `stampEntry(dataset, id, kind = 'entry')` and `withdrawStamp` with the same signature)
- Modify: `review/web/src/lib/export.ts` (add `groupReady`), `review/web/src/lib/export.test.ts`
- Modify: `review/web/src/routes/admin/export/+page.svelte`, the mock data files that serve `/api/admin/stampable`
- Modify: `review/README.md` (what can be stamped)

**Interfaces:**
- Consumes: Task 5's `ReadyEntry` and the stamp body's `kind`.
- Produces: `groupReady(entries: ReadyEntry[]): { key: string; title: string; entry: ReadyEntry | null; examples: ReadyEntry[] }[]`.
  - Groups keep the server's order.
  - An entry and its ready examples share one group, keyed `${dataset}/${entry_id}`.
  - A group of examples whose verb isn't ready has `entry: null`, and its title is `entry_title`.

- [ ] **Step 1: Write the failing tests** in `export.test.ts`:
  - `groups a verb with its ready examples`;
  - `examples without a ready verb form their own group titled by the verb`;
  - `counters and grammar stay one group each`.

- [ ] **Step 2: Run them to verify they fail**

Run: `cd review/web && npx vitest run src/lib/export.test.ts`
Expected: FAIL, because `groupReady` is not exported.

- [ ] **Step 3: Implement**
  - Add `groupReady`.
  - The page renders one row per group:
    - the entry's "Stamp as reviewed" when `entry` is set;
    - each example as a sub-row with its own button;
    - when a group has two or more examples, "Stamp all N examples", which stamps them one after another and stops at the first error.
  - The intro becomes: "Entries and verb example sentences whose every part is approved, with nothing open. A stamp names the most senior reviewer involved."
  - The stamps list's Withdraw passes `t.kind`.
  - The mocks gain one verb, one example and one word.

- [ ] **Step 4: Run them to verify they pass**

Run: `cd review/web && npm run check && npx vitest run && npm run build`
Expected: 0 errors, all tests pass, and the build succeeds. Then preview with the `review-web` launch entry. On the admin Export page, check that a verb shows with its examples under it, and that "Stamp all" stamps each one (mock).

- [ ] **Step 5: Commit** with the message `"review web: stamp verbs, words and verb examples on the export page"`.

### Task 7: VerbKit decodes the new stamps

**Files:**
- Modify:
  - `Packages/VerbKit/Sources/VerbKit/Models/Verb.swift` (`review: ReviewStamp?`, decode)
  - `VerbExample.swift` (`review`, decode/encode)
  - `Word.swift` (`Word.review`, the `Word(_ verb:)` bridge carries it, `Codable` encode/decode)
  - `WordsDataFile.swift` (`StoredWord.review`)
  - `ReviewStamp.swift` (`extension Verb: Reviewable {}`, `VerbExample`, `Word`, and the doc comment)
- Test: `Packages/VerbKit/Tests/VerbKitTests/ReviewStampTests.swift`

**Interfaces:**
- Produces: `Verb.review`, `VerbExample.review`, `Word.review`, all `ReviewStamp?` and defaulting to nil in the initialisers. All three conform to `Reviewable`, so `isReviewed` and `ReviewSummary(_:)` work on them.

- [ ] **Step 1: Write the failing tests:**
  - `testVerbsExamplesAndWordsDecodeWithoutAStamp`, against the real bundled data, as the counters test does;
  - `testAVerbAnExampleAndAWordDecodeAStamp`, from inline JSON;
  - `testExampleStampSurvivesAnEncodeRoundTrip`;
  - `testStoredWordKeepsItsStamp`;
  - `testSummaryOfVerbExamples`, where `ReviewSummary(verbs.flatMap(\.examples))` counts stamped examples.

- [ ] **Step 2: Run them to verify they fail**

Run: `cd Packages/VerbKit && swift test --filter ReviewStampTests`
Expected: compile failure, because `review` is not a member of `Verb`.

- [ ] **Step 3: Implement** the fields, decoding (`decodeIfPresent`), encoding (`encodeIfPresent`) and conformances.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test-swift`
Expected: all pass.

- [ ] **Step 5: Commit** with the message `"VerbKit: review stamps on verbs, examples and words"`.

### Task 8: App: the verb capsule, example checks and counts

Before starting, `git log origin/main -- App/VerbDetailView.swift App/VerbExampleRow.swift App/ReviewStatusPill.swift`. If an unmerged paper-and-ink branch touches these files, rebase onto main after it lands rather than editing alongside it.

**Files:**
- Modify: `App/ReviewStatusPill.swift`:
  - `ReviewStatusPill` gains `note: String? = nil`, shown under the headline whatever the state;
  - `ContentReviewSection` gains rows for Verbs, Example sentences and Words, plus the new footer.
- Modify: `App/VerbDetailView.swift` (the pill in `header`, beside the level badge)
- Modify: `App/VerbExampleRow.swift` (a check after the form tag for a reviewed example)
- Modify: `App/VerbListView.swift` (`ReviewSummaryLine(noun: "verbs", …)` at the end of the list, counting `visible(in: currentLevels)` as `GrammarListView.swift:164` does)
- Modify: `docs/superpowers/specs/2026-10-27-review-status-design.md` ("As built": the new scope), `docs/superpowers/specs/2026-10-27-data-review-site-design.md` (close the scope gap, "Implemented in plan 7")

**Interfaces:**
- Consumes: Task 7's `Verb.review`, `VerbExample.review`, `Word.review`, `ReviewSummary`.

- [ ] **Step 1: Add the verb capsule:**
  - `item`: `"Verb: \(verb.displayTitle)"`, `review: verb.review`
  - `checked`: `["The conjugated forms, generated from the dictionary form", "That every kanji has a reading"]`
  - `unchecked`: `["The meaning, description and notes", "The common phrases"]`
  - `note`: `"Example sentences are reviewed one by one; a reviewed one shows a check."`

- [ ] **Step 2: Add the example check.**
  - Only when `example.review != nil` and Show review status is on, show `Image(systemName: "checkmark.circle.fill")` in `palette.good` at `.caption2`.
  - Accessibility label: `"Reviewed by \(review.by.displayName) on \(review.on)"`.
  - Nothing appears on an unreviewed example.

- [ ] **Step 3: Add the counts.**
  - Settings rows: "Verbs" `ReviewSummary(verbs.verbs)`, "Example sentences" `ReviewSummary(verbs.verbs.flatMap(\.examples))`, and "Words" `ReviewSummary(words.words)` (`@Environment(WordsStore.self)`).
  - Footer: "Readings, sound changes and conjugated forms are checked automatically. Meanings, examples, pitfalls and questions are marked once a person has read them."
  - Add the verb list line.

- [ ] **Step 4: Verify the build and look at the screens**

Run: `make check-project` and an iOS simulator build (the `build` tool or `xcodebuild` per `make` help).
Expected: the build succeeds.

Then check the screens in the simulator:
- **Unstamped data:** a verb page shows "Not yet reviewed" and its sheet shows the note. No example shows a check. The verb list ends with "No verbs reviewed yet". Settings › Content review shows the three new rows at 0.
- **Stamped data:** temporarily point the debug build at a local copy with one stamped verb and example, if the project has a hook for local data; otherwise use a SwiftUI preview with stamped `Verb` fixtures. "Reviewed" and the check should appear.
- Take screenshots for the PR. Do not commit stamped data.

- [ ] **Step 5: Commit** with the message `"App: review status on verbs and example sentences"`.

---

**Final check (after Task 8):** run `make check`, `make test-py`, `make review-test` and `make test-swift`. `git diff origin/main --stat -- data/` must be empty.
