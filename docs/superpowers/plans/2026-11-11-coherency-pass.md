# Coherency pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every screen read as the same paper-and-ink app: large titles with the motif on all tabs, ink sound marks, the five boards no plan covered, and paper surfaces on the ~30 secondary screens that still use the system style.

**Architecture:**
- **VerbKit** gains three small tested helpers: the Counters "Start here" list, where a counted number sits in an example, and Word Bank tag counts.
- **App** gains two shared pieces:
  - `SoundChangeMark`, the ink mark for a changed reading;
  - `PaperEmptyState`.
- Each screen then adopts the shared pieces (`motifTitle`, `paperCard`, `FilterChip`, `PaperButtonStyle`, `\.palette`) instead of glass and `.secondary`.
- **Widgets** get Mincho and the board's layouts, inside the widget target's own files.

**Tech Stack:** SwiftUI (iOS 26 / macOS 26), VerbKit (Foundation only), XCTest, WidgetKit.

**Spec:** `docs/superpowers/specs/2026-11-06-paper-ink-redesign-design.md`: the section "Coherency pass" and row 8 of "Boards → plans". Boards on https://claude.ai/artifact/7eCLPFjJnWRoGB2n85ocr2:
- "Proposed: counters home" (`project/CountersHome.dc.html`)
- "Proposed: counter" (`project/CounterDetail.dc.html`)
- "Proposed: Word Bank" (`project/WordBank.dc.html`)
- "Proposed: empty states" (`project/EmptyState.dc.html`)
- "Proposed: home-screen widgets" (`project/Widgets.dc.html`)

## Global Constraints

- Rules 1–10 of the spec apply:
  - glass only on chrome;
  - red only for mistakes and destructive actions;
  - ink is the one strong colour;
  - furigana on every kanji through `JapaneseText`;
  - Mincho (`Font.headword`/`Font.sentence`) for Japanese headwords and sentences;
  - nothing relies on colour alone.
- A changed counter reading is **bold with a 2 pt `ink` underline**. No orange anywhere for sound changes.
- Every tab root with a list uses `motifTitle`. No Japanese name beside a title.
- Text colours come from `\.palette` (`ink`, `muted`), never `.secondary`, `.orange` or `.green`, in every file this plan touches.
- VerbKit stays UI-free. Wording lives in App. Never edit `.xcodeproj`; run `make project` after adding files.
- Widgets compile only `Widgets/**` plus the three named App files. Any font or helper they need goes in `Widgets/`.
- Don't touch `data/`.

## Review Focus

1. **Search on Grammar and Counters after unpinning.**
   - Pulling down reveals the field.
   - A typed query and its results survive scrolling.
   - Opening the tab with a query still shows results.
   - Test: on the simulator, type in both tabs and scroll.
2. **Sound marks where readings are small:** the counter widget (8–11 pt), the 3-column irregular grid, and AX5. The underline must not clip or touch the next row.
   - Test: `SoundChangeMark` uses an overlay line offset below the baseline; checked on the simulator at default size and AX5 for 本 and 人.
3. **Counted-number highlight in examples:**
   - numbers written with digits (3本), kanji (三本) or kana (さんぼん);
   - the counter appearing twice;
   - a counter whose written form is also an ordinary word (つ, 人).
   - Test: `CounterHighlightTests` in Task 1.
4. **Tag chips with many or no tags:**
   - Show at most 6 chips after All.
   - Hide the row with no tags.
   - The selected chip stays visible after its tag is deleted.
   - Test: `testTagCounts…` in Task 1, plus the App fallback to All.
5. **Empty states in dark halves and at AX5:** the faint 空 uses `rule`, the buttons stack at accessibility sizes.
   - Test: the `PaperEmptyState` layout switches on `dynamicTypeSize.isAccessibilitySize`; checked on the simulator.

---

### Task 1: VerbKit helpers

**Files:**
- Modify: `Packages/VerbKit/Sources/VerbKit/Models/CounterHome.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Models/CounterHighlight.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/WordBank/WordBankTagCounts.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/CoherencyPassTests.swift`

**Interfaces:**
- Produces:
  - `public enum CounterHome { public static let startHereIDs: [String]; public static func startHere(_ counters: [Counter]) -> [Counter] }`
    - The IDs are the bundled data's ids for つ, 人, 本, 枚, 個, 匹, 台, 冊 and 杯, in that order. Look them up in `data/counters.json`; don't change the data.
    - `startHere` returns those found among `counters`, in order, so hidden levels drop tiles.
  - `public enum CounterHighlight { public static func range(in sentence: String, counter: Counter) -> Range<Int>? }`
    - Returns a character range over the first counted number: a run of digits, kanji numerals (一二三四五六七八九十百千何) or one of the counter's kana readings for 1–10 and 何, joined to the counter (`written`/readings).
    - Returns nil when nothing matches.
  - `public struct WordBankTagCount: Equatable, Sendable { public let tagID: String; public let count: Int }`
  - `public enum WordBankTagCounts { public static func top(_ entries: [WordBankEntryValue], limit: Int) -> [WordBankTagCount] }`
    - Counts dialect and custom tag ids.
    - Sorts by count descending, then by tag id.
    - Returns at most `limit` items.

