# Counters milestone 4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add ten counters (durations, 足, 着, 頭, 羽, 番), a when-or-how-long comparison, and 何 + counter practice to the counter quiz.

**Architecture:** Content goes into `data/counters.json` and is generated and validated by `scripts/update_data.py`; one validator fix lets 時間 coexist with 時. A new optional `questions` field feeds a new `counterAsk` quiz kind built in VerbKit and shown by the existing counter quiz screens.

**Tech Stack:** Python (unittest), Swift 6 / SwiftUI, VerbKit (XCTest), iPhone simulator.

**Spec:** `docs/superpowers/specs/2026-10-23-counters-milestone-4-design.md` (the counter table, groups, sections and quiz behaviour are there).

## Global Constraints

- The app derives no readings: everything comes from `counters.json`.
- Every `data/` change is re-signed by the owner (`make sign-commit`), on the feature branch; do not sign.
- New fields are optional in decoding; an old cache and old builds keep working.
- Content is the assistant's and unreviewed; say so in the as-built notes.
- iPad, macOS, Android and watchOS are not touched.

## Review Focus

- 三時 inside 三時間 (and 三日 inside 三日間, 三年 inside 三年間) is not read as a wrong reading of the shorter counter. Task 1.
- A `questions` entry whose `jp` lacks 何 plus its own counter, or has a wrong reading, is rejected by the validator. Task 1.
- A counter with no `questions` (つ) makes no 何 question, and a quiz built from counters that all lack them is empty, not a crash. Task 4.
- Two counters written alike (日 date and 日 days) never put the same button on screen twice in *Ask it*. Task 4.
- An old cache with no `questions` decodes and the Ask it row is disabled, not broken. Task 4 and Task 5.
- 4時間 よじかん, 7時間 ななじかん, 9時間 くじかん and 4年間 よねんかん read as the spec says. Task 2.

---

### Task 1: Validator changes

**Files:**
- Modify: `scripts/update_data.py` (`check_counted_runs`, `check_counters`)
- Modify: `scripts/test_update_data.py`

**Interfaces:**
- Produces: counted runs followed by 間 are skipped unless the counter itself ends in 間; `check_counters` validates an optional `questions` list and `check_counted_runs` also reads each question's `jp`.

- [ ] **Step 1: Write failing tests** in `test_update_data.py`: (a) `test_a_counted_run_inside_a_longer_counter_is_not_checked`: a 時 counter whose example is `三時間勉強しました。` with no 時間 reading in furigana gives no problem from `check_counted_runs`, while `三時` alone still does; (b) `test_a_counter_ending_in_kan_checks_its_own_runs`: a 時間 counter whose example `三時間` reads wrong is reported; (c) `test_question_problems` in `CheckCountersTests` with needles `"questions must be a list"`, `"question jp"` (missing or empty), `"question en"`, `"must contain 何"` (a `jp` without 何+counter), and an entry that is not an object; (d) `test_a_valid_question_passes`.
- [ ] **Step 2: Run** `python3 -m unittest discover -s scripts`; expect the new tests to fail.
- [ ] **Step 3: Implement** the lookahead (`(?!間)` appended unless `c["counter"].endswith("間")`) in `check_counted_runs`, a `_check_questions(cid, counter, problems)` helper called from `check_counters`, and the questions sources in `check_counted_runs`.
- [ ] **Step 4: Run** `make test-py`; expect PASS. Run `make data-check`; expect "data is up to date" (the real data has no questions yet).
- [ ] **Step 5: Commit** `"Counters: validate 何 questions and compound counted runs"`.

### Task 2: The ten counters (data)

**Files:**
- Modify: `data/counters.json`, `data/furigana.json`, `data/manifest.json` (via `make data`)
- Modify: `Packages/VerbKit/Tests/VerbKitTests/RealCountersDataTests.swift`

**Interfaces:**
- Produces: counters `jikan`, `shuukan`, `kagetsu`, `nenkan`, `nichikan`, `soku`, `chaku`, `ban`, `tou`, `wa`; groups `durations`, `clothes`, `order`; sections as in the spec.

- [ ] **Step 1: Update `RealCountersDataTests`** (watch it fail): `testTheHomeSectionsCoverEveryCounterInTheChosenOrder` expects the eight section ids in spec order and the new row counts; add `testTheNewCountersReadAsTheSpecSays` asserting the preferred readings: 4時間 よじかん, 7時間 ななじかん, 9時間 くじかん, 8週間 はっしゅうかん, 6ヶ月 ろっかげつ, 4年間 よねんかん, 2日間 ふつかかん, 3足 さんぞく, 何足 なんぞく, 8着 はっちゃく, 3羽 さんば, 6羽 ろっぱ, 3頭 さんとう, 何番 なんばん, and that 羽 lists うさぎ as primary.
- [ ] **Step 2: Run** `swift test --filter RealCountersData`; expect FAIL.
- [ ] **Step 3: Author the counters** with a throwaway script in the scratchpad that loads `counters.json`, appends the ten counters (fields as in the spec table, `symbol` an SF Symbol, 3 to 5 things, 2 or 3 examples, pitfalls, `related`), the groups and sections, and writes through `update_data.dump_counters`. Then `make data`; fix every problem `make data-check` reports (missing furigana for counted runs and kanji, bad readings) by adding entries to `furigana.json`.
- [ ] **Step 4: Run** `make test` and `make data-check`; expect PASS. Review the generated `readings` for each new counter against the spec table.
- [ ] **Step 5: Commit** `"Counters: ten new counters, groups and sections"`.

