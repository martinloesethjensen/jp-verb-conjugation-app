# Counter Sound Patterns and Widget (Milestone 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Sound patterns screen (a row per sound class, which numbers change, tap a column to compare) and a Counter of the day widget showing the readings grid.

**Architecture:** Both features read only what is already in `counters.json`: a class's marked numbers are the numbers every one of its counters has in `changed`, so no data, manifest or pipeline change and no new signature. Two pure VerbKit functions carry the logic (`soundPatternRows`, `counterOfTheDay`) and are unit tested. The screen is a new `CounterDestination` in the Counters tab. The widget is a static-configuration widget in the existing extension, reading the shared SwiftData store like the Grammar widget.

**Tech Stack:** Swift 5 mode, SwiftUI (iOS 26), WidgetKit, SwiftData, XCTest.

**Spec:** `docs/superpowers/specs/2026-10-17-counters-design.md`, section "Milestone 3".

**Base:** `main` with milestones 1 and 2 merged. Branch: `claude/counters-patterns-widget`.

## Global Constraints

- Package tests: `swift test --package-path Packages/VerbKit`; commit only when the **exit code is 0**. Two timing tests (`testSearchStaysFastForFiveThousandEntries`, `testFiveThousandEntriesPlanQuickly`) fail intermittently under load; re-run alone before treating a failure as real.
- After adding app or widget files run `./scripts/generate-project.sh`. iOS build: `xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination 'id=<simulator UDID>' -derivedDataPath <scratch>/dd build`. **iPad and macOS checks are parked:** do not build the macOS scheme (the widget still declares only families that exist on both, like the Grammar widget).
- **No `data/` change.** If a task seems to need one, stop: every `data/` change needs the owner to sign the manifest (`python3 scripts/sign_manifest.py sign`), and Claude never signs.
- The app never derives a reading. Every reading shown, including the widget's, comes from `Counter.readings(for:)` and `Counter.isChanged(_:)`.
- A change is never shown by colour alone: tint plus the corner dot (as `ReadingCell`), plus an accessibility label saying "sound changes".
- Hidden JLPT levels (`LevelSettings`) apply to the patterns screen and the widget, as everywhere else.
- Widget deep link: `Route.counter(id).url` (`verbtable://counter/<id>`), already handled by `MainTabView`.
- Commit messages end with the trailer from the session's attribution reminder.

## Review Focus

Inputs the spec implies but no task's own tests would otherwise cover, most likely to bite first:

1. **Plain-class exceptions** (年 and 円 change at 4, 階 changes at 3 inside class `k`): these are single-counter exceptions, so they must not be marked as the class's pattern. Pinned in Task 1 against the real `data/counters.json`.
2. **Hidden levels empty a class** (or everything): the class row disappears; with nothing left the screen shows an empty state and the home tile is hidden. Pinned in Tasks 1 and 2.
3. **Widget with no data or all counters hidden:** no data shows "Open Verb Table to load counters"; levels hiding everything falls back to all counters, never the empty state (as the Grammar widget). Pinned in Task 3.
4. **Irregular row:** its marks are empty because every cell differs, so it must say "Irregular: learn each reading", not "no changes". Pinned in Task 1.
5. **Column compare for numbers where nothing shares a stem** (3, 4, 何): no stem caption is shown rather than a meaningless one (さん…). Pinned in Task 1.

---

## File Structure

- Create `Packages/VerbKit/Sources/VerbKit/Models/SoundPatterns.swift`: the pure row and stem logic.
- Create `Packages/VerbKit/Sources/VerbKit/Widget/CounterPick.swift`: the counter of the day.
- Create `App/Counters/SoundPatternsView.swift`: the screen.
- Modify `App/Counters/CountersTab.swift`: `CounterDestination.patterns` and its page.
- Modify `App/Counters/CountersHomeView.swift`: the "Sound patterns" tile.
- Create `Widgets/CounterWidget.swift`, `Widgets/CounterWidgetViews.swift`; modify `Widgets/VerbTableWidgets.swift`.
- Tests: `Packages/VerbKit/Tests/VerbKitTests/SoundPatternsTests.swift`, `CounterPickTests.swift`.
- Modify `docs/superpowers/specs/2026-10-17-counters-design.md` ("As built (milestone 3)").

