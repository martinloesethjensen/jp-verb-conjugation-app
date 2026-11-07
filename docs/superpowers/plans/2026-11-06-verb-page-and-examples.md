# Verb Page and Examples Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the verb page, its sub-pages and the quiz results the paper-and-ink look from the canvas: a Mincho headword with furigana, an ink "Test this verb" button, sectioned form tables, example sentences on ruled genkō paper with the verb underlined, a "How it's made" card on Potential, and a red teacher's stamp around the quiz score.

**Architecture:** The rules that can be tested go in VerbKit:
- spelling a kana form with the verb's kanji, as ruby units;
- finding a form inside an example sentence;
- marking emphasised characters in furigana units;
- the potential pattern;
- pairing missed questions with their results.

Everything drawn goes in `App/`:
- new shared pieces: `PaperButtonStyle`, `paperCard(ruled:)`, a `SectionHeader` with a trailing view, `JapaneseText(_:emphasizing:)`, `VerbExampleRow`, `VerbSubPageHeader` and `QuizScoreCard`;
- the existing screens, rebuilt from those pieces.

**Tech Stack:** Swift 6, SwiftUI (iOS 26 / macOS 26), XCTest in `Packages/VerbKit`, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-11-06-paper-ink-redesign-design.md`, rules 1–9 and the "Boards → plans" row for plan 2. Canvas boards: "Verb page, full length", "Verb sub-page: potential", "Proposed: quiz results". Local copies are in the session scratchpad as `canvas/project/VerbFull.dc.html`, `VerbPotential.dc.html` and `QuizResults.dc.html`.

## Global Constraints

- **Branch:** `claude/verb-page-redesign`, from `origin/main`. Plan 1 is already merged there.
- **Colours:** only `\.palette` tokens in the views this plan touches. No `.secondary`, `.primary`, `.green`, `.orange`, `.red` or `.tint(accent)`. Text uses `ink` or `muted`; `mark` and `good` only for quiz marks, which are text on `card` (≥ 4.5:1 in every palette).
- **Glass:** Liquid Glass stays on chrome only. Remove it from every content surface this plan touches: the `glassProminent` Test button, `.glass` lesson links, results glass, and `QuizMissedCard`.
- **Furigana:** all Japanese goes through `JapaneseText`. Verb forms in tables stay kana (spec rule 5).
- **Fonts:**
  - Headwords: `Font.headword` (HiraMinProN-W6).
  - Example sentences and common phrases: `Font.sentence` (HiraMinProN-W3), added in Task 1.
  - Form tables: the system font.
  - Every size scales with Dynamic Type through `relativeTo:`.
- **VerbKit:** stays UI-free. User-facing strings (section titles, the "How it's made" explanations, results copy) live in `App/`.
- **No change under `data/`.**
- **No new widget dependencies.** None of the new App files is needed by the widget target, so `project.yml` doesn't change.
- **AGENTS.md:** each task adds its new shared symbols to the AGENTS.md tables in the same commit.
- **Tests:** `make test-swift` (VerbKit only; there is no App test target).
- **iOS build:** `make project && xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination 'generic/platform=iOS Simulator' build -quiet`.
- **macOS build:** the same with `-scheme JPVerbConjugation_macOS -destination 'generic/platform=macOS'`. Its Info.plist error, `LSSupportsOpeningDocumentsInPlace`, already exists on `main`, so the check is "no Swift errors" (`grep -E 'error:' | grep -v Info.plist` is empty).
- **Simulator checks:** iPhone 18 Pro. Open pages with `xcrun simctl openurl <udid> verbtable://verb/<id>`. Set the theme by writing the App Group defaults through `xcrun simctl spawn … defaults write`.

## Review Focus

- **A long meaning beside a big headword.** For example 着る "to put on (clothes on the upper body)", at the largest Dynamic Type size: the header must wrap the meaning under the headword, not clip or squeeze it. Covered by Task 2, step 4.
- **Example sentences with the form written in kana, or with 来る's changed stem.** The underline must still land on the verb (きます / こない / 来ない). Covered by `FormHighlightTests` and the real-data test (Task 4).
- **Furigana off.** With "Show furigana" off, the verb in an example must still be bold and underlined (the plain-`Text` path). Covered by Task 4, step 9.
- **An irregular verb on the Potential page.** For する verbs, 来る and ある, the "How it's made" card must say the right thing or not show at all. Covered by `PotentialPatternTests` (Task 5).
- **Results with nothing wrong, or everything timed out.** A perfect quiz shows no "Marked wrong" section. A timed-out row shows "Time's up" and no struck-through answer. Covered by `testMissedPairsQuestionsWithResults` (Task 6) and the Task 6 simulator check.

