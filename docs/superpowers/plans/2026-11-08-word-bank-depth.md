# Word Bank Depth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the Word Bank entry page and the add/edit sheet in paper and ink, as the boards draw them, and turn the on-device suggestions into one card with "Use all" and "Dismiss".

**Architecture:**
- **VerbKit** gets four small testable additions:
  - where an entry's kanji come from (`KanjiExtraction.chips`);
  - a `dismissed` state on `EntrySuggestionModel`;
  - quick tag picks for the editor (`TagSuggester.quickPicks`);
  - a public `WordBankDates.day`.
- **App** gets:
  - shared paper form pieces (`PaperField`, `PaperDivider`, `.paperInline`);
  - a restyled `TagPill`;
  - a rewritten `WordBankDetailView` and `WordBankEditor`, with the editor's Kind, word class, kanji spelling and notes moved to a "More" page;
  - `EntrySuggestionCard`.
- Behaviour stays as it is: saving, duplicates, dictionary-form offers, reading auto-fill and the kanji stroke-order sheet.

**Tech Stack:** Swift 6, SwiftUI (iOS 26, macOS 26), FoundationModels (existing, unchanged), XCTest in `Packages/VerbKit`.

**Spec:** `docs/superpowers/specs/2026-11-06-paper-ink-redesign-design.md`, row 7 of "Boards → plans". Boards: "Word Bank: entry" (`project/WordBankEntry.dc.html`) and "Word Bank: add a word" (`project/WordBankAdd.dc.html`).

## Global Constraints

- **Branch:** `claude/word-bank-depth`, from `origin/main`.
- **Architecture:**
  - VerbKit stays UI-free.
  - Wording lives in App.
  - No change under `data/`, no new dependency, no download.
  - The `.wordbank` archive format and `WordBankEntryValue` stay as they are; no model or schema change.
