# Counters stage 2: the app shows numbers above 10 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A learner can look up, step through and compare the numbers above 10 that stage 1 put in `counters.json`, and can find them by search, each marked "unreviewed".

**Architecture:** The app derives nothing: it reads the extra keys in `readings`. `Counter` learns `extent` and `extra` (already in the data), `CounterNumber.kanji` covers any number, a pure `Counter.step` moves through a counter's extended numbers, and the SwiftUI screens (counter page stepper, Compare ranges, search rows) are thin views over those.

**Tech Stack:** Swift 6, SwiftUI, VerbKit (XCTest), iOS simulator.

**Spec:** `docs/superpowers/specs/2026-10-26-counters-big-numbers-design.md` ("App" section, stage 2). Changed since the spec: the owner dropped the teacher gate on 2026-10-27; numbers above 10 ship marked **unreviewed**, with the same small "unreviewed" text the Genki lesson mappings use (`App/GrammarDetailView.swift`).

## Global Constraints

- 1 to 10 and 何 look and work exactly as today (`CounterNumber.allCases` stays the core eleven; strip, widget, Sound patterns, quiz and Spotlight do not change).
- Old caches and old data (no `extent`/`extra`) decode: `extent` defaults to 10, `extra` to `[]`.
- Nothing above 10 is derived in the app; a number the counter has no key for is never offered.
- Every number above 10 shows "unreviewed"; one place decides it (`CounterNumber.isExtended`), so a later review status can replace it.
- Stage 3 (the Bigger numbers quiz, examples, pitfalls) is not in this plan.

## Review Focus

- A counter with no `extent` (old data) shows no stepper and no extra Compare ranges. Task 2, Task 4.
- 円 (`extra` 200 to 10000) steps 99, 100, 200 and back without offering 101 or 150. Task 2.
- A Forms search result for 十五分 or 3000円 opens the counter page on that number, with the stepper there. Task 3.
- A bare じゅう, さんじゅう or ひゃく query matches nothing; さんじゅうご does. Task 3.
- Largest Dynamic Type and VoiceOver: the stepper buttons say what they do and the row is not clipped. Task 4.

---

### Task 1: Model, kanji and stepping

**Files:**
- Modify: `Packages/VerbKit/Sources/VerbKit/Models/Counter.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/CounterDecodingTests.swift`, new `CounterSteppingTests.swift`

**Interfaces:**
- Produces: `CounterNumber.kanji` for 1 to 10000 (十五, 二十, 百, 三百, 千, 三千, 一万); `CounterNumber(key:)` accepts "1" to "10000" and "what"; `CounterNumber.isExtended: Bool` (`.n(v)` with v > 10); `Counter.extent: Int` (default 10), `Counter.extra: [Int]` (default `[]`), both optional in JSON; `Counter.extendedNumbers: [CounterNumber]` (11…extent then `extra`, only keys that have readings, ascending); `Counter.step(_ number: CounterNumber, by delta: Int) -> CounterNumber?`.

- [ ] **Step 1: Write failing tests.** `testKanjiForExtendedNumbers` (11 十一, 20 二十, 45 四十五, 100 百, 300 三百, 1000 千, 3000 三千, 10000 一万; 何 stays 何); `testKeysAboveTenParse` ("11", "100", "10000" parse; "0", "10001", "x" are nil); `testOldDataHasNoExtent` (decoding a counter without the fields gives extent 10, extra [], `extendedNumbers` empty); `testExtendedNumbersFollowTheData` (a fixture counter with extent 12 and extra [100] and readings for 11, 12, 100 gives [11, 12, 100]; a key without readings is skipped); in `CounterSteppingTests`: `+1` from 10 gives 11, `-1` from 11 is nil, `+10` from 10 gives 20, `+1` from 99 gives 100, an 円 fixture steps 100 → 200 on +1 and 200 → 100 on −10, `+10` at the last number clamps to the last, `+1` at the last is nil, a counter without extended numbers always gives nil.
- [ ] **Step 2: Run** `cd Packages/VerbKit && swift test --filter "CounterDecoding|CounterStepping"`; expect failures.
- [ ] **Step 3: Implement** in `Counter.swift` (keep the uncommitted `kanjiFor` work if it passes; tidy it). `step`: with `v` the current value (10 for a core number), the target is the first extended number ≥ v + delta for a positive delta (else the last one if it is above v), the last ≤ v + delta for a negative delta (else the first one if it is below v), nil when that equals `v` or the list is empty. Decode `extent` and `extra` with `decodeIfPresent`; add them to `CodingKeys` and the memberwise `init` with defaults.
- [ ] **Step 4: Run** the filter, then `make test-swift`; expect PASS.
- [ ] **Step 5: Commit** `"VerbKit: counters know their extended numbers"`.

### Task 2: Search finds extended numbers

**Files:**
- Modify: `Packages/VerbKit/Sources/VerbKit/Search/CounterSearch.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/CounterSearchTests.swift`

**Interfaces:**
- Consumes: `Counter.extendedNumbers`, `CounterNumber.kanji`.
- Produces: `kanjiNumerals(in:)` turns 1 to 10000 into kanji; `formMatches` also scans `counter.extendedNumbers`; `noisyFormPrefixes` gains にじゅう, さんじゅう, よんじゅう, ごじゅう, ろくじゅう, ななじゅう, はちじゅう, きゅうじゅう, ひゃく, ひゃっ.