---

### Task 1: Shared paper pieces

**Files:**
- Create: `App/UI/PaperButtonStyle.swift`
- Modify: `App/UI/PaperSurface.swift` (add `ruled:` to `paperCard`)
- Modify: `App/UI/SectionHeader.swift`
- Modify: `App/UI/Typography.swift`
- Modify: `AGENTS.md`

**Interfaces:**
- Produces:
  - `struct PaperButtonStyle: ButtonStyle` with `enum Prominence { case primary, secondary }` and `init(_ prominence: Prominence = .primary)`, plus `extension ButtonStyle where Self == PaperButtonStyle { static var paper: Self; static var paperSecondary: Self }`.
  - `View.paperCard(cornerRadius: CGFloat = 12, fillsWidth: Bool = true, ruled: Bool = false)`.
  - `SectionHeader<Trailing: View>(_ title: String, systemImage: String? = nil, @ViewBuilder trailing: () -> Trailing)`, plus the existing `SectionHeader(_:systemImage:)` where `Trailing == EmptyView`.
  - `Font.headword(_ style: Font.TextStyle, scale: CGFloat = 1)` and `Font.sentence(_ style: Font.TextStyle)`.

- [ ] **Step 1: Implement `PaperButtonStyle`.**
  - Primary: `palette.button` fill and `palette.onButton` label.
  - Secondary: `palette.card` fill, a 1 pt `palette.rule` border (1.5 pt with Increase Contrast) and an `ink` label.
  - Both: a capsule, label font `.body.weight(.semibold)`, minimum height 50, `frame(maxWidth: .infinity)`, and opacity 0.7 while pressed. Disabled draws at opacity 0.4, read from `\.isEnabled`.
- [ ] **Step 2: Add `ruled:` to `PaperCard`.** When true, draw a genkō grid in the card background under the content, clipped to the card's rounded rectangle. Use a `Canvas` with lines every 28 pt both ways, stroked 1 pt in `palette.rule.opacity(0.6)`. Existing callers are unchanged.
- [ ] **Step 3: Make `SectionHeader` generic over a trailing view.**
  - Lay out an `HStack(alignment: .firstTextBaseline)`: the title (`.title3.weight(.semibold)`, ink), a `Spacer`, then the trailing view.
  - Trailing content is the caller's own; the verb page passes `Text(...).font(.footnote).foregroundStyle(palette.muted)` or a `Button`.
  - The icon stays optional, so existing callers compile unchanged.
- [ ] **Step 4: Add the two fonts.**
  - `headword(_:scale:)` multiplies the default size by `scale`.
  - `sentence(_:)` is `.custom("HiraMinProN-W3", size: defaultSize(of: style), relativeTo: style)`.
- [ ] **Step 5: Use `.paper` in `ThemePickerView`'s preview.** It replaces the hand-made capsule "Test this verb" there; that code duplicated what this style now does.
- [ ] **Step 6: Build iOS and macOS.**
  - Expected: iOS `** BUILD SUCCEEDED **` (quiet mode prints nothing and exits 0).
  - Expected: macOS shows no Swift `error:` lines.
- [ ] **Step 7: Update AGENTS.md and commit.**
  - AGENTS.md "App UI components": add `PaperButtonStyle` (`.paper` / `.paperSecondary`, for content buttons instead of glass), `paperCard(ruled:)` (genkō paper for example sentences and results), `SectionHeader` with a trailing view, and `Font.headword(_:scale:)` / `Font.sentence(_:)`.
  - Commit message: `Paper button style, ruled cards, section header trailing and sentence font`.

### Task 2: Verb page header, Test button and toolbar

**Files:**
- Modify: `App/VerbDetailView.swift`
- Modify: `App/RootView.swift:160-176` (the examples sheet stays, opened from the page body; see Task 4)

**Interfaces:**
- Consumes: `PaperButtonStyle` (`.paper`), `Font.headword(_:scale:)`, `TypeLabel(_:teGroup:emphasis:)`, `LevelBadge(level:emphasis:)`, `Verb.dictionaryUnits`.
- Produces: nothing new.