- **Spec rules:**
  - **Glass only on chrome:** the back, Speak, Edit and More buttons, and the sheet's Cancel/Save. The kanji chips lose their `glassEffect` and become `card` tiles.
  - Content buttons are `.paper*`. The suggestion card's "Use all" is the new `.paperInline` and "Dismiss" is `.paperSecondaryInline`.
  - **Red only where something is marked:** "Delete" stays `role: .destructive`, inside the overflow menu.
  - **Furigana:** every Japanese string with kanji goes through `JapaneseText`, including section titles (方言 → 標準語), notes, meaning notes and the suggestion card.
  - **Never colour alone:** tag pills keep their glyph (map pin for dialect tags, # for custom). A custom tag's colour becomes a small dot beside an ink name.
  - **Contrast:** text is at least 4.5:1. Tag text is `ink`, never the tag colour; placeholders use `muted`.
  - Switches use `paperSwitch()` (no new ones here).
  - **Selected tag chips use `FilterChip`** (filled with `button`), per spec rule 3. The board's 2 pt ink border on a selected tag is overridden by that rule. *Owner to confirm.*
- **Copy, entry page (exact, from the board):**
  - section titles "方言 → 標準語", "Meanings", "Kanji", "Notes";
  - folder line "Folder: Kansai › Everyday" (path joined with " › ");
  - kanji caption "From the standard form. Tap for stroke order.";
  - dates "Added 2026-10-30 · Edited 2026-11-04" (`yyyy-MM-dd`; "· Edited …" only when the day differs);
  - accessibility "Speak", "Edit", and "凄, stroke order" for a kanji tile.
- **Copy, editor (exact, from the board):**
  - title "New word";
  - "Cancel" / "Save";
  - field labels "Text", "Reading" (placeholder "かな"), "Written" (placeholder "ありがとう"), "Meaning 1…n" (placeholder "thank you");
  - section headers "STANDARD JAPANESE", "MEANINGS", "TAGS";
  - rows "Add a meaning", "+ New tag", "Folder", "More" with the subtitle "Kanji spelling, notes";
  - the suggestion card: "Suggested on this device", "Standard: …", "Meaning: … · Dialect: …", "Use all", "Dismiss".
- **Placeholders** (not on the boards; flagged for the owner):
  - "Edit word" (edit title);
  - "Add a standard form";
  - "From the kanji spelling.";
  - "Reading: …" and "Kind: …" suggestion lines;
  - field labels "Note" and "Kind";
  - accessibility "Remove meaning N" / "Remove standard form N".
  - Existing copy is kept where the boards are silent: "Text (おおきに)" becomes the placeholder "おおきに"; the duplicate and dictionary-form notes; the furigana auto-fill note; "Looking for suggestions…"; "Couldn't get suggestions" / "Try again"; the unsure note; "Tap a kanji to open it in Jisho."
- **Tests:** `make test-swift`.
- **iOS build:** `make project && xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination 'generic/platform=iOS Simulator' build -quiet`.
- **macOS build:** the same command with `-scheme JPVerbConjugation_macOS -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO`. It passes when there are no Swift `error:` lines.
- **AGENTS.md:** each task adds its shared symbols to the tables in the same commit.
- **Release:** no TestFlight or App Store release.

## Review Focus

1. **Dismissing the card, then typing on.**
   - Expected: the same text (even with a trailing space) stays dismissed, and the model is not asked again. A different word brings a new card.
   - Covered by Task 3, `testDismissHidesUntilTheTextChanges`.
2. **An entry whose kanji come from more than one place**, for example kanji text and a kanji standard form.
   - Expected: no "From the …" claim. Only a single source is named.
   - Covered by Task 2, `testTheSourceIsNamedOnlyWhenOneFieldHasKanji`.
3. **Someone with thirty tags.**
   - Expected: the editor shows every applied tag plus at most eight others, recent first, and never hides an applied tag.
   - Covered by Task 4, `testAppliedTagsAlwaysShowAndOthersAreCapped`.
4. **A recent tag that was since deleted, or merged by an import.**
   - Expected: it is skipped silently.
   - Covered by Task 4, `testDeletedRecentIDsAreSkipped`.
5. **A sentence-length entry at AX5, and kanji with no stroke data.**
   - Expected: the 46 pt headword wraps without clipping, the tiles wrap, and the caption switches to the Jisho wording.
   - Covered by Task 5, step 2 (simulator check).

---

### Task 1: Paper form pieces and tag pill (App)

**Files:**
- Create: `App/UI/PaperField.swift` (`PaperField`, `PaperDivider`, `PaperFieldSection`)
- Modify: `App/UI/PaperButtonStyle.swift` (add `.paperInline`)
- Modify: `App/WordBank/TagPill.swift` (paper restyle)
- Modify: `AGENTS.md` (components table)

**Interfaces:**
- Consumes: `\.palette`, `paperCard`, `JapaneseText`.
- Produces:
  - `struct PaperField: View` with `init(_ label: String, placeholder: String, text: Binding<String>, font: Font = .body, axis: Axis = .horizontal)`.
    - A `caption` label in `muted` sits above a borderless `TextField` in `ink`. The placeholder uses `Text(placeholder).foregroundStyle(palette.muted)` through `prompt:`.
    - Padding is 9 × 14.
    - The label is the field's accessibility label.
  - `struct PaperDivider: View`: a 1 pt `rule` line (1.5 pt with Increase Contrast), full width.
  - `struct PaperFieldSection<Content: View>: View { let title: String?; @ViewBuilder let content: () -> Content }`.
    - An optional uppercase `caption.weight(.semibold)` header in `muted`, then the content in a card (`card` fill, `rule` outline, 14 pt radius, no inner padding).
    - Callers put `PaperDivider()` between rows.
  - `static var paperInline: PaperButtonStyle { PaperButtonStyle(.primary, fillsWidth: false) }`.
  - `TagPill` restyle; its initialisers are unchanged, so existing call sites keep working.
    - `card` fill and `ink` text.
    - A 1 pt outline: `ink` for a dialect tag, `rule` for a custom one.
    - The glyph stays, and a 6 pt dot in the tag colour precedes a custom tag's name.
    - It gains `var isDialect: Bool`, set by the two value initialisers.

- [ ] **Step 1: Write `PaperField`, `PaperDivider`, `PaperFieldSection` and `.paperInline`,** with `#Preview`s in Light and Nocturnal dark.
- [ ] **Step 2: Restyle `TagPill`.**
- [ ] **Step 3: Build iOS and macOS, then check on the simulator.** Expected:
  - iOS succeeds, and macOS shows no Swift `error:` lines;
  - Word Bank rows, the tag picker and Manage tags show the new pills with readable text in every theme, yellow tags included;
  - with Differentiate Without Color on, dialect and custom tags still differ by glyph.
- [ ] **Step 4: Update AGENTS.md and commit.**
  - AGENTS.md components table:
    - `PaperField` / `PaperFieldSection` / `PaperDivider`: labelled fields in a paper card, for editors;
    - `.paperInline`: an ink capsule hugging its label;
    - amend the `TagPill` row: paper pill, glyph, colour dot.
  - Commit message: `Paper fields, inline ink button and paper tag pills`.

### Task 2: The entry page (VerbKit + App)

**Files:**
- Modify: `Packages/VerbKit/Sources/VerbKit/WordBank/KanjiExtraction.swift` (add `chips`)
- Modify: `Packages/VerbKit/Sources/VerbKit/WordBank/WordBankDates.swift` (`public enum`, `public static func day`)
- Create: `Packages/VerbKit/Tests/VerbKitTests/KanjiChipsTests.swift`
- Rewrite: `App/WordBank/WordBankDetailView.swift`
- Modify: `AGENTS.md` (VerbKit table: `KanjiExtraction` row)

**Interfaces:**
- Consumes: Task 1's `TagPill`; `SectionHeader`, `JapaneseText`, `Font.headword`, `paperCard`, `SpeakButton`, `kanjiSheet(_:)`, `KanjiStore.entry(for:)`, `TextLookupURL.jishoKanji`.
- Produces:
  - `public struct KanjiChips: Equatable, Sendable { public enum Source: Equatable, Sendable { case text, spelling, standard, mixed }; public let kanji: [Character]; public let source: Source }`.
  - `KanjiExtraction.chips(text: String, spelling: String?, standard: [String]) -> KanjiChips` (`public static`). The kanji are `kanji(in: [text, spelling ?? ""] + standard)`, in the same order as today. The source is the single field that has any kanji, `.mixed` when more than one does, and `.text` when none do.
  - `WordBankDates.day(_:) -> String`, now public.

- [ ] **Step 1: Write the failing tests.**

```swift
func testKanjiKeepTheirOrderAcrossFields() {
    XCTAssertEqual(KanjiExtraction.chips(text: "めっちゃ", spelling: nil, standard: ["凄く", "とても"]).kanji, ["凄"])
}
func testTheSourceIsNamedOnlyWhenOneFieldHasKanji() {
    XCTAssertEqual(KanjiExtraction.chips(text: "めっちゃ", spelling: nil, standard: ["凄く"]).source, .standard)
    XCTAssertEqual(KanjiExtraction.chips(text: "おおきに", spelling: "大きに", standard: ["ありがとう"]).source, .spelling)
    XCTAssertEqual(KanjiExtraction.chips(text: "直す", spelling: nil, standard: ["片付ける"]).source, .mixed)
    XCTAssertEqual(KanjiExtraction.chips(text: "食う", spelling: nil, standard: []).source, .text)
}
func testDayIsPublicAndFixed() {
    XCTAssertEqual(WordBankDates.day(Date(timeIntervalSince1970: 1_761_825_600)), "2025-10-30")   // 12:00 UTC, the same day in any time zone within ±11 h
}
```

- [ ] **Step 2: Run the tests and confirm they fail.** Run `cd Packages/VerbKit && swift test --filter KanjiChipsTests`. Expected: a compile failure.
- [ ] **Step 3: Implement `chips` and make `day` public.** Run the filter, then `make test-swift`. Expected: all pass.
- [ ] **Step 4: Rewrite `WordBankDetailView` to the board, top to bottom.**
  - **Toolbar** (glass, system):
    - `primaryAction`: `SpeakButton(text: entry.reading ?? entry.text)` with `.accessibilityHint("Standard pronunciation")`, then Edit.
    - `secondaryAction`: "Move to…", "Delete" (destructive), and Report, as today.
    - The "Standard pronunciation" row on the page goes; the hint keeps the caveat.
  - **Header:**
    - a row of `TagPill`s (dialect, then custom), then `· <word class>` in `muted` (`wordClass.displayName.lowercased()`, or the kind's raw value when it isn't `.word`);
    - `JapaneseText(entry.text)` in `.headword(.largeTitle, scale: 1.35)` (46 pt), with `textActions`;
    - the typed reading in `muted` when it differs (existing rule);
    - the kanji spelling line ("Written" + `JapaneseText`, existing);
    - "Folder: \(path)" in `muted`.
  - **方言 → 標準語:**
    - the header is `JapaneseText("方言 → 標準語").font(.headword(.title3))` with `.accessibilityAddTraits(.isHeader)`;
    - one `paperCard` row: `JapaneseText(entry.text)` · `Image(systemName: "arrow.right")` in `muted` · `JapaneseText(equivalents.map(\.written).joined(separator: "・"))`;
    - under it, one `muted` `JapaneseText` line per equivalent that has a note: "\(written) — \(note)".
  - **Meanings:** `SectionHeader("Meanings")`, then one `paperCard` with a row per sense: the bold `muted` number, then the meaning. A note follows as `muted` " — " + `JapaneseText(note)`. `PaperDivider()` goes between rows.
  - **Kanji:** `SectionHeader("Kanji")`, then a `WrappingFlowLayout` of tiles.
    - A tile is 56 pt (`@ScaledMetric`) with `card` fill, a `rule` outline and a 12 pt radius. It shows the character in `.headword(.title)`.
    - The tap behaves as today: the stroke-order sheet, else Jisho.
    - The caption is the source phrase ("From the standard form." / "From the kanji spelling.", none for `.text`/`.mixed`), followed by "Tap for stroke order." when any kanji has strokes, else "Tap a kanji to open it in Jisho."
  - **Notes:** `SectionHeader("Notes")`, then `JapaneseText(notes)` in a `paperCard`, selectable.
  - **Dates:** centred `caption` in `muted`: `"Added \(WordBankDates.day(createdAt))"`, plus `" · Edited \(…)"` when the day differs.
  - **Removed:** the separate Tags section and the folder `Label`; their content now sits in the header.
- [ ] **Step 5: Build iOS and macOS, then check on the simulator.**
  - Expected: iOS succeeds, and macOS shows no Swift `error:` lines.
  - Open めっちゃ (Kansai-ben; standard 凄く・とても; two meanings). Expected: it matches the board in Light; in Nocturnal dark everything is readable; VoiceOver reads the tile as "凄, stroke order".
  - Save screenshots.
- [ ] **Step 6: Update AGENTS.md and commit.**
  - AGENTS.md: the `KanjiExtraction` row gains `chips(text:spelling:standard:)`; the `WordBankDates` row says it is public.
  - Commit message: `Word Bank entry page in paper and ink`.

### Task 3: The suggestion card (VerbKit + App)

**Files:**
- Modify: `Packages/VerbKit/Sources/VerbKit/WordBank/EntrySuggestion.swift` (`State.dismissed`, `dismiss()`)
- Modify: `Packages/VerbKit/Tests/VerbKitTests/EntrySuggestionTests.swift`
- Create: `App/WordBank/EntrySuggestionCard.swift`
- Modify: `App/WordBank/WordBankEditor.swift` (replace `suggestionsSection`, `suggestionChips`, `chip`; keep `useAll` and `applyDialect`)

**Interfaces:**
- Consumes: Task 1's `.paperInline`, `.paperSecondaryInline`; `EntrySuggestion.removing(whatIsIn:appliedDialectCatalogueIDs:)`; `DialectCatalogue.bundled`.
- Produces:
  - `EntrySuggestionModel.State.dismissed`.
  - `EntrySuggestionModel.dismiss()` (`public func`). It cancels any running task and sets `.dismissed`. Text with the same `JapaneseNormalizer.key` keeps it dismissed and isn't asked again; other text resumes the normal flow.
  - `struct EntrySuggestionCard: View { let state: EntrySuggestionModel.State; let rest: EntrySuggestion?; let dialectName: String?; let onUseAll: () -> Void; let onDismiss: () -> Void; let onRetry: () -> Void }`. Here `rest` is the suggestion minus what the draft already has, computed by the editor.

- [ ] **Step 1: Write the failing test.**

```swift
func testDismissHidesUntilTheTextChanges() async {
    let fake = FakeSuggester()
    let model = model(fake)
    model.textChanged("ほんま"); await settle()
    model.dismiss()
    XCTAssertEqual(model.state, .dismissed)
    model.textChanged("ほんま "); await settle()
    XCTAssertEqual(model.state, .dismissed)
    XCTAssertEqual(fake.calls, ["ほんま"])
    model.textChanged("めっちゃ"); await settle()
    XCTAssertEqual(model.state, .ready(EntrySuggestion(meanings: ["x"])))
    XCTAssertEqual(fake.calls, ["ほんま", "めっちゃ"])
}
```

- [ ] **Step 2: Run the test and confirm it fails.** Run `swift test --filter EntrySuggestionModelTests`. Expected: a compile failure.
- [ ] **Step 3: Implement `dismiss()`.** Run the filter, then `make test-swift`. Expected: all pass.
- [ ] **Step 4: Write `EntrySuggestionCard` and use it in the editor.**
  - **Card:** `card` fill, a 1 pt **dashed** `muted` outline (`StrokeStyle(lineWidth: 1, dash: [4, 3])`), 14 pt radius, 12 × 14 padding.
  - **Header:** `Label("Suggested on this device", systemImage: "sparkles")`, `footnote`, `muted`.
  - **States:**
    - `.idle`, `.unavailable`, `.dismissed`: draw nothing.
    - `.loading`: a `ProgressView` and "Looking for suggestions…".
    - `.nothing`, `.unsure`, `.failed`: the existing one-line notes; failed has "Try again" in `.paperSecondaryInline`.
    - `.ready` with an empty `rest`: "Nothing new to suggest: the entry already has it."
    - `.ready` otherwise, as lines:
      1. "Reading: …", when present;
      2. "Standard: " + `JapaneseText(forms.joined(separator: "・"))` in `.headword(.body)`;
      3. one line joining with " · " the parts "Meaning: a, b", "Dialect: \(name)" and "Kind: Phrase", each only when present.
    - When `rest.isUnsure`, the existing unsure footnote follows.
    - Then an `HStack`: "Use all" (`.paperInline`) and "Dismiss" (`.paperSecondaryInline`).
  - **Editor wiring:** "Use all" calls the existing `useAll(rest)`; "Dismiss" calls `suggestions.dismiss()`.
  - **Removed:** the per-item chips. *Owner to confirm: the board offers only Use all / Dismiss.*
- [ ] **Step 5: Build iOS, then check on a device or simulator with Apple Intelligence.** Type ほんま. Expected:
  - the card shows Standard 本当 with furigana;
  - Use all fills Standard, Meaning and the Kansai-ben tag, and the card says "Nothing new to suggest…";
  - Dismiss hides it until the text changes.
  - Without Apple Intelligence: no card.
- [ ] **Step 6: Commit.** Message: `Word Bank editor: one suggestion card with Use all and Dismiss`.

### Task 4: The editor restyle (VerbKit + App)

**Files:**
- Modify: `Packages/VerbKit/Sources/VerbKit/WordBank/TagSuggester.swift` (add `quickPicks`)
- Modify: `Packages/VerbKit/Tests/VerbKitTests/TagSuggesterTests.swift`
- Create: `App/WordBank/RecentTags.swift` (the `"wordBank.recentTags"` read and record, taken out of `TagPicker`)
- Modify: `App/WordBank/TagPicker.swift` (use `RecentTags`)
- Create: `App/WordBank/WordBankEditorMore.swift` (the "More" page)
- Rewrite: `App/WordBank/WordBankEditor.swift` (body and sections; helpers kept)
- Modify: `AGENTS.md` (VerbKit `TagSuggester` row; components)

**Interfaces:**
- Consumes: Task 1's `PaperField`, `PaperFieldSection`, `PaperDivider`, `FilterChip`, `TagPill`; Task 3's `EntrySuggestionCard`; `FolderPicker`, `TagPicker`, `FolderTree.path(of:)`.
- Produces:
  - `TagSuggester.quickPicks(applied: [UUID], recent: [UUID], dialectTags: [DialectTagValue], customTags: [CustomTagValue], limit: Int = 8) -> [TagSuggestion]` (`public func`). It returns `.existingDialect` / `.existingCustom` values in this order:
    1. every applied tag, in applied order;
    2. recent tags that are not applied, in recent order;
    3. the remaining tags, dialect before custom, each by `name` using `localizedStandardCompare`.

    Unknown ids are skipped. Groups 2 and 3 together are capped at `limit`.
  - `enum RecentTags { static let key = "wordBank.recentTags"; static func load() -> [UUID]; static func record(_ id: UUID) }` (standard `UserDefaults`, newest first, eight kept: the same behaviour as today).
  - `struct WordBankEditorMore: View { @Binding var draft: WordBankEntryValue }`. It shows Kind (segmented), Word class (when kind is `.word`), "Kanji spelling" (placeholder "大きに") and "Source or notes", all in `PaperFieldSection`s on `paperBackground()`, with the title "More".

- [ ] **Step 1: Write the failing tests.**

```swift
func testAppliedTagsAlwaysShowAndOthersAreCapped() {
    let custom = (0..<30).map { CustomTagValue(name: "tag \($0)", color: .blue) }
    let applied = [custom[29].id, custom[28].id]
    let picks = TagSuggester().quickPicks(applied: applied, recent: [custom[3].id], dialectTags: [], customTags: custom, limit: 8)
    XCTAssertEqual(picks.count, 10)
    XCTAssertEqual(Array(picks.prefix(3)), [.existingCustom(custom[29]), .existingCustom(custom[28]), .existingCustom(custom[3])])
}
func testDeletedRecentIDsAreSkipped() {
    let kansai = DialectTagValue(name: "Kansai-ben", region: .kansai)
    let picks = TagSuggester().quickPicks(applied: [], recent: [UUID(), kansai.id], dialectTags: [kansai], customTags: [])
    XCTAssertEqual(picks, [.existingDialect(kansai)])
}
func testDialectsComeBeforeCustomInTheRest() {
    let (tosa, hakata) = (DialectTagValue(name: "Tosa-ben", region: .shikoku), DialectTagValue(name: "Hakata-ben", region: .kyushuOkinawa))
    let (slang, food) = (CustomTagValue(name: "slang", color: .purple), CustomTagValue(name: "food", color: .orange))
    let picks = TagSuggester().quickPicks(applied: [], recent: [], dialectTags: [tosa, hakata], customTags: [slang, food])
    XCTAssertEqual(picks, [.existingDialect(hakata), .existingDialect(tosa), .existingCustom(food), .existingCustom(slang)])
}
```
- [ ] **Step 2: Run the tests and confirm they fail.** Run `swift test --filter TagSuggesterTests`. Expected: a compile failure.
- [ ] **Step 3: Implement `quickPicks` and `RecentTags`, and move `TagPicker` onto `RecentTags`.** Run `make test-swift`. Expected: all pass.
- [ ] **Step 4: Rewrite the editor body.** Use a `ScrollView` on `paperBackground()`, keeping the `NavigationStack`, with 14 pt spacing and 16 pt side padding. Top to bottom:
  - **Title and toolbar:** "New word" or "Edit word". The toolbar keeps Cancel / Save (disabled while the text is empty); the system draws Save as the prominent tinted button.
  - **Untitled `PaperFieldSection`:**
    - `PaperField("Text", placeholder: "おおきに", font: .headword(.title2), axis: .vertical)`, then `PaperDivider()`, then `PaperField("Reading", placeholder: "かな")`.
    - Under the card: the auto-fill note, the duplicate note with "Open" (`.paperSecondaryInline`), and the dictionary-form offers ("Use …", `.paperSecondaryInline`). Their copy and behaviour are unchanged.
  - **`EntrySuggestionCard`** (Task 3), when suggestions are on.
  - **"Standard Japanese":**
    - per equivalent: `PaperField("Written", placeholder: "ありがとう")`, then "Reading" and "Note" fields;
    - a trailing `minus.circle` button in `muted` labelled "Remove standard form N";
    - dividers between rows, and a last row button "Add a standard form" with `plus`.
  - **"Meanings":**
    - per sense: `PaperField("Meaning \(n)", placeholder: "thank you")` and "Note" (placeholder "≠ standard 直す");
    - a remove button as above;
    - a last row button "Add a meaning".
  - **"Tags":** a `WrappingFlowLayout` of `FilterChip(name, isOn: applied)` buttons from `quickPicks`. A tap toggles the id in `draft.dialectTagIDs` / `customTagIDs` and calls `RecentTags.record`. The last chip is "+ New tag", outlined with a dashed `rule` border and `muted` text, and opens `TagPicker`.
  - **Untitled `PaperFieldSection`:**
    - a "Folder" row showing the path ("Unfiled" when none) and a `RowChevron`, opening `FolderPicker`;
    - `PaperDivider()`;
    - a `NavigationLink` row "More" with the subtitle "Kanji spelling, notes" in `muted`, opening `WordBankEditorMore(draft: $draft)`.
  - **Kept as they are:** `refreshReading`, `readingFor`, `useDictionaryForm`, `save`, `optional(_:)`, the alert, `onChange(of: draft.text)` and `onAppear`.
- [ ] **Step 5: Build iOS and macOS, then check on the simulator.**
  - Expected: iOS succeeds, and macOS shows no Swift `error:` lines.
  - Check:
    - add ほんま with a standard form, two meanings and Kansai-ben, file it in Kansai › Everyday, then save;
    - edit it, remove meaning 2 and save;
    - a new tag made through "+ New tag" appears applied in the chips;
    - the keyboard's Return does not save;
    - VoiceOver reads each field's label;
    - at AX5 the labels and fields wrap.
  - Save screenshots in Light and Sand dark.
- [ ] **Step 6: Update AGENTS.md and commit.**
  - AGENTS.md:
    - the `TagSuggester` row gains `quickPicks`;
    - the components table gains `RecentTags` (the Word Bank's recently used tag ids, this device);
    - Traps: "The Word Bank editor is a `ScrollView` of `PaperFieldSection`s, not a `Form`; add fields as `PaperField`."
  - Commit message: `Word Bank editor in paper and ink, with quick tag chips and a More page`.

### Task 5: Spec status, full pass and checks

**Files:**
- Modify: `docs/superpowers/specs/2026-11-06-paper-ink-redesign-design.md`

- [ ] **Step 1: Update the spec.**
  - Mark row 7 "(built)".
  - Add a "Word Bank depth" paragraph covering:
    - the entry page order;
    - kanji tiles on paper;
    - the suggestion card with Use all / Dismiss;
    - the editor's fields in paper sections;
    - quick tag chips;
    - Kind, word class, kanji spelling and notes under More.
- [ ] **Step 2: Full simulator pass.**
  - Themes: Light, Pastel, Northern lights dark and Halloween.
  - Check:
    - a sentence-length entry at AX5: the headword wraps and nothing clips;
    - an entry whose only kanji lack stroke data: the caption reads "Tap a kanji to open it in Jisho." and the tile opens Jisho;
    - Increase Contrast: outlines at 1.5 pt;
    - Differentiate Without Color: tag glyphs are visible.
- [ ] **Step 3: Run the checks.** Run `make check`, `make check-project` and `make test-swift`. Expected: all pass.
- [ ] **Step 4: Commit.** Message: `Spec: Word Bank depth built`.

---

## Self-review

- **Spec coverage:**
  - the entry page restyle: Task 2;
  - the editor restyle: Task 4;
  - the suggestion card: Task 3;
  - the shared pieces they need: Task 1.
  - The kanji chips still open the stroke-order sheet (Task 2, step 4); the suggester and the model are unchanged apart from `dismiss()`.
- **Placeholders:** the listed placeholder strings are flagged in Global Constraints.
- **Owner decisions:**
  - `FilterChip` instead of the board's bordered selected tag.
  - Per-item suggestion chips are dropped.
  - Kind and word class move under More.
  - Speak moves to the toolbar, with "Standard pronunciation" kept as its hint.
  - Dates use `yyyy-MM-dd`, as the board shows.
- **Types:**
  - `KanjiExtraction.chips(text:spelling:standard:)`, `EntrySuggestionModel.dismiss()`, `TagSuggester.quickPicks(applied:recent:dialectTags:customTags:limit:)`, `PaperField(_:placeholder:text:font:axis:)` and `EntrySuggestionCard(state:rest:dialectName:onUseAll:onDismiss:onRetry:)` are spelled the same in every task.