- [ ] **Step 1: Write the failing tests**

```swift
func testStartHereFollowsTheBoardAndDropsHiddenCounters() {
    let all = BundledData<CounterDataFile>.load(named: "counters")!.value.counters
    XCTAssertEqual(CounterHome.startHere(all).map(\.counter), ["つ", "人", "本", "枚", "個", "匹", "台", "冊", "杯"])
    XCTAssertEqual(CounterHome.startHere(all.filter { $0.counter != "本" }).count, 8)
}
func testCounterHighlightFindsDigitsKanjiAndKana() {
    let hon = counter("本")   // from bundled data
    XCTAssertEqual(CounterHighlight.range(in: "ビールを二本ください。", counter: hon), 4..<6)
    XCTAssertEqual(CounterHighlight.range(in: "ペンが3本あります。", counter: hon), 3..<5)
    XCTAssertEqual(CounterHighlight.range(in: "さんぼんください。", counter: hon), 0..<4)
    XCTAssertNil(CounterHighlight.range(in: "本を読みます。", counter: hon))   // 本 alone is a book, not a count
}
func testCounterHighlightTakesTheFirstOfTwo() {
    XCTAssertEqual(CounterHighlight.range(in: "一本と二本", counter: counter("本")), 0..<2)
}
func testTagCountsAreSortedAndLimited() {
    // entries tagged a×3, b×2, c×2, d×1 → [a 3, b 2, c 2] with limit 3; [] for untagged entries.
}
```

- [ ] **Step 2:** Run `make test-swift`. Expected: it fails to compile because the three symbols are missing.
- [ ] **Step 3:** Implement the three helpers. The ranges count `Character`s, as `GrammarHighlight` does.
- [ ] **Step 4:** Run `make test-swift`. Expected: all tests pass.
- [ ] **Step 5:** Commit: "VerbKit: counter start list, counted-number highlight, tag counts".

### Task 2: Shared pieces: titles, sound marks, empty state

**Files:**
- Create: `App/UI/SoundChangeMark.swift`. It holds `func soundChangeMark(_ changed: Bool) -> some View`:
  - when true: semibold, plus a 2 pt `palette.ink` line 2 pt under the text's bottom (overlay, `.bottom` alignment, offset);
  - when false: identity.
- Create: `App/UI/PaperEmptyState.swift`. It holds `struct PaperEmptyState<Actions: View>: View`, `init(_ title: String, message: String, glyph: String = "空", @ViewBuilder actions: () -> Actions)`:
  - the glyph in `Font.headword(.largeTitle, scale: 1.6)` coloured `palette.rule`, with furigana through `JapaneseText`;
  - the title in `.title3.weight(.semibold)` `ink`, and the message in `.subheadline` `muted`;
  - the actions in an HStack, or a VStack at accessibility sizes;
  - everything inside `paperCard(cornerRadius: 16, ruled: true)`;
  - an `init(_:message:glyph:)` without actions (an `EmptyView` extension).
- Modify: `App/GrammarListView.swift` and `App/Counters/CountersHomeView.swift`:
  - replace `.navigationTitle(...)` with `.motifTitle(...)`;
  - set `alwaysVisible: false` on `inlineSearch` (drop the parameter);
  - update `InlineSearch.swift`'s doc comment;
  - remove `alwaysVisible` if no caller is left.
- Modify: `App/Counters/NumberStrip.swift`, `ReadingBlock.swift`, `ReadingCell.swift`, `GroupTableView.swift`, `SoundPatternsView.swift`:
  - replace the orange fill and dot with `soundChangeMark(changed)` on the reading text;
  - NumberStrip's caption becomes "Underlined numbers change sound: …".
- Replace `ContentUnavailableView` with `PaperEmptyState` in every file listed by `grep -rl ContentUnavailableView App`. Keep each existing title and message. Add the board's two actions to the Word Bank's empty state: "Add a word" (`.paper`) and "Import…" (`.paperSecondary`). Search results keep `NoMatchInLevelsView`.