- [ ] **Step 1: Rebuild `header` as on the board.**
  - **Row 1:** `TypeLabel(verb.type, teGroup: verb.teGroup, emphasis: .header)` and `LevelBadge(level: verb.jlpt, emphasis: .header)`.
  - **Row 2:** `JapaneseText(units: verb.dictionaryUnits)` in `.headword(.largeTitle, scale: 1.5)`, ink, with `verb.meaning` in `.title3.weight(.semibold)`, ink, not italic.
    - Lay the row out with `ViewThatFits(in: .horizontal)`.
    - First, an `HStack(alignment: .lastTextBaseline)` with the meaning trailing.
    - Fallback, a `VStack(alignment: .leading)` with the meaning under the headword.
  - **Row 3:** `JapaneseText(verb.description)` in `.body`, ink. It moves here from the page body.
  - `.accessibilityElement(children: .combine)` on rows 1–2.
- [ ] **Step 2: Replace `actions`.**
  - `Button { onQuiz() } label: { Label("Test this verb", systemImage: "checkmark.circle") }`, styled `.buttonStyle(.paper)`.
  - Remove the `accent` property and the black foreground.
- [ ] **Step 3: Slim the toolbar to the board's three controls.**
  - `.primaryAction`: the favourite toggle and `SpeakButton`.
  - `.secondaryAction`: the Jisho `Link`, labelled "Open in Jisho", and `ReportProblemButton`. iOS draws these as the "More" menu.
  - Remove the toolbar "Examples" button; Task 4 adds "See all" in the page instead. Until then, nothing opens the examples sheet. Tasks 2 and 4 land together, so that's acceptable.
- [ ] **Step 4: Build iOS. Check on the simulator in Light and Nocturnal.**
  - Pages: `verbtable://verb/たべる` and the verb whose meaning is longest. Find it with `python3 -I -c "import json;v=json.load(open('data/verbs.json'));v=v['verbs'] if isinstance(v,dict) else v;print(max(v,key=lambda x:len(x['meaning']))['dict'])"`.
  - Then check the long-meaning verb at the largest accessibility text size: `xcrun simctl ui <udid> content_size accessibility-extra-extra-extra-large`, then reset it.
  - Expected: furigana た over 食. The meaning sits beside the headword for たべる and wraps under it for the long one. The button is an ink capsule with white text in Light and a light capsule with dark text in Nocturnal.
- [ ] **Step 5: Commit.** Message: `Verb page header: Mincho headword with furigana, level, ink Test button`.

### Task 3: Forms and More forms

**Files:**
- Modify: `App/FormTable.swift`, `App/FormCell.swift`, `App/MoreRowsCard.swift`, `App/VerbDetailView.swift` (the `formGroups` section headers)

**Interfaces:**
- Consumes: `SectionHeader(_:trailing:)`, `RowChevron`, `\.palette`.
- Produces: nothing new. `FormTable` keeps its signature, so the four sub-pages pick up the restyle.

- [ ] **Step 1: Restyle `FormTable`.**
  - Column headers: `.footnote.weight(.semibold)` in `muted`.
  - Row labels: `.footnote` in `muted`.
  - Dividers: `Divider().overlay(palette.rule)`.
  - Cell font: `.body`.
  - Row padding: 10 pt vertical, from `verticalSpacing: 10`.
- [ ] **Step 2: Restyle `FormCell`.** The stem is `palette.muted`, regular weight; the ending is `palette.ink`, bold.
- [ ] **Step 3: Restyle `MoreRowsCard` rows.**
  - Title in ink, preview in `muted`, `RowChevron`, `frame(minHeight: 48)` instead of the 10 pt padding, and rule-coloured dividers.
  - Keep the rows and their order: Potential, んです, Auxiliaries, Advanced, then lessons.
- [ ] **Step 4: Head the two groups in `VerbDetailView.formGroups`.**
  - `SectionHeader("Forms") { Text("Tap to hear · hold for more") … }` above `VerbFormsCard`.
  - `SectionHeader("More forms")` above `MoreRowsCard`, drawn only when the card has rows. To make that possible, move the `rows` computation to `static func rows(for verb: Verb, lessonCount: Int) -> [Row]`, and let `VerbDetailView` read `verbStore` for the lesson count.
