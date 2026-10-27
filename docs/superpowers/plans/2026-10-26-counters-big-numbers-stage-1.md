# Numbers above 10, stage 1 (pipeline and data) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate and validate readings for 11 to 99, 100 and 円's round numbers in `data/counters.json`, plus a 月 counter, without changing anything the current app shows.

**Architecture:** `update_data.py` composes extended readings from each counter's own 1 to 10 readings (regular counters) or from its 1 to 10 readings plus a small optional `compound` field (irregular counters), then applies the existing `changed`, `distractors` and counted-run validation to the longer key list. Extended numbers are extra keys after `"what"`, so old keys, old builds and the current screens are untouched.

**Tech Stack:** Python (unittest), existing Swift real-data tests.

**Spec:** `docs/superpowers/specs/2026-10-26-counters-big-numbers-design.md` (rules in its appendix). This plan refines it in three places, ruled here and recorded in Task 8: `compound` (below); `distractors` are generated for an extended key only when it changed or is authored (every key still has the list, empty otherwise), which keeps the file near the 150 KB budget; composition uses only the preferred tens prefix (にじゅう, ななじゅう), never alternates.

## Global Constraints

- The app derives no readings; stage 1 changes no Swift source, only Swift tests.
- Keys stay in this order: `"1"` to `"10"`, `"what"`, then `"11"` upward, then `extra`.
- Every `data/` change is re-signed by the owner on the feature branch; furigana for each new counted run in examples and questions is authored with the content.
- The composition rules are the appendix's and are unreviewed until the teacher checks them: the data merges only after that check.
- `counters.json` stays under 200,000 bytes.

## Data model added to a counter (all optional)

- `extent`: whole number 10 to 99, default 99. The largest composed number.
- `extra`: ascending list of numbers above `extent`. `100` is composed; any other (200 to 900, 1000 to 9000, 10000) must be authored in `overrides`.
- `compound`: an object with keys `"1"` to `"9"` and `"0"`. `"1"` to `"9"` replace that digit's reading when it is the last digit of a compound (人: `"1": ["いちにん"]`). `"0"` is the reading after a round ten (人: `["にん"]`, 日: `["にち"]`). Needed by irregular counters.
- `overrides` may now hold any key the counter has; an override always beats composition.

## Review Focus

- `二十本` in an example was skipped by the counted-run check; it must now be read and checked. Task 5.
- An irregular counter with `extent` above 10 and neither `compound` nor full overrides gets a clear error, not a crash or silent gaps. Task 4.
- An `extra` number other than 100 with no override is rejected. Task 4.
- The old keys keep their order and values (1 to 10, 何), so the current screens and old builds are unchanged. Task 3.
- 二十歳 はたち and 二十日 はつか beat composition, while 二十四日 composes (にじゅうよっか). Task 6.
- The file stays under the size budget. Task 7.

---

### Task 1: Number words and the key list

**Files:**
- Modify: `scripts/update_data.py` (counter section, near `COUNTER_KEYS`)
- Test: `scripts/test_update_data.py`

**Interfaces:**
- Produces: `plain_number(n: int) -> str` and `counter_keys(counter: dict) -> list[str]`.