---

### Task 1: Sound pattern rows

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Models/SoundPatterns.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/SoundPatternsTests.swift`

**Interfaces:**
- Consumes: `Counter` (`sound`, `changed`, `isChanged(_:)`, `readings(for:)`), `CounterNumber.allCases`.
- Produces:
  - `public struct SoundPatternRow: Identifiable, Hashable, Sendable` with `sound: String` (the class id, also `id`), `title: String`, `summary: String`, `counters: [Counter]` (members in data order), `marked: [CounterNumber]` (numbers every member changes, in `CounterNumber.allCases` order), `isIrregular: Bool`.
  - `public func soundPatternRows(from counters: [Counter]) -> [SoundPatternRow]`: one row per class that has at least one counter, in the fixed order plain, k, s, h-b, h-p, irregular. Titles and summaries are fixed copy: plain "Plain" ("The counter's sound never changes."), k "K sounds" ("か and こ turn into っか and っこ."), s "S sounds" ("さ turns into っさ at 1, 8 and 10."), h-b "H sounds (b/p)" ("は-row sounds turn into ぱ or ば."), h-p "H sounds (p)" ("は-row sounds turn into ぱ everywhere they can."), irregular "Irregular" ("Learn each reading.").
  - `public func soundPatternStem(for number: CounterNumber, in rows: [SoundPatternRow]) -> String?`: for the non-irregular rows that mark `number` (needs at least two), the longest common prefix of each row's first member's preferred reading; returned only if it ends in small っ, else nil.

- [ ] **Step 1: Write the failing tests** in `SoundPatternsTests.swift`. Build fixture counters with `Counter(id:counter:reading:meaning:sound:symbol:readings:changed:)`; for the synthetic tests supply only the keys the test reads. Tests (names and assertions):
  - `testRowsAreInFixedOrderAndSkipEmptyClasses`: counters of classes h-b, plain, k → rows `["plain", "k", "h-b"]`.
  - `testMarkedIsTheIntersectionOfMembers`: two `k` counters with `changed` `["1","6"]` and `["1","3","6"]` → marked `[.n(1), .n(6)]`.
  - `testSingleCounterExceptionsAreNotMarked`: two `plain` counters, one with `changed: ["4"]`, one with `[]` → marked is empty.
  - `testIrregularRowIsFlagged`: one `irregular` counter → `isIrregular` true, `marked` empty.
  - `testStemForSixIsRokkuAcrossKAndHRows`: rows k (ろっこ), h-b (ろっぽん), h-p (ろっぷん), all marking 6 → `soundPatternStem(for: .n(6), …) == "ろっ"`.
  - `testNoStemWhenNothingSharedOrOnlyOneRow`: 3 marked by h-b (さんぼん) and h-p (さんぷん) → nil (the prefix さん does not end in っ); 4 marked by h-p only → nil.
  - `testRealDataPatterns` (loads `data/counters.json` like `RealCountersDataTests`): `plain` marked is empty (年 and 円 excluded), `k` marked is `[1, 6, 8, 10]` (階's 3 excluded), `s` is `[1, 8, 10]`, `h-b` is `[1, 3, 6, 8, 10, 何]`, `h-p` is `[1, 3, 4, 6, 8, 10, 何]`, and the stem for `.n(6)` is `"ろっ"`.

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --package-path Packages/VerbKit --filter SoundPatternsTests`
Expected: FAIL (compile error: `soundPatternRows` not found).

- [ ] **Step 3: Implement** `soundPatternRows` and `soundPatternStem` with the signatures above in `SoundPatterns.swift`. Marked is `CounterNumber.allCases.filter { n in counters.allSatisfy { $0.isChanged(n) } }` per class; the common prefix is computed per `Character`.

