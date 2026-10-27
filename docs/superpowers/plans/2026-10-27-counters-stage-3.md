# Counters stage 3: the Bigger numbers quiz and content Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A learner can be quizzed on the numbers above 10 (二十歳, 三十分, 三百円) and finds examples and pitfalls for the ones they meet first.

**Architecture:** *Bigger numbers* reuses the existing `.counterReading` question kind (history, weak spots and "Practise missed" key by counter and number key, so nothing new is stored). A new builder draws (counter, number) pairs from `Counter.extendedNumbers`, weighted toward numbers whose sound changed and irregular counters. The sheet gains a row; Mixed gets a small sample. Content is authored in `data/counters.json` and needs the owner's signature.

**Tech Stack:** Swift 6, SwiftUI, VerbKit (XCTest), Python data pipeline.

**Spec:** `docs/superpowers/specs/2026-10-26-counters-big-numbers-design.md` ("Quiz" and "Examples and pitfalls" under App, stage 3). iOS only: Android, watchOS, macOS and iPad are parked.

## Global Constraints

- *Read it* keeps drawing from 1 to 10 and 何 only; extended numbers appear only in *Bigger numbers*, Weak spots and a Mixed sample.
- No new `QuizQuestionKind` (old history and old builds keep decoding).
- Every question about a number above 10 shows the same small "unreviewed" label as stage 2.
- A (counter, number) pair with no wrong choice to offer is skipped; the result is never padded.
- `data/` changes need the owner's signature; do not sign.

## Review Focus

- Weak spots lists a wrong 三十分 (today it silently drops any key above 10). Task 1.
- A counter with nothing above 10 makes no Bigger numbers question; with every counter hidden by level settings the row is disabled. Task 2, Task 3.
- 三十分's wrong choices are real readings of other bigger numbers, never an accepted reading. Task 2.
- The explanation after a wrong answer names the pattern for an extended number (not "changes at 1, 3, 6…"). Task 2.
- New examples' counted runs read as their counter says and have furigana (`make data-check`). Task 4.

---

### Task 1: Weak spots keep numbers above 10

**Files:**
- Modify: `Packages/VerbKit/Sources/VerbKit/Quiz/QuizProgress.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/QuizProgressTests.swift`

**Interfaces:**
- Produces: `QuizProgress.weakCounterPairs` includes pairs whose `formID` is any valid `CounterNumber(key:)` (core or above 10), ordered by weakness, then recency, then counter id, then number value.

- [ ] **Step 1: Write failing test** `testWeakCounterPairsIncludeNumbersAboveTen`: three wrong `.counterReading` attempts on ("fun", "30") and one on ("hon", "3"); `weakCounterPairs` contains `.n(30)` for fun first; a bogus `formID` ("banana") is still dropped.
- [ ] **Step 2: Run** `cd Packages/VerbKit && swift test --filter QuizProgress`; expect the new test to fail.
- [ ] **Step 3: Implement** by replacing the core-only `numbers` dictionary with `CounterNumber(key:)` validity and `sortValue` ordering.
- [ ] **Step 4: Run** the filter; expect PASS.
- [ ] **Step 5: Commit** `"Quiz: weak spots keep numbers above 10"`.

### Task 2: The Bigger numbers builder

**Files:**
- Modify: `Packages/VerbKit/Sources/VerbKit/Quiz/CounterQuestion.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/CounterQuestionTests.swift`

**Interfaces:**
- Produces: `public func buildBiggerNumberQuestions(counters: [Counter], count: Int, using generator: inout some RandomNumberGenerator) -> [CounterQuestion]` and an overload without the generator (system RNG): `.counterReading` questions for `Counter.extendedNumbers`, drawn without replacement with weight 4 for a changed number or an irregular counter and weight 1 otherwise; `buildCounterQuestions(pairs:count:)` also accepts extended numbers. Wrong choices: generated `distractors`, then preferred readings of the nearest other numbers in the same pool (extended numbers for an extended one), never an accepted reading. The explanation for an extended number: irregular counter → "…is irregular: learn each reading. 三十歳 is …"; changed → "三十分 is さんじゅっぷん: the sound changes here, as it does at <core changed numbers>"; plain → "三十枚 keeps its plain reading: …".