- [ ] **Step 1: Write failing tests** in a new `CounterKeyTests`: `test_plain_number` asserts 11 `じゅういち`, 14 `じゅうよん`, 20 `にじゅう`, 70 `ななじゅう`, 99 `きゅうじゅうきゅう`, 100 `ひゃく`, 300 `さんびゃく`, 600 `ろっぴゃく`, 800 `はっぴゃく`, 1000 `せん`, 3000 `さんぜん`, 8000 `はっせん`, 10000 `いちまん`, and that 5 gives `ご`. `test_counter_keys_default_to_99` asserts the first twelve keys are `COUNTER_KEYS`, then `"11"` to `"99"` (101 keys). `test_extent_and_extra`: `{"extent": 24}` stops at `"24"`; `{"extent": 10}` gives exactly `COUNTER_KEYS`; `{"extent": 59, "extra": [100]}` ends with `"59", "100"`.
- [ ] **Step 2: Run** `python3 -m unittest discover -s scripts` (from `scripts/`: `python3 -m unittest test_update_data`); expect the new tests to fail.
- [ ] **Step 3: Implement** `plain_number` for 1 to 99 (the prefixes in the spec appendix with じゅう), the hundreds (ひゃく, にひゃく, さんびゃく, よんひゃく, ごひゃく, ろっぴゃく, ななひゃく, はっぴゃく, きゅうひゃく), thousands (せん, にせん, さんぜん, よんせん, ごせん, ろくせん, ななせん, はっせん, きゅうせん) and 10000 `いちまん`; `counter_keys` reads `extent` (default 99) and `extra`.
- [ ] **Step 4: Run** the tests; expect PASS.
- [ ] **Step 5: Commit** `"Counters: number words and the key list for bigger numbers"`.

### Task 2: Composition

**Files:**
- Modify: `scripts/update_data.py`
- Test: `scripts/test_update_data.py`

**Interfaces:**
- Consumes: `plain_number`, the existing `_voiced`, `GEMINATING_KEYS`.
- Produces: `compose_readings(counter: dict, n: int, core: dict[str, list[str]]) -> list[str] | None`. `core` is the counter's readings for `"1"` to `"10"` after overrides. Returns the readings for `n` (preferred first), or `None` when the counter cannot compose `n` (an irregular counter without what it needs).

- [ ] **Step 1: Write failing tests** in `ComposeTests`. For each class, build the counter from the existing test helper and assert the **hand-written** expected readings (preferred first):
  - 本 (`h-b`, ほん): 11 `[じゅういっぽん]`, 14 `[じゅうよんほん]`, 18 `[じゅうはっぽん, じゅうはちほん]`, 20 `[にじゅっぽん, にじっぽん]`, 30 `[さんじゅっぽん, さんじっぽん]`, 40 `[よんじゅっぽん, よんじっぽん]`, 100 `[ひゃっぽん]`
  - 分 (`h-p`, ふん): 11 `じゅういっぷん`, 14 `じゅうよんぷん`, 20 `にじゅっぷん, にじっぷん`, 100 `ひゃっぷん`
  - 個 (`k`, こ): 11 `じゅういっこ`, 18 `じゅうはっこ, じゅうはちこ`, 20 `にじゅっこ, にじっこ`, 100 `ひゃっこ`
  - 冊 (`s`, さつ): 11 `じゅういっさつ`, 18 `じゅうはっさつ`, 20 `にじゅっさつ, にじっさつ`, 100 `ひゃくさつ`
  - 枚 (`plain`, まい): 11 `じゅういちまい`, 14 `じゅうよんまい`, 20 `にじゅうまい`, 70 `ななじゅうまい`, 100 `ひゃくまい`
  - an override beats composition (枚 with `overrides {"14": ["x"]}` gives `[x]` through `counter_readings` in Task 3, not here).
  - irregular with `compound`: a 人-like counter (`compound {"1": [いちにん], "2": [ににん], "0": [にん]}`, core 3 `さんにん`): 11 `じゅういちにん`, 13 `じゅうさんにん`, 20 `にじゅうにん`, 100 `ひゃくにん`; without `compound`, `compose_readings(..., 11, core)` is `None`.
- [ ] **Step 2: Run** the tests; expect failures.
- [ ] **Step 3: Implement** `compose_readings` by the appendix table: 11 to 99 with a last digit uses the last digit's readings (`compound[d]` if present, else `core[d]`) after `prefix + じゅう`; a round ten takes `core["10"]` with its leading じゅう, じゅっ or じっ kept and the prefix in front for regular counters, or `prefix + じゅう + compound["0"]` for irregular ones; 100 is `ひゃっ` + the voiced or plain reading rest for `k`, `h-b`, `h-p` and `ひゃく` + the counter's reading for `s`, `plain` and for irregular counters with `compound["0"]`. Drop duplicates, keep order.
- [ ] **Step 4: Run** the tests; expect PASS.
- [ ] **Step 5: Commit** `"Counters: compose readings above ten"`.