- [ ] **Step 5: Build iOS, then check たべる and the Potential page in Light and Sand.** Expected: the table matches the board, with muted stems, bold ink endings and ruled rows. Long forms still wrap, not truncate.
- [ ] **Step 6: Commit.** Message: `Forms tables and More forms rows in paper and ink`.

### Task 4: Example sentences with the verb underlined

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Forms/FormHighlight.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Furigana/TextUnit+Emphasis.swift`
- Modify: `Packages/VerbKit/Sources/VerbKit/Furigana/TextUnit.swift` (add `isEmphasized`)
- Create: `Packages/VerbKit/Tests/VerbKitTests/FormHighlightTests.swift`
- Create: `Packages/VerbKit/Tests/VerbKitTests/TextUnitEmphasisTests.swift`
- Modify: `App/JapaneseText.swift`
- Create: `App/VerbExampleRow.swift`
- Modify: `App/ExamplesView.swift`, `App/VerbDetailView.swift`, `App/CommonPhrasesCard.swift`, `AGENTS.md`

**Interfaces:**
- Consumes: `KanjiSpelling(_ verb: Verb)` and `.spell(_:)`; `VerbForms[id:]`; `paperCard(ruled:)`; `Font.sentence`; `SectionHeader(_:trailing:)`.
- Produces:
  - `public enum FormHighlight { public static func range(of form: String, for verb: Verb, in sentence: String) -> Range<Int>? }`. Character offsets.
  - `TextUnit.isEmphasized: Bool`, default `false`, as a new trailing `init` parameter `isEmphasized: Bool = false`.
  - `public extension TextUnit { static func emphasizing(_ units: [TextUnit], characters: Range<Int>) -> [TextUnit] }`.
  - `JapaneseText(_ text: String, emphasizing: Range<Int>?)`.
  - `struct VerbExampleRow: View { let example: VerbExample; let verb: Verb }`, with `static func formLabel(_ id: FormID, catalogue: FormCatalogue) -> String` (moved from `ExamplesView`).

- [ ] **Step 1: Write the failing tests in `FormHighlightTests`.** Build verbs with the existing test helpers or `Verb(...)` initialisers, as `KanjiSpellingTests` does.

```swift
func testFindsKanjiSpelledForm() {      // 食べる, masu_pos たべます
    XCTAssertEqual(FormHighlight.range(of: "たべます", for: taberu, in: "朝ご飯を食べます。"), 4..<8)
}
func testFindsTeFormBeforeKara() {
    XCTAssertEqual(FormHighlight.range(of: "たべて", for: taberu, in: "食べてから、出かけます。"), 0..<3)
}
func testFindsKuruChangedStem() {       // 来る, short_neg こない
    XCTAssertEqual(FormHighlight.range(of: "こない", for: kuru, in: "彼は来ない。"), 2..<5)
}
func testFallsBackToKanaSpelling() {
    XCTAssertEqual(FormHighlight.range(of: "たべます", for: taberu, in: "なにをたべますか。"), 3..<7)
}
func testVerbWithoutKanjiUsesKana() {   // する
    XCTAssertEqual(FormHighlight.range(of: "します", for: suru, in: "宿題をします。"), 3..<6)
}
func testNilWhenAbsent() {
    XCTAssertNil(FormHighlight.range(of: "たべません", for: taberu, in: "朝ご飯を食べます。"))
}
func testEveryPublishedExampleContainsItsForm() throws {   // real data, as RealFormSplitTests loads it
    // For every verb and every example whose form exists, range(...) is non-nil (483 of 483 today).
}
```

- [ ] **Step 2: Write the failing tests in `TextUnitEmphasisTests`.**

```swift
func testSplitsPlainUnitAtBoundaries() {
    // Hand-built: [TextUnit(text: "あさごはんをたべます。")], characters 6..<10
    // → [あさごはんを] [たべます (emphasized, glueToPrevious)] [。 (glueToPrevious)]
}
func testEmphasizesWholeRubyUnitWhenPartlyCovered() {
    // [食(た), べてから] with characters 0..<3 → 食 emphasized whole, べて emphasized, から plain
}
func testEmptyRangeLeavesUnitsUnchanged() {
    XCTAssertEqual(TextUnit.emphasizing(units, characters: 2..<2), units)
}
func testRangePastEndIsClamped() {
    // characters 3..<99 on a 5-character text emphasizes characters 3..<5 only
}
```

- [ ] **Step 3: Run the tests and confirm they fail.**
  - Run: `cd Packages/VerbKit && swift test --filter 'FormHighlightTests|TextUnitEmphasisTests'`
  - Expected: a compile failure, because `FormHighlight`, `isEmphasized` and `emphasizing` don't exist yet.
- [ ] **Step 4: Implement `FormHighlight.range`.**
  - Try candidates in order: `KanjiSpelling(verb)?.spell(form)`, then `form`.
  - Return the first candidate found in `sentence`, converted to character offsets.
- [ ] **Step 5: Implement `TextUnit.isEmphasized` and `emphasizing`.**
  - Walk the units with a running character offset.
  - A unit wholly inside the range is emphasised.
  - A unit with a reading that the range partly covers is emphasised whole.
  - A plain unit the range partly covers splits into up to three units at the range's edges. The pieces after the first take `glueToPrevious: true`, so they never wrap apart.
  - Clamp the range to the text.
- [ ] **Step 6: Run the tests and confirm they pass.**
  - Run: `cd Packages/VerbKit && swift test --filter 'FormHighlightTests|TextUnitEmphasisTests'`. Expected: all pass.
  - Then `make test-swift`. Expected: all pass, 1263 plus the new tests.
- [ ] **Step 7: Add `JapaneseText(_ text: String, emphasizing: Range<Int>?)`.**
  - **Ruby path:** run the units through `TextUnit.emphasizing`. `UnitView` draws an emphasised unit `.bold()`, with the base text underlined `underline(true, color: palette.ink)`; the reading isn't underlined.
  - **Plain path** (furigana off, or no readings): concatenate `Text` pieces with the middle piece `.bold().underline(color: palette.ink)`.
  - `nil` behaves exactly like `init(_:)`.
- [ ] **Step 8: Build `VerbExampleRow`, then use it on the verb page and in the sheet.**
  - **The row:**
    - The form tag is the catalogue label in a capsule: `.caption2.weight(.semibold)`, `muted` text, with a 1 pt `rule` outline.
    - The sentence is `JapaneseText(example.jp, emphasizing: verb.forms[id: example.form].flatMap { FormHighlight.range(of: $0, for: verb, in: example.jp) })` in `.sentence(.title3)`, ink.
    - The English is `.subheadline` in `muted`, always shown (the board shows it).
    - A `SpeakButton(text: example.jp)` trails, and `.textActions(example.jp, translate: true)` stays.
  - **The verb page:** add a section after Common phrases.
    - Heading: `SectionHeader("Examples") { Button("See all", action: onExamples).font(.subheadline.weight(.semibold)) }`.
    - Card: the first three examples as `VerbExampleRow`s with rule dividers, in `.paperCard(cornerRadius: 14, ruled: true)`.
    - Draw the section only when `verb.examples` isn't empty. Hide "See all" when there are three or fewer.
  - **The sheet:** rebuild `ExamplesView` as a `ScrollView` with the same ruled card holding every example. Add `paperBackground()`. Keep the title and the Done button.
  - **Common phrases:** drop the header icon. Use `.sentence(.title3)` for the Japanese and `muted` for the English, and keep the `SpeakButton`.
  - **The notes box:** stays a `paperCard`, with ink text in `.subheadline` and the `lightbulb` glyph in ink.
- [ ] **Step 9: Build iOS, then check たべる in Light with furigana on and off, and the sheet.** Expected:
  - 食べます is bold and underlined, with た over 食, and the ruled grid is visible but faint.
  - With furigana off, the verb is still bold and underlined.
  - In Nocturnal, the grid stays faint and doesn't fight the text.
- [ ] **Step 10: Update AGENTS.md and commit.**
  - AGENTS.md VerbKit table: add `FormHighlight.range(of:for:in:)` and `TextUnit.emphasizing(_:characters:)`.
  - AGENTS.md components table: add `VerbExampleRow` and `JapaneseText(_:emphasizing:)`.
  - Commit message: `Examples on genkō paper with the verb underlined, on the verb page and in the sheet`.

### Task 5: Sub-page header and "How it's made" on Potential

**Files:**
- Modify: `Packages/VerbKit/Sources/VerbKit/Lens/FormLookup.swift` (the `Verb` extension)
- Create: `Packages/VerbKit/Sources/VerbKit/Forms/PotentialPattern.swift`
- Create: `Packages/VerbKit/Tests/VerbKitTests/PotentialPatternTests.swift`
- Modify: `Packages/VerbKit/Tests/VerbKitTests/FormLookupTests.swift` (the `units(for:)` tests)
- Create: `App/VerbSubPageHeader.swift`
- Modify: `App/PotentialPage.swift`, `App/NdesuPage.swift`, `App/AuxiliariesPage.swift`, `App/AdvancedPage.swift`, `App/VerbLessonsPage.swift`, `App/LessonLinks.swift`, `AGENTS.md`

**Interfaces:**
- Consumes: `KanjiSpelling`, `FormSplit.split(_:from:)`, `VerbExampleRow`, `paperCard(ruled:)`, `PaperButtonStyle`.
- Produces:
  - `public extension Verb { func units(for kana: String) -> [TextUnit] }`. `dictionaryUnits` becomes `units(for: dict)`.
  - `public enum PotentialPattern: Equatable, Sendable { case ru, u, suru, kuru; public init?(verb: Verb) }`.
  - `struct VerbSubPageHeader: View { let verb: Verb; let title: String; var headline: String? }`.

- [ ] **Step 1: Write the failing tests.**

```swift
// FormLookupTests
func testUnitsSpellFormWithKanjiStem() {
    XCTAssertEqual(taberu.units(for: "たべられる"),
                   [TextUnit(text: "食", reading: "た"), TextUnit(text: "べられる")])
}
func testUnitsUseKuruChangedReading() {
    XCTAssertEqual(kuru.units(for: "こられる"),
                   [TextUnit(text: "来", reading: "こ"), TextUnit(text: "られる")])
}
func testUnitsFallBackToKana() {        // する → できる has no kanji stem
    XCTAssertEqual(suru.units(for: "できる"), [TextUnit(text: "できる")])
}