### Task 3: 何 questions (data)

**Files:**
- Modify: `data/counters.json`, `data/furigana.json`, `data/manifest.json`

**Interfaces:**
- Produces: `questions: [{"jp", "en"}]` on every counter except つ, each `jp` containing 何 plus the counter.

- [ ] **Step 1: Write the questions** with the scratchpad script: one per counter, two for 時 and 日 (date and days) where the pair needs separating (何時 / 何時間, 何日 / 何日間), `jp` a natural sentence with a counted run of 何, `en` the question in English.
- [ ] **Step 2: Run** `make data` then `make data-check`; fix reported problems (furigana for 何 runs and sentence words).
- [ ] **Step 3: Run** `make test`; expect PASS.
- [ ] **Step 4: Commit** `"Counters: 何 questions for every counter"`.

### Task 4: `counterAsk` in VerbKit

**Files:**
- Modify: `Packages/VerbKit/Sources/VerbKit/Models/Counter.swift`, `Quiz/QuizQuestion.swift`, `Quiz/CounterQuestion.swift`, `Quiz/QuizGenerator.swift`
- Test: `CounterDecodingTests.swift`, `CounterQuestionTests.swift`, `QuizQuestionTests` (kind round trip)

**Interfaces:**
- Produces:
  - `public struct CounterAsking: Codable, Hashable, Sendable { public var jp: String; public var en: String }`
  - `Counter.askings: [CounterAsking]` decoded from the optional `questions` key (default `[]`; also an init parameter `askings: [CounterAsking] = []`)
  - `QuizQuestionKind.counterAsk`, with `isCounter` true for it
  - `buildCounterQuestions(counters:groups:kind:count:)` with `.counterAsk`: one question per asking; prompt = `en`; detail = "Pick the 何 phrase"; `correct` = `counter.written(.what)`; `accepted` = every counter written the same way that has this asking (just that one); choices = correct plus up to three wrong 何 phrases from other counters that have askings, those sharing a group first, never the same written form twice; `formID` = the asking's `jp`; `explanation` = `"\(jp)  (\(readings(for: .what).first!))"`; skipped when it cannot get one wrong choice.

- [ ] **Step 1: Write failing tests:** decoding a counter with and without `questions`; `.counterAsk` builds one question per asking; the correct choice is the 何 phrase and no choice repeats; wrong choices from the same group come first; a counter without askings contributes none and an empty input gives `[]`; two counters written 日 never both appear; the explanation holds the Japanese sentence and the 何 reading; the new kind survives encode/decode and old unknown kinds still skip.
- [ ] **Step 2: Run** `swift test --filter "CounterDecoding|CounterQuestion|QuizQuestion"`; expect failures.
- [ ] **Step 3: Implement** the types and builder; make `QuizGenerator`'s exhaustive switches treat `.counterAsk` like the other counter kinds.
- [ ] **Step 4: Run** `make test-swift`; expect PASS.
- [ ] **Step 5: Commit** `"VerbKit: 何 questions for the counter quiz"`.

### Task 5: Ask it in the app

**Files:**
- Modify: `App/Counters/CounterQuizSheet.swift`, `App/Counters/CountersTab.swift`, `App/Counters/CounterQuizView.swift`, `App/QuizQuestionView.swift` (exhaustive switch)

**Interfaces:**
- Consumes: `buildCounterQuestions(... kind: .counterAsk ...)`.
- Produces: `CounterQuizSelection.askIt`; an "Ask it" row on the quiz sheet, disabled when no question can be built; Mixed includes it; the quiz header reads "Which 何 phrase?" for the kind.

- [ ] **Step 1: Wire the selection** (`.askIt` builds `.counterAsk`; `available(.counterAsk)` drives the row) and the quiz view's header and result text (the Japanese sentence and the 何 reading shown after answering; speak the sentence).
- [ ] **Step 2: Build** `xcodebuild … build`; expect BUILD SUCCEEDED.
- [ ] **Step 3: Verify in the simulator:** the start sheet shows Ask it, a question shows the English prompt and four 何 phrases, a wrong answer shows the explanation, hiding every level disables the row.
- [ ] **Step 4: Commit** `"Counters: Ask it in the counter quiz"`.

### Task 6: Verify, notes, review

- [ ] **Step 1: Run** `make test`, `make data-check`, `make check-project`, and build the iOS app; expect all green.
- [ ] **Step 2: Check in the simulator** (with the data seeded locally if it is not yet published): the new sections on the home list, the "When or how long?" Compare table, a duration page (時間, 4時間 の pitfall), 羽 and 頭 under People & animals, a 何 question.
- [ ] **Step 3: Write an "As built" section** in the milestone-4 spec (what changed, what was not checked, the content is unreviewed) and update the Android and watchOS follow-up notes only if their issues name the counter list.
- [ ] **Step 4: Commit** `"Counters milestone 4: as-built notes"`.

---

## Self-review notes

- **Coverage:** ten counters (Task 2), compound run fix and question validation (Task 1), comparison (Task 2 sections), 何 questions (Tasks 3 to 5), docs (Task 6). Months and numbers above 10 are out of scope, as the spec says.
- **Names:** `CounterAsking`, `Counter.askings`, `QuizQuestionKind.counterAsk`, `CounterQuizSelection.askIt` are used consistently.
- **Content risk:** readings are generated and validated; sentences, things and pitfalls are the assistant's and unreviewed.