### Task 3: Wire into the generator

**Files:**
- Modify: `scripts/update_data.py` (`counter_readings`, `changed_keys`, `counter_distractors`, `apply_counter_readings`, `check_counter_distractors`)
- Test: `scripts/test_update_data.py`

**Interfaces:**
- Consumes: `counter_keys`, `compose_readings`, `plain_number`.
- Produces: `counter_readings(counter)` returns every key of `counter_keys(counter)`; `changed_keys` marks a number whose preferred reading is not `plain_number(n)` + the counter's reading; `counter_distractors` returns every key, with a non-empty list for an extended key only when it changed or has an override.

- [ ] **Step 1: Write failing tests:** `test_extended_readings_are_generated` (本: `"20"` is `[にじゅっぽん, にじっぽん]`; `"15"` is `[じゅうごほん]`; key order is 1 to 10, `what`, 11 to 99); `test_an_override_beats_composition`; `test_changed_includes_extended_numbers` (本: `"11"`, `"20"` in `changed`, `"15"` not; 枚: none of the extended keys); `test_old_keys_are_unchanged` (generated 1 to 10 and 何 of 本, 分, 枚 equal the values from before this change); `test_distractors_cover_changed_extended_keys_only` (本 `"20"` has the unchanged `にじゅうほん` as a distractor and no accepted reading; `"15"` is `[]`; every key is present); `test_stale_detection_sees_new_keys` (`apply_counter_readings` returns True for a doc whose counter lacks the extended keys, then False).
- [ ] **Step 2: Run** the tests; expect failures.
- [ ] **Step 3: Implement** the changes, generalising the existing distractor algorithm to take the plain reading of the number (`plain_number(n)` for extended keys, `BASE_NUMBERS` for core) and replacing `COUNTER_KEYS` with `counter_keys(c)` where `apply_counter_readings` and `check_counter_distractors` compare key lists.
- [ ] **Step 4: Run** the unit tests (`cd scripts && python3 -m unittest test_update_data`); expect PASS. Do not run `make data` or `make data-check` yet: with the default `extent` of 99 the real irregular counters fail validation until Task 6 gives them `compound` and `extent`. That failure is expected, not a regression.
- [ ] **Step 5: Commit** `"Counters: generate changed and distractors for bigger numbers"`.

### Task 4: Validation

**Files:**
- Modify: `scripts/update_data.py` (`check_counters`)
- Test: `scripts/test_update_data.py`

**Interfaces:**
- Consumes: `counter_keys`.

- [ ] **Step 1: Write failing tests** in `CheckCountersTests.test_big_number_problems` with needles: `"extent must be"` (9, 100, a string), `"extra must be"` (not ascending, entry at or below `extent`, an entry that is not 100, a multiple of 100 up to 900, a multiple of 1000 up to 9000 or 10000), `"must override"` (an `extra` number other than 100 without an override), `"compound"` (a key that is not `"0"` to `"9"`, an empty or non-hiragana list), `"irregular"` (an irregular counter with `extent` above 10 and neither `compound["0"]` nor an override for every key it lacks), and `"overrides key"` (a key outside `counter_keys`). Add `test_a_valid_big_counter_passes` and `test_tsu_style_counter_with_extent_10_passes`.
- [ ] **Step 2: Run** the tests; expect failures.
- [ ] **Step 3: Implement** the checks in `check_counters`, replacing the `COUNTER_KEYS` comparisons (override keys, irregular full-override rule) with `counter_keys(c)`, and the `compound` and `extra` rules above. An irregular counter is complete when every extended key is either overridden or composable (`compound["0"]` present, which also covers 100).
- [ ] **Step 4: Run** the unit tests; expect PASS (the real-data checks stay off until Task 6, as in Task 3).
- [ ] **Step 5: Commit** `"Counters: validate extent, extra and compound"`.