- [ ] **Step 1:** Implement the two components, then adopt them in the files above.
- [ ] **Step 2:** Run `grep -rn "orange\|ContentUnavailableView" App/Counters App/GrammarListView.swift App/WordBank App/VerbListView.swift`. Expected: no matches. Then build iOS and macOS. Expected: no errors.
- [ ] **Step 3:** Check on the simulator:
  - Grammar and Counters show a large title with the motif in Light and Northern lights dark; pulling down reveals search, and search still works (Review Focus 1);
  - 本's strip and block in ink, at default size and AX5 (Review Focus 2);
  - an empty Word Bank folder.
- [ ] **Step 4:** Commit: "Coherency: motif titles on every tab, ink sound marks, paper empty states".

### Task 3: Counters home and counter page

**Files:**
- Modify: `App/Counters/CountersHomeView.swift`.
  - Above the topics, when there's no search, add "Start here": `SectionHeader("Start here")` and a `LazyVGrid` of 3 flexible columns with a `CounterTile` for each of `CounterHome.startHere(counters(in: settings))`.
    - `CounterTile` is a 96 pt `paperCard`: the counter in `Font.headword(.title)` through `JapaneseText`, the meaning in `.caption` `muted`, centred, opening `.counter`.
    - At accessibility sizes there's 1 column.
  - The topics stay as now (Compare, rows), but each topic's rows sit on a `paperCard` instead of plain list rows. Use `paperBackground` on the List, `paperRow()` on the rows, and topic headers as `SectionHeader` with Compare as `.paperSecondaryInline`.
- Modify: `App/Counters/DirectoryRow.swift`:
  - the counter in `Font.headword(.title2)` through `JapaneseText`;
  - reading and meaning in `palette.muted` / `ink`;
  - "irregular" as an outlined capsule (1 pt `ink`, `.caption2.weight(.semibold)`), not glass.
- Modify: `App/Counters/CounterDetailView.swift`:
  - The header counter is in `Font.headword(.largeTitle, scale: 1.4)` and the meaning in `ink`.
  - Topic buttons and related counters use `.paperSecondaryInline` and `FilterChip` styles instead of `.glass`.
  - The segmented `Picker` becomes a `FilterChip` row (`isOn: shown == segment`).
  - The examples card is `paperCard(ruled: true)`, and `CounterExampleRow` underlines `CounterHighlight.range` through `JapaneseText(_:emphasizing:)`. `ExampleRow` gets an optional `emphasis: Range<Int>?`.
  - Practise uses `.paper`.
  - `NumberStepper`'s ±1/±10 buttons use `.paperSecondary` capsules.
  - `ThingChips` uses `TagPill`-style outlined capsules with `palette` colours.
  - `ReviewStatusPill`'s orange and green become `palette.mark` (not reviewed, with a question glyph) and `palette.good`.
  - `UnreviewedLabel` uses `palette.muted`.

- [ ] **Step 1:** Implement.
- [ ] **Step 2:** Run `grep -rn "glass\|\.secondary\|orange" App/Counters App/ReviewStatusPill.swift`. Expected: no matches. Build iOS. Expected: no errors.
- [ ] **Step 3:** Check on the simulator: the Counters home tiles and topic cards, and the 本 and つ pages, in Light and a dark half.
- [ ] **Step 4:** Commit: "Coherency: Counters home and counter page in paper and ink".

### Task 4: Word Bank list

**Files:**
- Modify: `App/WordBank/WordBankRow.swift`:
  - First line: `JapaneseText(entry.text)` in `Font.headword(.title3)`, with the first meaning beside it in `.subheadline` `muted`, not italic, wrapping below at accessibility sizes.
  - Second line: up to three `TagPill`s, then "= " and the first standard form via `JapaneseText`, in `.caption` `muted`.
  - Folder path and match explanation stay, in `muted`.
- Modify: `App/WordBank/WordBankListView.swift`:
  - The list rows sit on one `paperCard` (`paperBackground` and `paperRow()`), and the hub rows (All entries, Unfiled, Recently added, Folders) also use `paperRow()`.
  - On a place that lists entries, add a horizontal row of `FilterChip`s above the rows: "All N", then `WordBankTagCounts.top(entries, limit: 6)` as "<tag name> N".
    - Selecting one filters the rows to that tag; All clears it.
    - The selection is `@State` and resets to All when its tag disappears.
    - The row is hidden when there are no tags.
- Modify: `App/WordBank/WordBankSearchSupport.swift`: `.secondary` becomes `palette.muted`.

- [ ] **Step 1:** Implement.
- [ ] **Step 2:** Build iOS. Expected: no errors. Check on the simulator: All entries with the imported めっちゃ entry, a tag chip filtering, Light and a dark half, AX5.
- [ ] **Step 3:** Commit: "Coherency: Word Bank list rows and tag chips".

### Task 5: Widgets

