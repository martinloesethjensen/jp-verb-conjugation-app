# Review site, plan 1: stable ids for examples, usages, pitfalls and things

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every reviewable sub-item in `data/` (example sentences, grammar usages, pitfalls, counter things) a short stable `id`, enforced by `update_data.py`, so review-site suggestions keep pointing at the right item when lists change.

**Architecture:** A new `scripts/stable_ids.py` defines which objects need an id, the id format and the check. `update_data.py` runs the check and keeps `verbs.json` examples on one line with the new key. A one-off `scripts/assign_ids.py` fills in missing ids: through the existing dumpers for `verbs.json` and `counters.json`, and by in-place text insertion for the hand-formatted `grammar.json`. The app ignores the new key (Swift `Codable` skips unknown keys).

**Tech Stack:** Python 3 standard library (`unittest`, `json`, `re`, `secrets`), the existing `make data`, `make test-py`, `swift test`.

**Spec:** `docs/superpowers/specs/2026-10-27-data-review-site-design.md` ("Stable ids first").

## Roadmap (one plan per piece; later plans are written when the previous one lands)

1. **This plan:** stable ids. Data PR, owner signs.
2. Site foundation: a JSON Schema per data file as the one definition of the shapes (checked by `update_data.py`; the Rust `serde` types are tested against it, and later Kotlin), including the stable-id slots and their pattern; `review/` layout, Access, Rust Worker with JWT verification and roles, D1 schema, Svelte shell, CI, snapshot import with signature check, browse and item pages.
3. Review path: queues, approve, suggest change and delete, counter-suggestions, the admin inbox.
4. Add path: per-type add forms, furigana prompts, locked id fields.
5. Export: `make review-pull`, applying accepted work, stamps with `name`, PR summary.
6. Stamps for verbs, words and examples: pipeline, `mark_reviewed.py`, VerbKit, app capsule and example check.

## Global Constraints

- Every `data/` change is re-signed by the owner (`make sign-commit PUSH=1`). Agents never run `scripts/sign_manifest.py sign` or `make sign-commit`.
- Id format: 6 characters from `abcdefghijkmnpqrstuvwxyz23456789` (no `l`, `o`, `0`, `1`), regex `^[a-km-np-z2-9]{6}$` (corrected during execution: the first draft left out `i`, which the alphabet includes; shipped ids contain `i`). Generated with `secrets`. Unique within its file.
- The key is `"id"` and comes first in the object.
- `grammar.json` is hand-formatted: apart from the inserted ids it must stay byte for byte as it was (same approach as `stamp_grammar_text` in `scripts/mark_reviewed.py`).
- `verbs.json` examples stay on one line: `{ "id": "…", "form": "…", "jp": "…", "en": "…" }`.
- `counters.json` keeps its one-counter-per-line layout (`dump_counters`).
- No `review` stamps exist yet (`grep -c '"review"' data/*.json` is 0 everywhere), so ids changing entry hashes invalidates nothing. The check must still run before stamps are checked.
- Words have no sub-items and get no ids. Verbs, words, counters and grammar points keep their existing ids.

## Review Focus

- A sub-item added later by hand without an id: `update_data.py` (and `--check`) fails naming the file and the item, and says to run `scripts/assign_ids.py`. Test in Task 2.
- Two items sharing an id (copy-paste): the check fails naming both. Test in Task 1.
- Running `assign_ids.py` twice changes nothing the second time. Test in Task 3.
- A `grammar.json` object whose layout the inserter doesn't recognise: the script stops with an error instead of writing a file with some items missing ids. Test in Task 3.
- An existing malformed id (`"id": "ABC"`): the check reports it rather than silently replacing it. Test in Task 1.

---

### Task 1: The id rules (`scripts/stable_ids.py`)

**Files:**
- Create: `scripts/stable_ids.py`
- Test: `scripts/test_stable_ids.py`