// PotentialPatternTests
func testRuVerb()  { XCTAssertEqual(PotentialPattern(verb: taberu), .ru) }
func testUVerb()   { XCTAssertEqual(PotentialPattern(verb: nomu), .u) }
func testSuru()    { XCTAssertEqual(PotentialPattern(verb: suru), .suru) }
func testSuruCompound() { XCTAssertEqual(PotentialPattern(verb: benkyouSuru), .suru) } // べんきょうする
func testKuru()    { XCTAssertEqual(PotentialPattern(verb: kuru), .kuru) }
func testNoPatternWithoutPotential() { XCTAssertNil(PotentialPattern(verb: aru)) }  // forms.potential == nil
```

- [ ] **Step 2: Run the tests and confirm they fail.**
  - Run: `cd Packages/VerbKit && swift test --filter 'PotentialPatternTests|FormLookupTests'`
  - Expected: a compile failure on `units(for:)` and `PotentialPattern`.
- [ ] **Step 3: Implement both.**
  - `units(for:)`: when `KanjiSpelling(self)` has a reading stem that prefixes `kana`, return `[kanjiStem with that reading, the rest]`, dropping an empty rest. Otherwise return `[TextUnit(text: kana)]`.
  - `PotentialPattern(verb:)`:
    - nil when `verb.forms.potential == nil`;
    - `.ru` for type `.ru`, `.u` for type `.u`;
    - for `.irregular`: `.kuru` when `dict.hasSuffix("くる")`, `.suru` when `dict.hasSuffix("する")`, otherwise nil.
- [ ] **Step 4: Run the tests and confirm they pass.** Run the filter again, then `make test-swift`. Expected: all pass. The existing `dictionaryUnits` tests still pass.
- [ ] **Step 5: Build `VerbSubPageHeader`.**
  - A muted context line: `JapaneseText(units: verb.dictionaryUnits)` in `.headword(.subheadline)`.
  - The title in `.largeTitle.weight(.bold)`, ink.
  - When `headline` is set, `JapaneseText(units: verb.units(for: headline))` in `.headword(.largeTitle, scale: 1.3)`.
  - Put it at the top of all five sub-pages, add `paperBackground()` to each, and hide their navigation titles with `.toolbar(removing: .title)` on iOS. The title stays set for the back button and VoiceOver, as `VerbDetailView` does.
  - Only `PotentialPage` passes a headline: `verb.forms.potential`.
- [ ] **Step 6: Add the "How it's made" card to `PotentialPage`, shown when `PotentialPattern(verb:)` is non-nil.**
  - A `paperCard` captioned `HOW IT’S MADE` in `.caption.weight(.semibold)`, muted.
  - Then a row with `FormCell(form: verb.dict, dict: verb.forms.potential!)`, `Image(systemName: "arrow.right")` in muted, and `FormCell(form: verb.forms.potential!, dict: verb.dict)`. The splits run both ways, so each side bolds its own ending.
  - Then the explanation, in App wording keyed on the pattern:
    - `.ru`: "Ru-verbs drop る and add られる. The result conjugates like a ru-verb itself."
    - `.u`: "U-verbs change the final \(dictEnding) to \(potEnding.dropLast()) and add る. The result conjugates like a ru-verb." The endings come from the two `FormSplit`s.
    - `.suru`: "する becomes できる. The result conjugates like a ru-verb."
    - `.kuru`: "くる becomes こられる. The result conjugates like a ru-verb."
  - Below the table, add the verb's potential examples (`verb.examples.filter { $0.form.rawValue.hasPrefix("pot") }`) in the ruled card from Task 4, drawn only when there are some.
- [ ] **Step 7: Switch `LessonLinks` from `.glass` to `.paperSecondary`.** Keep the leading `arrow.right.circle` label.
- [ ] **Step 8: Build iOS and macOS, then check the Potential page for 食べる, 飲む, 来る and 勉強する in Light.** Expected:
  - The headline reads 食べられる with た over 食.
  - The card shows たべ**る** → たべ**られる** and the right sentence for each verb.
  - The Auxiliaries, Advanced, んです and Grammar sub-pages sit on paper with the small header.
- [ ] **Step 9: Update AGENTS.md and commit.**
  - AGENTS.md: add `Verb.units(for:)` and `PotentialPattern` to the VerbKit table, and `VerbSubPageHeader` to the components table.
  - Commit message: `Verb sub-pages: paper header, potential headline and How it's made`.

