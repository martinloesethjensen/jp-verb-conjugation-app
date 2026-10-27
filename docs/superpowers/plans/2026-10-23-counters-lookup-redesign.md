# Counters lookup-first redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Counters tiles, tall counter page and class-card Sound patterns with a searchable directory, a one-screen reading block and a number-by-first-sound table.

**Architecture:** A new optional `sections` key in `data/counters.json` drives the home list (the app falls back to `groups` without it). The compare table, counter page and Sound patterns screen are SwiftUI rewrites over small, testable VerbKit models. `groups` keep serving quiz distractors, search results and routes.

**Tech Stack:** Python (`scripts/update_data.py`, unittest), Swift 6 / SwiftUI, VerbKit (XCTest, `swift test`), iPhone simulator for visual checks.

**Spec:** `docs/superpowers/specs/2026-10-23-counters-lookup-redesign-design.md` (read it; it holds the mockup decisions). Baseline screenshots of the old screens are in the 2026-10-23 session critique.

## Global Constraints

- The app never derives a reading: it reads `readings`, `changed` and `sound` from `counters.json`. No hard-coded reading rules.
- `sections` is optional in the data and in decoding; old caches and old app builds must keep working.
- Every `data/` change is re-signed by the owner before merge (`make sign-commit`); do not sign or push data yourself.
- Tap targets at least 44 pt; VoiceOver labels keep "sound changes" on tinted cells; Dynamic Type works through accessibility sizes; Reduce Motion respected.
- Counters hidden by the level settings are left out everywhere, and a section with none left is hidden.
- `groups` keep driving the quiz, the Groups section of search results and `verbtable://counters/<id>` (a group id); those keep opening the existing group table.
- iPad and macOS are not redesigned or verified here (parked); they must keep compiling.
- Delivery in two stages: Task 1 (data) is its own small PR the owner signs; Tasks 2 to 8 follow.

## Review Focus

- A counter listed in two sections (本, つ) must not break `ForEach` identity or navigation. Task 2 pins unique row ids; Task 4 checks tapping the second 本.
- Cached data with no `sections` (an old install) shows the groups as sections, not an empty home. Task 2.
- Level settings that hide every counter in a section, or every counter at all, hide the section or show the empty state, with no crash. Task 2 and Task 4.
- A counter with no pitfalls, no things or no examples drops the hint and the empty segment instead of showing an empty tab. Task 3 and Task 6.
- Accessibility text sizes: the number strip must wrap or scroll rather than truncate readings, and compare rows must grow. Task 5 and Task 6.
- A Forms search result (3本) still lands on the counter page with 3 selected. Task 6.

---

### Task 1: `sections` in the data pipeline (separate PR, owner signs)

**Files:**
- Modify: `scripts/update_data.py` (`check_counters` near line 962, `dump_counters` near line 1046)
- Modify: `scripts/test_update_data.py` (`CheckCountersTests`, `counters_doc`, dump tests)
- Modify: `data/counters.json`, then `make data` for the manifest hash

**Interfaces:**
- Produces: `counters.json` top-level `"sections": [{"id", "title", "counters": [counter ids]}]`, in display order, one line per section when dumped.