**Files:**
- Create: `Widgets/WidgetFonts.swift`. It holds `extension Font { static func widgetHeadword(_ size: CGFloat) -> Font; static func widgetSentence(_ size: CGFloat) -> Font }`, using `HiraMinProN-W6` and `HiraMinProN-W3`.
- Create: `Widgets/WidgetRuby.swift`. It holds `struct WidgetRuby: View`, `init(_ text: String, reading: String?, size: CGFloat)`, which draws the reading in `muted` at 0.4× above the text. JapaneseText isn't available in the widget target.
- Modify: `Widgets/VerbWidgetViews.swift`:
  - the caption "VERB OF THE DAY" (`.caption2.weight(.semibold)`, tracking, `muted`);
  - the headword in `WidgetRuby`;
  - the meaning, then the type dot (`VerbColors`) with "Ru-verb · N5".
  - The medium size keeps its forms grid in paper tokens.
- Modify: `Widgets/CounterWidgetViews.swift`:
  - the background is `palette.ink` and the text `palette.paper`, with "COUNTER" in `muted` mixed toward paper;
  - the counter in `WidgetRuby`, then the meaning, then two example readings;
  - changed readings in the strip get the bold ink-style underline in `paper`;
  - drop `Self.accent`.
- Modify: `Widgets/GrammarWidgetViews.swift`:
  - "GRAMMAR" plus the level pill;
  - the title in `widgetHeadword`;
  - the example in `widgetSentence`, with the pattern underlined using `GrammarHighlight.range(in:patterns: GrammarHighlight.patterns(of:))`, then its English in `muted`;
  - the ruled background as in `paperCard(ruled:)`, re-drawn locally (`Widgets/WidgetRuled.swift`) since App UI isn't in the target.
- Clear and Tinted: `WidgetTheme.plain` already drops the paper; check that the ruled grid and ink background are dropped too.

- [ ] **Step 1:** Implement. Run `make check-project`, then build iOS. Expected: no errors.
- [ ] **Step 2:** Check on the simulator: add each widget to the Home Screen (small and medium) in Light and a dark half.
- [ ] **Step 3:** Commit: "Coherency: widgets in Mincho, ink counter, ruled grammar".

### Task 6: Paper on the remaining screens

**Files:** every file this command lists that Tasks 2–5 left:

```bash
for f in $(grep -rl "\.secondary\|glassEffect\|\.glass)\|List {\|Form {" App); do grep -q "palette\|paper" "$f" || echo "$f"; done
```

The list from the 2026-11-11 audit:
- the Counters list, quiz, sheet and search results;
- `DataSyncSection`, `ExampleRow` and `LevelSearch`;
- FormLookup (`FormLookupSheet`, `VerbSpanCard`);
- Grammar: `BuildingBlocksView`, `CommonMistakesView`, `MyCourseView`, `ParticleQuizView` and `SpotMistakeQuizView`;
- `QuizProgressView`, `QuizTopicSheet`, `ReviewStatusPill` and `VerbGuideSheet`;
- Word Bank: `FolderActions`, `NewDialectTagSheet`, `TagManagerView`, `WordBankBackupsView`, `WordBankExportSheet`, `WordBankImportSheet`, `TagPicker` and `FolderPicker`.

The rule for each:
- `List`/`Form` gets `paperBackground()` and its rows `paperRow()`;
- `.secondary` becomes `palette.muted`;
- `.glass` buttons in content become `.paper`, `.paperSecondary` or `.paperSecondaryInline`, by emphasis;
- selectable capsules become `FilterChip`;
- `.orange`/`.green` status colours become `palette.mark`/`palette.good`, with a glyph;
- Japanese headwords use `Font.headword` and sentences `Font.sentence` through `JapaneseText`.
- Quiz chrome glass in `QuizChrome.swift` stays (chrome).

- [ ] **Step 1:** Implement, one area at a time (Counters, Grammar, quiz and lookup, Word Bank, Settings and the rest), building iOS after each.
- [ ] **Step 2:** Rerun the command above. Expected: it prints only `App/VerbColors.swift`, the glass `accentPill` that `TypeLabel` owns. Build iOS and macOS. Expected: no errors.
- [ ] **Step 3:** Check on the simulator: Building blocks, Common mistakes, the quiz topic sheet, Progress, "What form is this?", Word Bank import and tags, and Settings, in Light and Northern lights dark.
- [ ] **Step 4:** Update AGENTS.md:
  - add `SoundChangeMark`, `PaperEmptyState`, `CounterHome`, `CounterHighlight` and `WordBankTagCounts` to the tables;
  - change `QuizScoreCard`'s row to "the theme half's stamp";
  - add a Traps line: "Use `PaperEmptyState`, not `ContentUnavailableView`".
- [ ] **Step 5:** Mark spec row 8 "(built)". Commit: "Coherency: paper on the remaining screens".