### Task 6: Quiz results with a teacher's stamp

**Files:**
- Modify: `Packages/VerbKit/Sources/VerbKit/Quiz/QuizViewModel.swift`
- Modify: `Packages/VerbKit/Tests/VerbKitTests/QuizViewModelTests.swift` (or the file that holds the `missedQuestions` tests: `grep -rln missedQuestions Packages/VerbKit/Tests`)
- Create: `App/UI/QuizScoreCard.swift`
- Modify: `App/QuizResultsView.swift`, `App/QuizView.swift`, `App/UI/QuizChrome.swift` (`QuizResultsSummary`, `QuizMissedCard`), `AGENTS.md`

**Interfaces:**
- Consumes: `paperCard(ruled:)`, `PaperButtonStyle`, `Font.headword`, `QuizProgress(attempts:).currentStreak`, `QuizHistoryStore`, `QuizSessionTopic.title`, `Verb.dictionaryUnits`.
- Produces:
  - `public var missed: [(question: QuizQuestion, result: QuizResult)]` on `QuizViewModel`: the wrong and timed-out answers in quiz order, choices left as asked.
  - `struct QuizScoreCard: View { let score: Int; let count: Int; let lines: [String] }`.
  - `QuizResultsView(viewModel:topicTitle:onDone:onPractiseMissed:)`.