- [ ] **Step 4: Run to verify they pass**

Run: `swift test --package-path Packages/VerbKit --filter SoundPatternsTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit** `Counters milestone 3: sound pattern rows` (add both files).

---

### Task 2: The Sound patterns screen

**Files:**
- Create: `App/Counters/SoundPatternsView.swift`
- Modify: `App/Counters/CountersTab.swift` (`CounterDestination`, `CounterDestinationView`), `App/Counters/CountersHomeView.swift`

**Interfaces:**
- Consumes: `soundPatternRows(from:)`, `soundPatternStem(for:in:)`, `CountersStore.counters`, `LevelSettings`, the existing `GroupTile`.
- Produces: `CounterDestination.patterns`; `struct SoundPatternsView: View` (no parameters).

- [ ] **Step 1: Add `case patterns` to `CounterDestination`** and a `case .patterns: SoundPatternsView()` in `CounterDestinationView`; add a `GroupTile` after "All counters" in the home grid: title "Sound patterns", symbol `waveform`, counters text "ろっ · いっ · …", spoken "which numbers change sound"; it goes to `.patterns` and is hidden when `visible` is empty.

- [ ] **Step 2: Build `SoundPatternsView`.** It reads `store.counters.visible(in:)` with the same `@AppStorage(LevelSettings.defaultsKey, store: .appGroup)` pattern as `CountersTab`, builds rows, and shows a vertical list of cards, one per row:
  - Title (headline), summary (footnote), the member counters joined with " · " (`title3`, secondary).
  - A strip of 11 number columns (1…10, 何) under the member line. Each column shows the number label and a mark if `row.marked` contains it: the orange tint plus corner dot of `ReadingCell`, never colour alone. The irregular card shows "Irregular: learn each reading" instead of a strip.
  - Tapping a column in any card sets `@State selected: CounterNumber?` (tap again clears); the selected column gets the accent ring in every card.
  - Below the list (or pinned under the title), a caption for the selection: with a stem, "6 → ろっ in K sounds, H sounds (b/p) and H sounds (p)" built from the rows that mark it; without a stem, only "6 changes in …" or "6 never changes in these classes" when no row marks it. Navigation title "Sound patterns".
  - Empty (`rows.isEmpty`): `ContentUnavailableView("No Counters", systemImage: "waveform")` with the line "Counters hidden by your level settings have no patterns to show."
  - Accessibility: each column cell is one element, label "6, sound changes" or "6, no change", trait `.isButton`; the selection caption is an `accessibilityElement` with the same text; layout wraps at accessibility text sizes (scroll sideways rather than truncate, as the group table does).

- [ ] **Step 2b: Regenerate and build**

Run: `./scripts/generate-project.sh && xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination 'id=<simulator UDID>' -derivedDataPath <scratch>/dd build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Check on the iPhone simulator** (counters come from the real store or a temporary seed as in milestone 1): open Counters → Sound patterns; the k row marks 1, 6, 8, 10; tapping 6 rings the column in every row and the caption reads ろっ; irregular shows its line; hiding N5 in Settings removes the tile. Take a screenshot as proof; record anything not checked.

- [ ] **Step 4: Run the package tests** (`swift test --package-path Packages/VerbKit`, exit 0), then commit `Counters milestone 3: the sound patterns screen`.

---