**Interfaces:**
- Produces:
  - `ALPHABET: str = "abcdefghijkmnpqrstuvwxyz23456789"`
  - `ID_PATTERN: re.Pattern` matching `^[a-km-np-z2-9]{6}$`
  - `new_id(taken: set[str]) -> str`: a fresh id not in `taken`; adds it to `taken`.
  - `id_slots(dataset: str, doc: dict) -> list[tuple[str, dict]]`: `(label, obj)` for every object that must carry an id. `dataset` is `"verbs"`, `"counters"` or `"grammar"`; any other raises `ValueError`. Slots, in document order:
    - verbs: `verbs[*].examples[*]`, label `"<verb id> example <n>"` (verb id is `id` if present else `dict`; n is 1-based)
    - counters: `counters[*].things[*]`, `.examples[*]`, `.pitfalls[*]`, `.pitfalls[*].examples[*]`, labels like `"hon thing 2"`, `"hon example 1"`, `"hon pitfall 1"`, `"hon pitfall 1 example 2"`
    - grammar: `grammar[*].usages[*]`, `.usages[*].examples[*]`, `.pitfalls[*]`, `.pitfalls[*].examples[*]`, `.contrasts[*].examples[*]` (added after review; a contrast's own `id` names another grammar point, so the contrast itself is not a slot), labels like `"n-desu usage 1"`, `"n-desu usage 1 example 2"`, `"n-desu pitfall 1"`, `"node contrast 1 example 2"`
  - `check_stable_ids(dataset: str, doc: dict) -> list[str]`: problems, one string each.

- [ ] **Step 1: Write the failing tests**

```python
class StableIdTests(unittest.TestCase):
    def test_new_ids_match_the_pattern_and_are_unique(self):
        taken = set()
        ids = [stable_ids.new_id(taken) for _ in range(500)]
        self.assertEqual(len(set(ids)), 500)
        self.assertTrue(all(stable_ids.ID_PATTERN.match(i) for i in ids))
        self.assertEqual(taken, set(ids))

    def test_verb_slots_are_the_examples(self):
        doc = {"verbs": [{"dict": "たべる", "examples": [{"jp": "a"}, {"jp": "b"}]}]}
        self.assertEqual([label for label, _ in stable_ids.id_slots("verbs", doc)],
                         ["たべる example 1", "たべる example 2"])

    def test_grammar_slots_cover_usages_pitfalls_and_their_examples(self):
        doc = {"grammar": [{"id": "n-desu",
                            "usages": [{"heading": "h", "examples": [{"jp": "a"}]}],
                            "pitfalls": [{"heading": "p", "examples": [{"jp": "b"}, {"jp": "c"}]}]}]}
        self.assertEqual([label for label, _ in stable_ids.id_slots("grammar", doc)],
                         ["n-desu usage 1", "n-desu usage 1 example 1", "n-desu pitfall 1",
                          "n-desu pitfall 1 example 1", "n-desu pitfall 1 example 2"])

    def test_counter_slots_cover_things_examples_and_pitfalls(self):
        doc = {"counters": [{"id": "hon", "things": [{"word": "ペン"}], "examples": [{"jp": "a"}],
                             "pitfalls": [{"heading": "p", "examples": [{"jp": "b"}]}]}]}
        self.assertEqual([label for label, _ in stable_ids.id_slots("counters", doc)],
                         ["hon thing 1", "hon example 1", "hon pitfall 1", "hon pitfall 1 example 1"])

    def test_missing_duplicate_and_malformed_ids_are_reported(self):
        doc = {"verbs": [{"dict": "たべる", "examples": [
            {"id": "abcdef", "jp": "a"}, {"id": "abcdef", "jp": "b"}, {"jp": "c"}, {"id": "ABC", "jp": "d"}]}]}
        problems = stable_ids.check_stable_ids("verbs", doc)
        self.assertIn("たべる example 2: id 'abcdef' is also used by たべる example 1", problems)
        self.assertIn("たべる example 3 has no id: run scripts/assign_ids.py", problems)
        self.assertIn("たべる example 4: id 'ABC' is not 6 characters from the id alphabet", problems)
        self.assertEqual(len(problems), 3)

    def test_unknown_dataset_raises(self):
        with self.assertRaises(ValueError):
            stable_ids.id_slots("words", {})
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `cd scripts && python3 -m unittest test_stable_ids -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'stable_ids'`

- [ ] **Step 3: Implement `scripts/stable_ids.py`** with the interfaces above. Missing lists (`things`, `pitfalls`, `usages`, `examples`) count as empty.

- [ ] **Step 4: Run the tests to see them pass**

Run: `cd scripts && python3 -m unittest test_stable_ids -v`
Expected: 6 tests, OK

- [ ] **Step 5: Make `make test-py` pick the new test file up** if it lists test modules explicitly (check the `test-py` target in `Makefile`), then run `make test-py`. Expected: all OK.

- [ ] **Step 6: Commit**

```bash
git add scripts/stable_ids.py scripts/test_stable_ids.py Makefile
git commit -m "scripts: stable id rules for reviewable data items"
```

### Task 2: Enforce ids in `update_data.py`

**Files:**
- Modify: `scripts/update_data.py` (`dump_verbs` at ~line 1371; `run` at ~line 1775: the grammar checks before line 1800, the verb checks after `check_verb_ids` ~line 1813, the counter checks ~line 1851)
- Test: `scripts/test_update_data.py` (`DumpTests` ~line 457, `RunTests` ~line 718)

**Interfaces:**
- Consumes: `stable_ids.check_stable_ids(dataset, doc) -> list[str]` (Task 1).
- Produces: `run()` returns exit code 1 with the heading `"<file> has items without a valid stable id:"` followed by the problems (use the existing `capped` helper) when any check fails. `dump_verbs` keeps examples with an `id` on one line.

- [ ] **Step 1: Write the failing tests**

```python
# in DumpTests
def test_an_example_with_an_id_stays_on_one_line(self):
    doc = {"verbs": [{"examples": [{"id": "abcdef", "form": "te", "jp": "たべて。", "en": "Eat."}]}]}
    self.assertIn('{ "id": "abcdef", "form": "te", "jp": "たべて。", "en": "Eat." }', ud.dump_verbs(doc))

# in RunTests, following the existing pattern for building a temp data dir
def test_an_example_without_an_id_fails_the_run(self):
    # Build the fixture data dir the way neighbouring RunTests do, then drop the id of one verb example.
    code, messages = ud.run(data_dir, check=True)
    self.assertEqual(code, 1)
    self.assertIn("verbs.json has items without a valid stable id:", messages[0])
    self.assertTrue(any("run scripts/assign_ids.py" in m for m in messages))
```

Add the same failing-run test for one grammar usage and one counter thing.

- [ ] **Step 2: Run them to see them fail**

Run: `cd scripts && python3 -m unittest test_update_data.DumpTests test_update_data.RunTests -v`
Expected: the new tests FAIL (dump splits the example over several lines; run returns 0). Existing `RunTests` fixtures without ids will also start failing once Step 3 lands; give their fixture examples, usages, pitfalls and things ids in this step so only the new tests fail now.

- [ ] **Step 3: Implement.** In `dump_verbs`, accept an optional leading `"id": …,` in the one-line regex. In `run`, call `check_stable_ids` for grammar (with the other grammar checks), verbs (right after `check_verb_ids`) and counters (before `check_reviews`), each returning the heading above.

- [ ] **Step 4: Run all Python tests**

Run: `make test-py`
Expected: all OK.

- [ ] **Step 5: Commit**

```bash
git add scripts/update_data.py scripts/test_update_data.py
git commit -m "update_data: require stable ids on examples, usages, pitfalls and things"
```

(`make data-check` fails on the real data until Task 4; that is expected at this commit.)

### Task 3: Fill in missing ids (`scripts/assign_ids.py`)

**Files:**
- Create: `scripts/assign_ids.py`
- Test: `scripts/test_assign_ids.py`

**Interfaces:**
- Consumes: `stable_ids.new_id`, `stable_ids.id_slots`, `stable_ids.check_stable_ids` (Task 1); `update_data.dump_verbs`, `update_data.dump_counters`.
- Produces:
  - `assign_json(dataset: str, doc: dict) -> int`: gives every slot without an id a new one, placed first in the object; returns how many were added. Existing ids are kept and reserved.
  - `assign_grammar_text(text: str) -> tuple[str, int]`: returns the new `grammar.json` text and the count added.
  - `main(argv=None) -> int`: `python3 scripts/assign_ids.py [--data-dir DIR]` rewrites `verbs.json` (via `dump_verbs`), `counters.json` (via `dump_counters`) and `grammar.json` (via `assign_grammar_text`), prints the count per file, and tells the owner to run `make data` and `make sign-commit`.

`assign_grammar_text` algorithm (the tests pin it; this is the part the signature doesn't determine):
1. Collect the ids already present (`id_slots("grammar", json.loads(text))`) into `taken`.
2. A one-line example `^(?P<indent>\s*)\{ "jp": ` gets `"id": "<new>", ` inserted after `{ `.
3. A multi-line usage or pitfall is a line `^\s*\{$` followed by a line `^(?P<indent>\s*)"heading": `; insert the line `<indent>"id": "<new>",` before the heading line.
4. Lines already starting `{ "id"` or a `{` line followed by an `"id"` line are left alone.
5. Parse the result and run `check_stable_ids("grammar", …)`. If it reports anything (an object in a layout the regexes missed), raise `ValueError` with those problems and write nothing.

- [ ] **Step 1: Write the failing tests**

```python
GRAMMAR = '''{
  "grammar": [
    {
      "id": "n-desu",
      "usages": [
        {
          "heading": "h",
          "examples": [
            { "jp": "あ。", "en": "a" }
          ]
        }
      ],
      "pitfalls": []
    }
  ]
}
'''

class AssignIdsTests(unittest.TestCase):
    def test_grammar_gets_ids_and_is_otherwise_unchanged(self):
        text, added = assign_ids.assign_grammar_text(GRAMMAR)
        self.assertEqual(added, 2)
        self.assertEqual(stable_ids.check_stable_ids("grammar", json.loads(text)), [])
        stripped = re.sub(r'"id": "[a-hj-km-np-z2-9]{6}",\s?\n?\s*', "", text)
        self.assertEqual(re.sub(r"\s+", "", stripped), re.sub(r"\s+", "", GRAMMAR))
        self.assertRegex(text, r'\n        \{\n          "id": "[a-hj-km-np-z2-9]{6}",\n          "heading": "h",')
        self.assertRegex(text, r'\{ "id": "[a-hj-km-np-z2-9]{6}", "jp": "あ。", "en": "a" \}')

    def test_running_twice_changes_nothing(self):
        once, _ = assign_ids.assign_grammar_text(GRAMMAR)
        twice, added = assign_ids.assign_grammar_text(once)
        self.assertEqual((twice, added), (once, 0))

    def test_an_unrecognised_layout_raises_instead_of_writing(self):
        odd = GRAMMAR.replace('{ "jp": "あ。", "en": "a" }', '{ "en": "a", "jp": "あ。" }')
        with self.assertRaises(ValueError):
            assign_ids.assign_grammar_text(odd)

    def test_json_assignment_keeps_existing_ids_and_puts_new_ones_first(self):
        doc = {"verbs": [{"dict": "たべる", "examples": [{"id": "abcdef", "jp": "a"}, {"form": "te", "jp": "b"}]}]}
        self.assertEqual(assign_ids.assign_json("verbs", doc), 1)
        examples = doc["verbs"][0]["examples"]
        self.assertEqual(examples[0]["id"], "abcdef")
        self.assertEqual(list(examples[1])[0], "id")
        self.assertNotEqual(examples[1]["id"], "abcdef")
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd scripts && python3 -m unittest test_assign_ids -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'assign_ids'`

- [ ] **Step 3: Implement `scripts/assign_ids.py`** as specified, with a module docstring in the style of `mark_reviewed.py` (usage line, then what to run afterwards).

- [ ] **Step 4: Run the tests to see them pass**

Run: `cd scripts && python3 -m unittest test_assign_ids -v`, then `make test-py`
Expected: 4 tests OK; all Python tests OK.

- [ ] **Step 5: Commit**

```bash
git add scripts/assign_ids.py scripts/test_assign_ids.py
git commit -m "scripts: assign_ids.py fills in missing stable ids"
```

### Task 4: Give the shipped data its ids

**Files:**
- Modify: `data/verbs.json`, `data/grammar.json`, `data/counters.json`, `data/manifest.json` and the bundled copies under `Packages/VerbKit/Sources/VerbKit/Resources/` (all regenerated, not hand-edited)

- [ ] **Step 1: Assign the ids**

Run: `python3 scripts/assign_ids.py`
Expected: a count per file (verbs: one per example, 442+ at the time of writing; grammar and counters: their usages, pitfalls, things and examples) and the reminder to run `make data` and sign.

- [ ] **Step 2: Check the diff is only ids**

Run: `git diff --stat data/` and `git diff data/grammar.json | grep '^[-+] ' | grep -v '"id": "' | head`
Expected: the second command prints nothing for `grammar.json` except lines whose only change is an inserted id (one-line examples show as a changed line containing `"id"`).

- [ ] **Step 3: Regenerate and check**

Run: `python3 scripts/update_data.py && python3 scripts/update_data.py --check`
Expected: the first bumps the versions of verbs, grammar and counters and says the manifest must be re-signed; the second prints `data is up to date`.

- [ ] **Step 4: Run every test suite**

Run: `make test-py` and `cd Packages/VerbKit && swift test`
Expected: all Python tests OK; all Swift tests pass with 0 failures (the app ignores the new key).

- [ ] **Step 5: Commit and open a draft PR (do not sign)**

```bash
git add data Packages/VerbKit/Sources/VerbKit/Resources
git commit -m "data: give examples, usages, pitfalls and things stable ids"
git push -u origin HEAD
gh pr create --draft --title "data: stable ids for reviewable items (review site, plan 1)" --body "…"
```

The PR body lists the counts per file, says the manifest needs the owner's signature (`make sign-commit PUSH=1`), links the spec, and ends with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