- [ ] **Step 1: Write the failing test.**

```swift
func testMissedPairsQuestionsWithResults() {
    // A three-question quiz: answer 1 right, 2 wrong (choose a wrong choice), 3 timed out.
    // missed.count == 2; missed[0].question.verb == q2.verb and missed[0].result.chosen == the wrong choice;
    // missed[1].result.timedOut == true. A quiz answered all right has missed.isEmpty.
}
```

- [ ] **Step 2: Run the test and confirm it fails.**
  - Run: `cd Packages/VerbKit && swift test --filter QuizViewModel`
  - Expected: a compile failure, because `missed` doesn't exist.
- [ ] **Step 3: Implement `missed`.** Use `zip(questions, results).filter { !$0.1.ok }`. Leave `missedQuestions` as it is; it still shuffles the choices for the retry.
- [ ] **Step 4: Run the tests and confirm they pass.** Run the filter, then `make test-swift`. Expected: all pass.
- [ ] **Step 5: Build `QuizScoreCard`.**
  - A `paperCard(cornerRadius: 16, ruled: true)` holding an HStack of the stamp and the text lines.
  - **The stamp:** 120 × 120 pt (`@ScaledMetric`). Inside, the score in `.headword` bold at 44 pt, with "/count" at 22 pt, both in `palette.mark`, under a hand-drawn ring.
    - The ring is a `Shape` from the board's path, scaled to the frame: `M60 8 C88 7 112 30 111 60 c-1 29 -24 52 -53 51 C30 110 8 88 9 59 10 33 30 12 57 9`.
    - Stroke it 3 pt in `mark` with round caps.
  - **Animation:** on appear, animate the ring's `trim(from: 0, to:)` from 0 to 1 over 0.5 s, `.easeOut`. Skip the animation when `accessibilityReduceMotion` is on.
  - **Text:** first line "Quiz complete" in `.title2.weight(.bold)`, ink. Then each of `lines` in `.subheadline`, muted.
  - **VoiceOver:** `.accessibilityElement(children: .ignore)`, with the label "Score \(score) out of \(count)" plus the lines.