- [ ] **Step 1: Write failing tests** in `scripts/test_update_data.py`. Extend `counters_doc(*counters, groups=None, sections=None)` to include `"sections"` only when given. Add `test_section_problems` in `CheckCountersTests` asserting a problem containing each needle: `"duplicate section"` (two sections with one id), `"not a counter"` (unknown id in `counters`), `"listed twice"` (same id twice in one section), `"in no section"` (a counter in no section), `"title"` (empty title). Add `test_sections_are_optional` (a doc without `sections` has no problems) and `test_a_counter_may_be_in_two_sections` (same id in two different sections is valid). Add `test_dump_puts_each_section_on_one_line` modelled on the existing group dump test.
- [ ] **Step 2: Run** `python3 -m unittest scripts.test_update_data -k Section` (or `make test-py`); expect the new tests to fail.
- [ ] **Step 3: Implement** the validation after the groups loop in `check_counters` (rules above, only when `"sections"` is present, which must be a list) and add `"sections"` to the key lists in `dump_counters`.
- [ ] **Step 4: Run** `make test-py`; expect PASS.
- [ ] **Step 5: Author the data.** Add to `data/counters.json`, in this order and with these exact members (titles are the spec's):
  - `drinks` "Drinks": hai, hon, tsu
  - `people-animals` "People & animals": nin, hiki
  - `things` "Things": mai, dai, satsu, ko, hon, tsu
  - `time-dates-age` "Time, dates & age": ji, fun, nichi-date, nichi-days, nen, sai
  - `money-events` "Money & counting events": en, kai, kai-floor
- [ ] **Step 6: Run** `make data` then `make data-check`; expect no problems and an updated `data/manifest.json` hash. Do not run `make sign`.
- [ ] **Step 7: Commit** on its own branch: `git add scripts data && git commit -m "Counters: add sections for the home list"`. Open the PR and note that the owner must run `make sign-commit` before merge.

### Task 2: Sections in VerbKit (model, decoding, store, home list)

**Files:**
- Modify: `Packages/VerbKit/Sources/VerbKit/Models/Counter.swift` (add `CounterSection`; `CountersDataFile.sections`)
- Modify: `Packages/VerbKit/Sources/VerbKit/Store/CountersStore.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Models/CounterHome.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/CounterDecodingTests.swift`, `CountersStoreTests.swift`, new `CounterHomeTests.swift`

**Interfaces:**
- Produces:
  - `public struct CounterSection: Codable, Hashable, Identifiable, Sendable { id: String; title: String; counters: [String] }`
  - `CountersDataFile.sections: [CounterSection]` (decodeIfPresent, default `[]`; init parameter `sections: [CounterSection] = []`)
  - `CountersStore.sections: [CounterSection]`: the file's sections, or one section per group (id, title, members' ids) when the file has none.
  - `public struct CounterHomeRow: Identifiable, Hashable, Sendable { section: String; counter: Counter; var id: String { "\(section)/\(counter.id)" } }`
  - `public struct CounterHomeSection: Identifiable, Hashable, Sendable { section: CounterSection; rows: [CounterHomeRow]; var id: String; var canCompare: Bool { rows.count > 1 } }`
  - `public func homeSections(_ sections: [CounterSection], counters visible: [Counter]) -> [CounterHomeSection]`: keeps section order, row order from `section.counters`, skips ids missing from `visible`, drops sections left empty.

- [ ] **Step 1: Write failing tests.** `CounterDecodingTests`: a file with `sections` decodes them; one without gives `[]`. `CountersStoreTests`: with a cached file lacking sections, `store.sections` has one entry per group with that group's title and member ids; with sections present they win. `CounterHomeTests`: (a) a counter in two sections yields two rows with different `id`s; (b) a hidden counter's row is skipped; (c) a section with every counter hidden is dropped; (d) a single-counter section has `canCompare == false`; (e) an empty visible list gives `[]`.
- [ ] **Step 2: Run** `cd Packages/VerbKit && swift test --filter "CounterDecoding|CountersStore|CounterHome"`; expect failures (types undefined).
- [ ] **Step 3: Implement** the types and `homeSections`; extend `CountersDataFile` coding keys and `apply(_:)` in the store.
- [ ] **Step 4: Run** the same command; expect PASS.
- [ ] **Step 5: Commit** `"VerbKit: counter sections and the home list model"`.

### Task 3: Sound patterns table and pitfall hint models

**Files:**
- Modify: `Packages/VerbKit/Sources/VerbKit/Models/SoundPatterns.swift` (keep `soundPatternRows` and `soundPatternStem`; add the table)
- Create: `Packages/VerbKit/Sources/VerbKit/Models/PitfallHint.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/SoundPatternsTests.swift`, new `PitfallHintTests.swift`