- [ ] **Step 1: Write failing tests:** `kanjiNumerals(in: "15分")` is "十五分", "100円" "百円", "3000円" "三千円", "11本" "十一本", "0本" and "10001本" unchanged (replace the old `"11本"` unchanged assertion); a fixture 分 counter with extent 59 finds 十五分 and 15分 and じゅうごふん; the query さんじゅう finds no forms and さんじゅうご finds 三十五; a counter with no key for the number is not matched; 円 finds 三千円 from 3000円.
- [ ] **Step 2: Run** `swift test --filter CounterSearch`; expect failures.
- [ ] **Step 3: Implement** both changes; the 20-row cap stays.
- [ ] **Step 4: Run** the filter, then `make test-swift`; expect PASS.
- [ ] **Step 5: Commit** `"VerbKit: counter search covers numbers above 10"`.

### Task 3: Counter page stepper and the unreviewed label

**Files:**
- Create: `App/Counters/NumberStepper.swift`, `App/Counters/UnreviewedLabel.swift`
- Modify: `App/Counters/CounterDetailView.swift`, `App/Counters/ReadingBlock.swift`, `App/Counters/CounterSearchResults.swift`

**Interfaces:**
- Consumes: `Counter.step`, `Counter.extendedNumbers`, `CounterNumber.isExtended`.
- Produces: `NumberStepper(counter:selection:)` (− 10, − 1, the number, + 1, + 10; hidden when the counter has no extended numbers; before an extended number is selected it shows "11" dimmed and + steps into the range; buttons are disabled when `step` is nil; each has an accessibility label "Back ten", "Back one", "Forward one", "Forward ten"; the number reads "15, じゅうご"); `UnreviewedLabel()` is `Text("unreviewed").font(.caption2).foregroundStyle(.secondary)`, shown by `ReadingBlock` under the written form and by the Forms search row when `number.isExtended`, and in the block's accessibility label.

- [ ] **Step 1: Implement** the three views and the wiring below the strip (`NumberStrip` then `NumberStepper`). A Forms result with an extended number already opens the page on it (`focus`).
- [ ] **Step 2: Build** the iOS app (`make project`, then the simulator build); no new warnings.
- [ ] **Step 3: Verify in the simulator:** 分 steps 11 to 59 and 100, the tint and corner dot show on 三十 (さんじゅっぷん), "unreviewed" shows above 10 and not on 1 to 10; 円 steps 99, 100, 200 to 10000; a counter without extended numbers shows no stepper; the search 15分 opens the page on 15.
- [ ] **Step 4: Commit** `"Counters: step through numbers above 10, marked unreviewed"`.

### Task 4: Compare ranges

**Files:**
- Modify: `App/Counters/GroupTableView.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/CounterRangeTests.swift`, `Packages/VerbKit/Sources/VerbKit/Models/Counter.swift` (or a new `CounterRange.swift`)

**Interfaces:**
- Produces: `public enum CounterRange: CaseIterable { case core, elevenToTwenty, tens, hundredsUp }` with `title` ("1–10", "11–20", "30–90", "100+"), `numbers(for: [Counter]) -> [CounterNumber]` (core: `allCases`; 11–20; the round tens 30 to 90; 100 and above), and `static func available(for: [Counter]) -> [CounterRange]` (a range is available when some counter has readings for one of its numbers).

- [ ] **Step 1: Write failing tests:** a group of two core-only counters has only `.core`; a counter with extent 59 adds 11–20 and 30–90 but not 100+; 円 adds 100+ with 19 rows; a number only some counters have still appears as a row, and `numbers(for:)` leaves out numbers none has.
- [ ] **Step 2: Run** `swift test --filter CounterRange`; expect failures.
- [ ] **Step 3: Implement** `CounterRange`, then in `GroupTableView`: a segmented picker above the table (only when more than one range is available; remembered while the screen is open), rows from the range, a "—" for a counter that lacks the number, the number column wide enough for "10000" (scaled), the "unreviewed" label under the picker for any range but 1–10, and the Speak menu titled with the range.
- [ ] **Step 4: Run** the filter and `make test-swift`; build the app; check in the simulator: a group with 分 and 時 shows 11–20 and 30–90, the 円 group shows 100+, a core-only group shows no picker, largest Dynamic Type and a dark-mode glance.
- [ ] **Step 5: Commit** `"Counters: Compare tables show numbers above 10"`.

### Task 5: Docs

**Files:**
- Modify: `docs/superpowers/specs/2026-10-26-counters-big-numbers-design.md`, `README.md` if it lists counter features

- [ ] **Step 1:** In the design doc, note under Decisions that item 5 (teacher gate) was dropped on 2026-10-27 and the numbers ship "unreviewed"; add an "As built (stage 2)" section: what was built, what changed from the design, what was not checked (iPad, macOS, widgets).
- [ ] **Step 2: Run** `make test`, `make data-check`, `make check-project`; expect green.
- [ ] **Step 3: Commit** `"Counters: stage 2 notes"`.