- [ ] **Step 1: Write failing tests:** `testBiggerNumbersAreExtendedNumbersOnly` (every question's `formID` is above 10, kind `.counterReading`, prompt is the written form, `correct` is the first reading, `accepted` all readings); `testNoExtendedNumbersMeansNoQuestions`; `testWrongChoicesAreOtherNumbersReadings` (fixture counter: no choice is in `accepted`, no duplicates); `testChangedNumbersAreDrawnMoreOften` (seeded generator, 200 draws of one question: the changed number appears more than twice as often as a plain one); `testExplanationNamesThePatternForAnExtendedNumber`; `testPairsAcceptExtendedNumbers`; `testCoreReadItStillExcludesExtendedNumbers` (existing builders never return a formID above 10).
- [ ] **Step 2: Run** `swift test --filter CounterQuestion`; expect failures.
- [ ] **Step 3: Implement** by generalising `wrongReadings` and `readingExplanation` to a number pool and extended wording; weighted draw by key `pow(random, 1/weight)` (Efraimidis–Spirakis), take the largest `count`.
- [ ] **Step 4: Run** the filter, then `make test-swift`; expect PASS.
- [ ] **Step 5: Commit** `"Quiz: a Bigger numbers question builder"`.

### Task 3: The sheet row, the sample in Mixed, the label

**Files:**
- Modify: `App/Counters/CounterQuizSheet.swift`, `App/Counters/CountersTab.swift`, `App/Counters/CounterQuizView.swift`

**Interfaces:**
- Consumes: `buildBiggerNumberQuestions`, `CounterNumber(key:)`, `UnreviewedLabel`.
- Produces: `CounterQuizSelection.biggerNumbers`; sheet row "Bigger numbers" with detail "三十分 is さんじゅっぷん", disabled when the builder makes nothing under the level settings; Mixed = Which counter + Read it + Ask it plus a sample of up to a fifth of the count from Bigger numbers; Weak spots unchanged (Task 1 widens it). The question card shows `UnreviewedLabel` when a `.counterReading` question's `formID` is above 10.

- [ ] **Step 1: Implement** the three edits.
- [ ] **Step 2: Build** the iOS app (`make project` first).
- [ ] **Step 3: Verify in the simulator:** open Counters > Quiz: the row is there and enabled; a Bigger numbers round asks about 11+ numbers with the "unreviewed" label and a pattern explanation after a wrong answer; Read it never asks above 10; Mixed runs.
- [ ] **Step 4: Commit** `"Counters: the Bigger numbers quiz"`.

### Task 4: Examples and pitfalls for the numbers learners meet first

**Files:**
- Modify: `data/counters.json` (via `make data` for versions, hashes and bundled copies), `data/furigana.json` if the pipeline asks, `Packages/VerbKit/Tests/VerbKitTests/RealCountersDataTests.swift`

**Interfaces:**
- Produces: examples and pitfalls using 三十分 さんじゅっぷん (分), 四十分 よんじゅっぷん (分), 十四日 じゅうよっか and 二十日 はつか (日, date), 百円 ひゃくえん (円); 二十歳 and 十二月 already exist. Counted runs read as their counter says (the pipeline checks it).

- [ ] **Step 1: Write failing test** in `RealCountersDataTests`: the real data's 分 has an example containing 三十分 and a pitfall naming 三十分 or 四十分; 日 (date) has one containing 二十日 and one containing 十四日; 円 has one containing 百円.
- [ ] **Step 2: Run** `swift test --filter RealCountersData`; expect failures.
- [ ] **Step 3: Author** the entries with English glosses and `readings` overrides where a dictionary key cannot read them (二十日 はつか, 十四日 じゅうよっか); then `make data`, `make data-check`, `make test`.
- [ ] **Step 4: Run** the filter and `make test`; expect PASS. `make verify` fails until the owner signs; say so.
- [ ] **Step 5: Commit** `"Counters: examples and pitfalls for bigger numbers"`.

### Task 5: Docs

**Files:**
- Modify: `docs/superpowers/specs/2026-10-26-counters-big-numbers-design.md`

- [ ] **Step 1:** Add "As built (stage 3)": what was built, what changed from the design (Weak spots needed a fix; no new question kind), what was not checked.
- [ ] **Step 2: Run** `make test`, `make data-check`, `make check-project`; expect green.
- [ ] **Step 3: Commit** `"Counters: stage 3 notes"`.