### Task 5: Compound numerals in the counted-run check

**Files:**
- Modify: `scripts/update_data.py` (`NUMBER_KANJI` use, `check_counted_runs`)
- Test: `scripts/test_update_data.py`

**Interfaces:**
- Produces: `parse_numeral(text: str) -> int | None` for 一 to 九十九, 百, 二百 to 九百, 千, 二千 to 九千, 一万 (and 十, 二十 …); `None` for anything else.

- [ ] **Step 1: Write failing tests:** `test_parse_numeral` (十 10, 十五 15, 二十 20, 九十九 99, 百 100, 三百 300, 千 1000, 三千 3000, 一万 10000, `"a"` None, 二十二百 None); `test_a_compound_counted_run_is_checked` (a 分 example `十五分です。` with dictionary reading `じゅうごふん` passes; with `じゅうごぷん` it is reported); `test_nijuppon_is_no_longer_skipped` (the existing `二十本あります。` example now needs `二十本` read as `にじゅっぽん` or `にじっぽん`, and a wrong dictionary reading is reported); `test_a_number_outside_the_counters_keys_is_not_checked` (`百五十本` is ignored, since the counter has no key for 150); the existing single-digit tests keep passing (the `test_a_longer_number_is_not_mistaken_for_its_last_digit` expectation is replaced by the compound one).
- [ ] **Step 2: Run** the tests; expect failures.
- [ ] **Step 3: Implement** a numeral pattern for the compound forms, `parse_numeral`, and use them in `check_counted_runs`: the run's key is `str(n)` (or `"what"` for 何) and is checked when `counter_keys(c)` has it, keeping the `(?!間)` rule and the lookbehind.
- [ ] **Step 4: Run** `make test-py`; expect PASS.
- [ ] **Step 5: Commit** `"Counters: read compound numerals in counted runs"`.

### Task 6: The data

**Files:**
- Modify: `data/counters.json`, `data/furigana.json`, `data/manifest.json` (by `make data`)
- Test: `Packages/VerbKit/Tests/VerbKitTests/RealCountersDataTests.swift`

**Interfaces:**
- Produces: counters carrying `extent`, `extra`, `compound`; a new counter `gatsu` (月, がつ, irregular, `extent` 12) in group `calendar` and section `time-dates-age`.

- [ ] **Step 1: Write failing tests** in `RealCountersDataTests`, with the readings of the spec appendix and the teacher-pending table: `testBigNumbersReadAsTheAppendixSays` asserting preferred readings: 本 20 `にじゅっぽん`, 本 100 `ひゃっぽん`, 分 15 `じゅうごふん`, 分 30 `さんじゅっぷん`, 分 45 `よんじゅうごふん`, 歳 20 `はたち`, 歳 21 `にじゅういっさい`, 歳 100 `ひゃくさい`, 円 100 `ひゃくえん`, 円 300 `さんびゃくえん`, 円 800 `はっぴゃくえん`, 円 1000 `せんえん`, 円 3000 `さんぜんえん`, 円 10000 `いちまんえん`, 時 11 `じゅういちじ`, 時 14 `じゅうよじ`, 時 24 `にじゅうよじ`, 人 11 `じゅういちにん`, 人 14 `じゅうよにん`, 人 20 `にじゅうにん`, 日 (date) 14 `じゅうよっか`, 20 `はつか`, 24 `にじゅうよっか`, 31 `さんじゅういちにち`, 日間 20 `はつかかん`, 月 `4` `しがつ`, 12 `じゅうにがつ`; `testExtentsAreWhatEachCounterNeeds` (つ has exactly 11 keys; 時 stops at 24; 分 at 59; 日 and 日間 at 31; 月 at 12). Update the existing counts (counters 28 → 29, groups, section rows for `time-dates-age`).
- [ ] **Step 2: Run** `swift test --filter RealCountersData`; expect failures.
- [ ] **Step 3: Author the data** with a throwaway script (as in milestone 4): `extent` 10 for つ, 24 for 時, 59 for 分, 31 for both 日, 12 for 月, default elsewhere; `extra: [100]` for every counter with `extent` 99 except 時間; 円 `extra` of the spec's nineteen numbers with their `overrides`; `compound` for 人 (1 `いちにん`, 2 `ににん`, 0 `にん`), both 日 (units 1 to 9 as in the design: いちにち, ににち, さんにち, よっか, ごにち, ろくにち, しちにち, はちにち, くにち; 0 `にち`; for 日間 the same with かん), 時 (0 `じ`), 月 (0 `がつ`); overrides for 歳 20 `はたち`, 日 20 `はつか`, 日間 20 `はつかかん`; the 月 counter with its things (calendar, birthday, rainy season …), examples, a pitfall (しがつ, しちがつ, くがつ and 三月 vs 三か月), questions, `related` 日 and か月. Run `make data`; add the furigana entries the counted-run check requests (`fill_furigana` loop from milestone 4 applies); then fix what `make data-check` reports.
- [ ] **Step 4: Run** `make test`; expect PASS. Print the generated tables for 分, 時, 日, 人, 円 and 月 and read them against the appendix.
- [ ] **Step 5: Commit** `"Counters: readings from 11 up, round numbers for 円, and 月"`.