### Task 3: Counter of the day widget

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Widget/CounterPick.swift`, `Widgets/CounterWidget.swift`, `Widgets/CounterWidgetViews.swift`
- Modify: `Widgets/VerbTableWidgets.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/CounterPickTests.swift`

**Interfaces:**
- Consumes: `DailyPick.element(of:on:calendar:)`, `Counter`, `LevelSettings`, `[Counter].visible(in:)`, `SwiftDataCountersPersisting`, `VerbModelContainer.make()`, `Route.counter(_:).url`.
- Produces: `public func counterOfTheDay(from counters: [Counter], levels: LevelSettings, on date: Date, calendar: Calendar = .current) -> Counter?`: picks from the visible counters, falling back to all of them when the levels hide everything, nil only when `counters` is empty. Widget side: `CounterEntry(date:, counter: Counter?)`, `CounterProvider: TimelineProvider`, `CounterOfTheDayWidget` (kind `"CounterOfTheDayWidget"`), `CounterWidgetView`.

- [ ] **Step 1: Write the failing tests** in `CounterPickTests.swift` (fixtures as in Task 1):
  - `testSameDayGivesSameCounter`: the same counter at 01:00 and 23:00 of one day, with a gregorian calendar.
  - `testHiddenLevelsAreSkipped`: an N5 and an N4 counter, N5 hidden → the N4 counter on every day of a week.
  - `testFallsBackToAllWhenLevelsHideEverything`: only N5 counters, N5 hidden → non-nil.
  - `testEmptyGivesNil`.

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --package-path Packages/VerbKit --filter CounterPickTests`
Expected: FAIL (compile error: `counterOfTheDay` not found).

- [ ] **Step 3: Implement `counterOfTheDay`** in `CounterPick.swift`.

- [ ] **Step 4: Run to verify they pass**

Run: `swift test --package-path Packages/VerbKit --filter CounterPickTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Build the widget.** In `CounterWidget.swift` copy the Grammar widget's shape: a `@MainActor enum CounterLoader { static func counters() -> [Counter] }` over `SwiftDataCountersPersisting` (`loadCounters()?.counters ?? []`), a `TimelineProvider` (placeholder with a sample 本 counter built inline) whose timeline is two entries (now, and next midnight with tomorrow's counter) with policy `.after(nextMidnight)`, and `StaticConfiguration`, families `[.systemSmall, .systemMedium]`, display name "Counter of the Day", description "A counter and all its readings, from Verb Table." Register it in `VerbTableWidgets.body`. In `CounterWidgetViews.swift`, same navy gradient container as the Grammar widget, `.widgetURL(Route.counter(id).url)`:
  - Small: the counter (large), its reading and meaning, and below it one line "Changes at 1 · 3 · 6 …" from `changed` (or "Irregular" for an empty `changed` on an irregular counter, "No sound changes" otherwise).
  - Medium: the header on the left; on the right the 11 readings (`Counter.readings(for:).first`) in a grid of 4 columns, the written form small above each reading, changed cells tinted orange with the corner dot as in `ReadingCell`.
  - No data: "Open Verb Table to load counters", centred, caption font.

- [ ] **Step 6: Regenerate, build and check**

Run: `./scripts/generate-project.sh && xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination 'id=<simulator UDID>' -derivedDataPath <scratch>/dd build`
Expected: `BUILD SUCCEEDED`. Then add the widget in the iPhone simulator (small and medium) and take a screenshot. If it cannot be added from the shell, say so in the as-built notes rather than claiming it was checked.

- [ ] **Step 7: Run the package tests** (exit 0) and commit `Counters milestone 3: the counter of the day widget`.

---

### Task 4: Docs

**Files:**
- Modify: `docs/superpowers/specs/2026-10-17-counters-design.md`; `README.md` only if it lists the Counters features.

- [ ] **Step 1: Add "As built (milestone 3)"** after the milestone 2 section: marked numbers are the intersection of a class's counters (and why), the stem rule (ends in っ), the widget's fallback and its families, what was checked (screenshots) and what was not (VoiceOver, Reduce Motion, largest text size, iPad, macOS, widget on the Lock Screen, which has no family).

- [ ] **Step 2: Run the whole suite** (`swift test --package-path Packages/VerbKit`, exit 0) and commit `Counters milestone 3: as built`. Open the PR with the PR description noting there is **no data change**, so no signature is needed, and that the screen copy is unreviewed.