**Interfaces:**
- Produces:
  - `public enum SoundColumnID: String, CaseIterable, Sendable { case k, s, h, other }` with `title` (か行, さ行, は行, "other") and `examples` shown under the header taken from its counters
  - `public struct SoundPatternColumn: Identifiable, Sendable { id: SoundColumnID; counters: [Counter]; sample: Counter }`
  - `public struct SoundPatternTable: Sendable { columns: [SoundPatternColumn]; numbers: [CounterNumber]; irregular: [Counter]; exceptions: [SoundPatternException]; func cell(_ number: CounterNumber, _ column: SoundColumnID) -> (reading: String, changed: Bool)?; func sentence(for number: CounterNumber) -> String }`
  - `public func soundPatternTable(from counters: [Counter]) -> SoundPatternTable`
  - `public func pitfallHint(_ pitfall: CounterPitfall) -> (heading: String, firstSentence: String)`

- [ ] **Step 1: Write failing tests.** `SoundPatternsTests` (using the file's `counter(_:sound:changed:six:one:)` helper, extended with `three`): `numbers` is exactly `[.n(1), .n(3), .n(6), .n(8), .n(10)]`; columns map `k`→k, `s`→s, `h-b` and `h-p`→h, `plain`→other, and `irregular` counters go to `irregular` only; the sample is the preferred counter id (`ko`, `satsu`, `hon`, `mai`) when present and visible, else the column's first counter; empty columns are omitted; `cell` returns the sample's preferred reading and its `changed`; `sentence(for: .n(6))` is `"6 → ろっ in か行 and は行"` when か行 and は行 samples read ろっこ and ろっぽん and さ行 does not change; a number no column changes says `"6 never changes sound in these columns."`; a changing number with no shared っ stem says `"3 changes in は行"`; the は行 exception for a member that changes beyond the column (分 at 4) appears in `exceptions`. `PitfallHintTests`: heading is returned verbatim, `firstSentence` is the explanation up to and including the first 。 or ". " (and the whole text when there is none), and trailing whitespace is trimmed.
- [ ] **Step 2: Run** `swift test --filter "SoundPatterns|PitfallHint"`; expect failures.
- [ ] **Step 3: Implement.** Reuse the intersection and exception rules in `soundPatternRows` by computing them per column, and reuse `soundPatternStem` for the shared stem; do not duplicate that logic. The sentence uses only data (`isChanged`, readings), never a hard-coded kana.
- [ ] **Step 4: Run** the same command plus the old pattern tests; expect PASS.
- [ ] **Step 5: Commit** `"VerbKit: sound pattern table and pitfall hint"`.

### Task 4: Home directory with always-visible search

**Files:**
- Modify: `App/Counters/CountersHomeView.swift`, `App/Counters/CountersTab.swift` (`CounterDestination`, `CounterDestinationView`)
- Modify: `App/Counters/CounterListView.swift` (keep `CounterRow` for search results; delete `CounterListView`)
- Delete: `App/Counters/GroupTile.swift`
- Modify: `App/InlineSearch.swift` only if it cannot show the field permanently (see Step 2)

**Interfaces:**
- Consumes: `homeSections`, `CountersStore.sections` (Task 2), `soundPatternTable` (Task 3, for Task 7).
- Produces: `CounterDestination` gains `.section(CounterSection)` and loses `.all`; keeps `.group`, `.counter(Counter, focus:)`, `.patterns`. A section destination opens the compare table (Task 5).

- [ ] **Step 1: Replace the grid** in `CountersHomeView` with a `List` of `CounterHomeSection`s: header title plus a "Compare ›" button when `canCompare` (opens `.section`), rows built from a new `DirectoryRow` view (kanji, reading, meaning, an "irregular" tag when `counter.sound == "irregular"`, chevron; about 50 pt). Row identity is `CounterHomeRow.id`. A last row "Why counters change sound" opens `.patterns`. Empty store, empty search and hidden-level behaviour stay as they are.
- [ ] **Step 2: Make search always visible.** Check how `inlineSearch(text:prompt:focused:)` places the field; if it hides under the title, pin it above the list (visible at launch, no pull-down). Typing still swaps the list for `CounterSearchResultsView`; clearing restores the list.
- [ ] **Step 3: Update `CounterDestination` and its view** (add `.section`, remove `.all`); the group destination keeps using the group table.
- [ ] **Step 4: Build** `xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination 'id=<iPhone 17 UDID>' build`; expect BUILD SUCCEEDED.
- [ ] **Step 5: Verify in the simulator:** search field visible at launch; five sections in the order in Task 1; tapping the second 本 (under Things) opens 本; hiding N5 in Settings shows the empty state without a crash; typing "umbrella" and "3本" still gives results; screenshot against the baseline.
- [ ] **Step 6: Commit** `"Counters: directory home with always-visible search"`.

### Task 5: Compare table: tighter rows and an irregular badge

**Files:**
- Modify: `App/Counters/GroupTableView.swift`, `App/Counters/ReadingCell.swift`
- Modify: `App/Counters/CountersTab.swift` (the `.section` destination)

**Interfaces:**
- Consumes: `CounterDestination.section` (Task 4).
- Produces: `GroupTableView(title: String, summary: String?, rows: [(counter: Counter, note: String?)])`. A group passes its title, summary and member notes; a section passes its title, `nil` summary and `nil` notes, so headers show `counter.meaning` when `note` is `nil`.

- [ ] **Step 1: Refactor** `GroupTableView` to the initializer above and update its two call sites (`.group`, `.section`).
- [ ] **Step 2: Tighten rows** from 64 to about 40 pt (`@ScaledMetric`), moving the written form (一杯) to a smaller inline or trailing position in `ReadingCell` so the reading stays large; the table fits 1 to 10 and 何 on one iPhone screen at the default text size with the tab bar not covering the last row (add bottom content margin if needed).
- [ ] **Step 3: Add the irregular badge** to the column header for `counter.sound == "irregular"` ("irregular"); keep the footnote.
- [ ] **Step 4: Build** (as in Task 4) and **verify** a three-column section (Drinks), a six-column section (Time, dates & age, sideways scroll with the number column pinned), and the largest text size (rows grow, nothing truncates); long-press Copy still works on a cell; screenshots.
- [ ] **Step 5: Commit** `"Counters: compact compare table with irregular badges"`.

### Task 6: Counter page: reading block, number strip, segments

**Files:**
- Modify: `App/Counters/CounterDetailView.swift`
- Create: `App/Counters/NumberStrip.swift`, `App/Counters/ReadingBlock.swift`
- Delete: `App/Counters/CountThemCard.swift`, `App/Counters/ReadingsGrid.swift` (reuse their tint, dot and speech patterns)
- Modify: `App/Counters/ThingChips.swift` only if it relied on `CountThemCard`

**Interfaces:**
- Consumes: `pitfallHint` (Task 3), `CountersStore.sections` (Task 2).
- Produces: `NumberStrip(counter: Counter, selection: Binding<CounterNumber>)` (eleven cells in one row for regular counters; for `sound == "irregular"` an 11-cell grid); `ReadingBlock(counter: Counter, number: CounterNumber)` (large reading, written form above, tint and dot, tap to speak).

- [ ] **Step 1: Build `ReadingBlock` and `NumberStrip`**, porting the tint, dot, accessibility labels ("sound changes") and `speakOnTap`/`textActions` from `ReadingCell` and `CountThemCard`. The strip wraps or scrolls at accessibility sizes. A caption states what orange means.
- [ ] **Step 2: Rebuild `CounterDetailView`** top to bottom: header (counter, reading, speaker, level, meaning, small links to the sections containing the counter, via `store.sections`, no symbol); pitfall hint (first pitfall's heading and first sentence, "More" expands all pitfalls with their examples; omitted without pitfalls); `ReadingBlock`; `NumberStrip`; a segmented control with Examples (default), Things (the existing `ThingChips`) and Related, omitting a segment that has no content; Practise button below the content when `buildCounterQuestions(for:count:)` is non-empty. `focus` from a Forms search result initialises the selected number.
- [ ] **Step 3: Build** and **verify** on 本 (pattern strip, hint expands, segments switch, Practise starts the quiz), 人 (grid, no strip), a counter with no pitfalls (no hint), a Forms result for 3本 (lands with 3 selected), VoiceOver reads a tinted cell as "sound changes", largest text size, Reduce Motion; the page for 本 fits about one and a half screens.
- [ ] **Step 4: Commit** `"Counters: one-screen counter page with number strip"`.

### Task 7: Sound patterns screen

**Files:**
- Modify: `App/Counters/SoundPatternsView.swift` (rewrite)

**Interfaces:**
- Consumes: `soundPatternTable(from:)`, `SoundPatternTable.sentence(for:)`, `.cell`, `.exceptions`, `.irregular` (Task 3).

- [ ] **Step 1: Rewrite the view:** the table (rows 1, 3, 6, 8, 10; columns from the table model; tint, dot and ring as elsewhere; each cell speaks on tap), a selection state defaulting to 6, the sentence under the table with chips for the affected counters (each opens that counter's page), tapping a column header lists its counters, then the exceptions box (exceptions plus "人, つ, 時, 日: learn each reading" built from `irregular`). Empty store or all hidden keeps the existing "No Counters" empty state.
- [ ] **Step 2: Build** and **verify:** the table, selecting each number row, the exceptions text (年 and 円 at 4, 階 at 3, 分 at 4), chips navigate, hiding N5 shows the empty state, largest text size scrolls instead of truncating; screenshots.
- [ ] **Step 3: Commit** `"Counters: sound patterns by number and first sound"`.

### Task 8: Docs, full test run, final check

**Files:**
- Modify: `docs/superpowers/specs/2026-10-23-counters-lookup-redesign-design.md` (add an "As built" section)
- Modify: `docs/superpowers/specs/2026-10-17-counters-design.md` (one line pointing to the redesign)

- [ ] **Step 1: Run** `make test` (Python and Swift) and the iOS build; expect all PASS and BUILD SUCCEEDED. Fix failures from deleted views or renamed destinations (search the repo for `.all`, `GroupTile`, `CountThemCard`, `ReadingsGrid`).
- [ ] **Step 2: Check routes:** `verbtable://counter/<id>` and the group URL still open the right pages (simulator `open_url`), and the Counter of the Day widget link still lands on a counter.
- [ ] **Step 3: Write "As built"** in the redesign spec: what differed from the design, what was checked (listing the Task 4 to 7 simulator checks and VoiceOver, Reduce Motion, largest text) and what was not (iPad, macOS, Android, watchOS).
- [ ] **Step 4: Commit** `"Counters redesign: docs and as-built notes"`.

---

## Self-review notes

- **Coverage:** home (Task 4), sections data (1, 2), compare table (5), counter page (6), Sound patterns (3, 7), deep links and routes (8), accessibility (5, 6, 7, 8). The spec's "3 and 4" sentence wording is deliberately derived from data only ("3 changes in は行"); a richer explanation needs an authored field, which would be a new data change the owner signs, so it is out of this plan.
- **Names are consistent across tasks:** `CounterSection`, `CounterHomeRow`, `CounterHomeSection`, `homeSections`, `SoundPatternTable`, `soundPatternTable`, `pitfallHint`, `NumberStrip`, `ReadingBlock`, `GroupTableView(title:summary:rows:)`.
- **Left to the implementer:** exact spacing, symbols and copy for the "irregular" badge and the "Compare ›" control; whether the thing picker survives (this plan drops it with `CountThemCard`).