- [ ] **Step 6: Rebuild `QuizResultsView` as on the board.**
  - **Score card:** `QuizScoreCard` with these lines:
    - "\(percentage)% correct · \(topicTitle)";
    - "Streak: \(n) day(s)" when `QuizProgress(attempts: quizHistory.attempts).currentStreak > 0`. Read the store with `@Environment(QuizHistoryStore.self)`.
  - **"Marked wrong"** (`SectionHeader`), only when `viewModel.missed` isn't empty. One row per pair, rule dividers, in a `paperCard`:
    - **Heading:** `JapaneseText(units: question.verb.dictionaryUnits)` in `.headword(.title3)`, ink, followed by " — " and the form label in muted. Identify-kind rows show `result.formString` instead of the label, as the current code does.
    - **Choice line**, in a `WrappingFlowLayout`:
      - "YOU CHOSE" in `.caption.weight(.bold)`, `mark`, then the chosen answer struck through in `mark`;
      - or, when timed out, "TIME’S UP" in `mark` alone;
      - then "CORRECT" in `.caption.weight(.bold)`, `good`, then the right answer bold in ink.
    - **Explanation:** `result.errorExplanation` in `.footnote`, muted, when present.
  - **Buttons:** pinned with `.safeAreaInset(edge: .bottom)` on a `palette.paper` bar.
    - "Practise the \(n) missed" (`.paper`), shown when anything was missed.
    - "Done" (`.paperSecondary`).
  - **Background:** `paperBackground()` on the ScrollView.
  - **Emoji:** remove the emoji and its `@ScaledMetric`s.
  - **Caller:** `QuizView` passes `topic.title`.
- [ ] **Step 7: Restyle `QuizResultsSummary` and `QuizMissedCard`.**
  - `QuizResultsSummary`: its top becomes `QuizScoreCard(score:count:lines: [subtitle])`. Its two buttons move to the same pinned bottom bar: "Practise missed" with `.paper` and "Done" with `.paperSecondary`. Add `paperBackground()`.
  - `QuizMissedCard`: draws `paperCard()` instead of glass.
  - None of the four callers change.
- [ ] **Step 8: Build iOS and macOS. Check results on the simulator.**
  - Light: play a five-question て-form quiz, answering wrong once and letting one time out.
  - Halloween: a perfect quiz.
  - Light again: a counter quiz.
  - Expected:
    - The red ring draws around the score.
    - Only the two misses are listed: the struck answer in red, the correct one labelled in green, and "TIME’S UP" with no strike.
    - The perfect quiz shows no "Marked wrong" section.
    - The counter results get the same score card.
- [ ] **Step 9: Update AGENTS.md and commit.**
  - AGENTS.md components table: add `QuizScoreCard`, and note that `QuizResultsSummary` uses it.
  - Commit message: `Quiz results: teacher's stamp, marked-wrong list and pinned paper buttons`.

### Task 7: Spec and docs

**Files:**
- Modify: `docs/superpowers/specs/2026-11-06-paper-ink-redesign-design.md`

- [ ] **Step 1: Update spec rule 9.**
  - Headwords use `HiraMinProN-W6`; example sentences and phrases use `HiraMinProN-W3`, with the verb in bold, as the board draws them.
  - Mark plan 2 as built in the "Boards → plans" table.
- [ ] **Step 2: Run `make check` and `make check-project`.** Expected: both pass.
- [ ] **Step 3: Commit.** Message: `Spec: sentence font and plan 2 status`.