### Task 7: Budget and the unchanged app

**Files:**
- Test: `Packages/VerbKit/Tests/VerbKitTests/RealCountersDataTests.swift`

- [ ] **Step 1: Write the tests:** `testTheFileStaysUnderTheSizeBudget` (the byte count of `data/counters.json` is below 200,000); `testTheCoreNumbersAreUnchanged` (for every counter the readings for `CounterNumber.allCases` are non-empty and, for a recorded sample of ten counters, equal the values recorded in the test from before the change: 本 1 `いっぽん`, 分 4 `よんぷん`, 時 4 `よじ`, 人 1 `ひとり`, 日 1 `ついたち`, 円 4 `よえん`, 歳 8 `はっさい`, 階 3 `さんがい`, 羽 3 `さんば`, 足 3 `さんぞく`).
- [ ] **Step 2: Run** `swift test --filter RealCountersData`; expect PASS (adjust only if the data genuinely regressed).
- [ ] **Step 3: Build** the iOS app with `xcodebuild … build` and open the Counters tab in the simulator (home, a Compare table, a counter page): expect no change from before.
- [ ] **Step 4: Commit** `"Counters: pin the size budget and the unchanged core numbers"`.

### Task 8: Notes and the full run

**Files:**
- Modify: `docs/superpowers/specs/2026-10-26-counters-big-numbers-design.md`

- [ ] **Step 1: Update the design:** the Generation paragraph names `compound` and says an irregular counter composes through it; the Size paragraph says distractors exist for extended keys only when they changed or are authored; the appendix notes that only preferred tens prefixes compose.
- [ ] **Step 2: Add an "As built (stage 1)" section** (what changed, what was not checked, that the composition rules wait for the teacher, that the owner signs before merge).
- [ ] **Step 3: Run** `make test`, `make data-check`, `make check-project`; expect all green.
- [ ] **Step 4: Commit** `"Counters: stage 1 notes"`.

---

## Self-review notes

- **Coverage:** keys and fields (1), composition and class tables (2), generator, `changed`, `distractors` (3), validation (4), counted runs (5), data including 月 and 円's round numbers (6), size and unchanged core (7), docs (8). Stages 2 and 3 (stepper, Compare ranges, search, quiz) are out of this plan by design.
- **Names:** `plain_number`, `counter_keys`, `compose_readings`, `parse_numeral`, and the fields `extent`, `extra`, `compound` are used the same way in every task.
- **Risk:** the data is large and written by me; the hand-written class tables, the appendix and the teacher check are what stand between a wrong reading and the app.
