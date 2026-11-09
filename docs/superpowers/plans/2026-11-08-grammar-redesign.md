# Grammar Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Grammar list and lesson pages in the paper-and-ink look: lesson layout 2 with layout 3's formula card as its header, the practise button under it, genkō example cards with the pattern underlined, common mistakes marking only the wrong part, a Polite | Casual forms table, and a list of chips and level-grouped cards.

**Architecture:** Four small pure helpers in VerbKit decide what the views draw: where the pattern sits in an example, which part of a wrong form is wrong, what the formula header shows, and which live example an attachment rule builds (moved out of `AttachmentSection` so the header and the section share it). App restyles `GrammarDetailView` (split into section views) and `GrammarListView` with the existing paper components.

**Tech Stack:** Swift 6 / SwiftUI (iOS 26, macOS 26), XCTest.

**Spec:** `docs/superpowers/specs/2026-11-06-paper-ink-redesign-design.md` (Rules) and the mockups `1-grammar-list`, `2-lesson-detail` (layout), `3-lesson-detail-alt` (formula card only) and `4-lesson-detail-dark` from the design subagent (copies in the session scratchpad `grammar-redesign/`). Owner's choices (2026-11-08): layout 2 + formula header; the list keeps its search; usages at hidden levels stay collapsed behind Show; Practise sits under the formula card.

## Global Constraints

- VerbKit stays UI-free; wording lives in App. Reuse `JapaneseText(_:emphasizing:)`, `paperCard(ruled:)`, `PaperButtonStyle` (`.paper`, `.paperSecondary`, `.paperSecondaryInline`), `SectionHeader`, `LevelBadge`, `FilterChip`, `RowChevron`, `TagPill`-style outlined capsules, `Font.headword` / `Font.sentence`.
- Liquid Glass on chrome only: the lesson tag and related links stop using `.glassEffect` / `.glass`.
- Red only for what is wrong: the wrong part of a pitfall's wrong form, with ✕, strikethrough and the spoken "Wrong:" label; the correct line gets ✓. Never colour alone.
- Furigana on every kanji when on: all Japanese through `JapaneseText`.
- Examples: W3 Mincho (`Font.sentence`) on ruled cards, the pattern underlined (and bold where the face allows) — as the verb page's examples.
- The list keeps its search field and level scope bar; the existing By level / My course modes stay, shown as chips.
- Copy (exact): "Practise this pattern"; "How it attaches"; "Building blocks ›"; "Usages" with "N of M at your levels" when some are hidden; hidden row "2 usages at a hidden level (N3)" / "1 usage at a hidden level (N3)" with "Show" / "Hide"; "Forms" with column heads "Polite" and "Casual"; "Common mistakes"; "Related"; list chips "By level" and "My course".

## Review Focus

1. A lesson with no attachment rules or no slots — no formula card, nothing empty on screen (Task 1, `testFormulaIsNilWithoutSlottedRules`; Task 2 draws nothing for nil).
2. An example where the pattern appears twice or not at all (conjugated past the ending, written in kanji) — first longest match underlined, or no underline (Task 1, `testHighlightPicksTheLongestFirstMatch`, `testHighlightIsNilWhenAbsent`).
3. A pitfall whose wrong form shares nothing with its example — the whole wrong form marked, not an empty range (Task 1, `testMistakeMarksEverythingWhenNothingIsShared`).
4. Forms with only one register, or more polite than casual rows — blank cells, no crash (Task 3, `ConjugationTable.rows` test `testRowsPadTheShorterColumn`).
5. AX5 text — the formula card wraps its chips, the forms table stacks its columns, nothing clips (Task 5, simulator check).

---

### Task 1: VerbKit helpers

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Grammar/GrammarHighlight.swift`, `Grammar/MistakeMark.swift`, `Grammar/GrammarFormula.swift`, `Grammar/AttachmentRule+Example.swift`, `Tests/VerbKitTests/GrammarRedesignTests.swift`
- Modify: `App/Grammar/AttachmentSection.swift` (use `AttachmentRule.example`)

**Interfaces:**
- Produces:
  - `public enum GrammarHighlight { static func patterns(of point: GrammarPoint) -> [String]; static func range(in text: String, patterns: [String]) -> Range<Int>? }` — patterns: each attachment rule's `then`, then the title split on `・`, with `〜` and spaces removed, distinct, longest first; range: character offsets of the first occurrence of the longest pattern found (ties: earliest), for `JapaneseText(_:emphasizing:)`.
  - `public enum MistakeMark { static func wrongRange(wrong: String, right: String?) -> Range<Int> }` — common prefix and suffix (by character, not overlapping); the middle of `wrong` is the wrong part; when it is empty (pure omission), or prefix+suffix is shorter than a third of `wrong`, or `right` is nil, the whole of `wrong`.
  - `public struct GrammarFormula: Equatable, Sendable { let slot: GrammarSlot; let endings: [String] }` and `public extension GrammarPoint { var formula: GrammarFormula? }` — the first rule with slots gives `slot` (its first slot); `endings` are the distinct `then` values of all slotted rules in order; nil when no rule has both slots and `then`.
  - `public extension AttachmentRule { func example(from pool: [SlotSource], eligible: [GrammarSlot: Set<String>], offset: Int) -> (base: String, built: String)? }` — exactly the logic now private in `AttachmentSection.example(_:)` (pool and per-slot eligible keys passed in).

- [ ] **Step 1: Failing tests** in `GrammarRedesignTests`, on the bundled grammar (`BundledData<GrammarDataFile>`):
  - `testHighlightPicksTheLongestFirstMatch`: patterns `["かもしれない", "かも"]`, text "雨が降るかもしれない。" → `4..<10`.
  - `testHighlightIsNilWhenAbsent`: "雨です。" with `["はず"]` → nil.
  - `testPatternsComeFromEndingsAndTitle`: a point titled "はず・かもしれない・わけ" whose rules end in はず → contains "はず", "かもしれない", "わけ", longest first.
  - `testMistakeMarksTheDifferingMiddle`: wrong "学生だかもしれない", right "学生かもしれない" → `2..<3`.
  - `testMistakeMarksEverythingWhenNothingIsShared`: wrong "静かだので", right "ぜんぜん違う文です" → `0..<5`; right nil → whole.
  - `testFormulaIsNilWithoutSlottedRules`: a point with no attachment → nil.
  - `testFormulaListsEveryEndingOnce`: a real lesson with several slotted rules (pick one from the data while writing) → `endings` distinct, in rule order.
  - `testExampleMatchesTheSectionsOldBehaviour`: for the ので lesson's verb rule, offset 0 with the bundled verbs → the same `(base, built)` the section produced (build it with the moved function; assert `built.hasSuffix("ので")`).
- [ ] **Step 2:** `cd Packages/VerbKit && swift test --filter GrammarRedesignTests` → FAIL to compile.
- [ ] **Step 3: Implement**; switch `AttachmentSection` to the shared `example`.
- [ ] **Step 4:** PASS; `make test-swift` all PASS; iOS build succeeds.
- [ ] **Step 5:** AGENTS.md rows for the four helpers. Commit — "VerbKit: what the grammar pages underline, mark and put in the formula".

### Task 2: Lesson header, formula card and practise

**Files:**
- Create: `App/Grammar/LessonHeader.swift`, `App/Grammar/FormulaCard.swift`
- Modify: `App/GrammarDetailView.swift` (header and practise move to the new views; `practiseSection` removed from the bottom)

**Interfaces:**
- Consumes: `GrammarPoint.formula`, `AttachmentRule.example` (Task 1).
- Produces: `struct LessonHeader: View { let point: GrammarPoint; let lesson: CourseLesson?; let onPractise: (() -> Void)? }`, `struct FormulaCard: View { let point: GrammarPoint; let formula: GrammarFormula }`.

- [ ] **Step 1: Header** — a row of `LevelBadge(range:emphasis: .header)`, "· N usages" when the lesson has more than one, and the course lesson name as an outlined capsule (no glass) with "unreviewed" beside it when so; `ReviewStatusPill` as now; the title in `Font.headword(.largeTitle)` through `JapaneseText`; keywords as outlined capsules in a `WrappingFlowLayout`; the summary through `JapaneseText` in `.headline` muted.
- [ ] **Step 2: Formula card** (genkō `paperCard(ruled: true)`): when `endings.count > 1`, `FilterChip`s to pick one (`@State selected`); then a line of a dashed-outline capsule with `formula.slot.title`, "+", and the selected ending in `Font.headword(.title)`; under it the live example of the first slotted rule whose `then` is the selected ending (`AttachmentRule.example`, offset 0) as `JapaneseText(built, emphasizing: <range of the ending in built>)` in `Font.sentence(.title3)`; "Building blocks ›" opens `BuildingBlocksSheet` as the section does today.
- [ ] **Step 3: Practise** — when `point.hasConnections`, a `.paper` "Practise this pattern" button right under the formula card (or under the header when there is no formula), running the existing connection-quiz action.
- [ ] **Step 4:** iOS and macOS builds succeed. Commit — "Grammar lesson: header with the formula card and practise".

### Task 3: How it attaches, usages and forms

**Files:**
- Create: `App/Grammar/LessonUsages.swift`, `App/Grammar/ConjugationTable.swift`
- Modify: `App/Grammar/AttachmentSection.swift`, `App/ExampleRow.swift` (an optional `highlight: Range<Int>?` and the W3 font), `App/GrammarDetailView.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/GrammarRedesignTests.swift` (the pairing below lives in VerbKit)

**Interfaces:**
- Produces: `public enum ConjugationTable { static func rows(_ conjugations: [GrammarConjugation]) -> [(polite: GrammarConjugation?, casual: GrammarConjugation?)] }` in `Packages/VerbKit/Sources/VerbKit/Grammar/ConjugationTable.swift` — the i-th polite beside the i-th casual (formal counts as polite, after the polite ones), padded with nil.

- [ ] **Step 1: Failing test** `testRowsPadTheShorterColumn`: 2 polite + 1 casual → 2 rows, second casual nil; only casual → polite nil. Run → FAIL; implement; PASS.
- [ ] **Step 2: How it attaches** — the section card becomes genkō (`ruled: true`); per word class one row: class name (with condition), the built example with the ending underlined, the note in muted; "Try another word" stays.
- [ ] **Step 3: Usages** (`LessonUsages`) — `SectionHeader("Usages")` with "N of M at your levels" as the trailing text when some are hidden; each usage a card with a numbered circle, the heading, a `LevelBadge` when the lesson mixes levels, the explanation, then its examples on one ruled card, each `ExampleRow(example:highlight: GrammarHighlight.range(in: example.jp, patterns: GrammarHighlight.patterns(of: point)))`; the hidden row as a dashed outline with the copy above and Show/Hide.
- [ ] **Step 4: Forms** — `SectionHeader("Forms")` and a card with "Polite" / "Casual" heads and `ConjugationTable.rows`, each cell `JapaneseText` with its note below in muted; at accessibility sizes (`ViewThatFits`) the columns stack.
- [ ] **Step 5:** `make test-swift` PASS; iOS and macOS builds succeed. Commit — "Grammar lesson: genkō attaches and examples, the forms table".

### Task 4: Common mistakes, contrasts and related

**Files:**
- Modify: `App/Grammar/CopulaCard.swift` (`WrongForm` gains `right: String?` and marks only `MistakeMark.wrongRange`), `App/GrammarDetailView.swift`

- [ ] **Step 1: Common mistakes** — `SectionHeader("Common mistakes")`; each pitfall a card: heading; `WrongForm(text: wrong, right: examples.first?.jp)` — ✕ glyph, the text in ink with only the wrong range in `palette.mark` and struck through, accessibility "Wrong: …"; then a ✓ line with the first example (ink, `palette.good` glyph); the explanation; remaining examples. The highlighted-pitfall outline uses `palette.button`, not `.tint`.
- [ ] **Step 2: Don't confuse with** — cards keep their content; examples use the ruled card and highlight like usages.
- [ ] **Step 3: Related** — rows like the list's (`GrammarRow` restyled in Task 5): Mincho title, `LevelBadge(range:)`, summary, `RowChevron`, opening `.grammar(id)`; no glass.
- [ ] **Step 4:** iOS and macOS builds succeed. Commit — "Grammar lesson: mistakes mark only the wrong part; related rows".

### Task 5: Grammar list, docs and checks

**Files:**
- Modify: `App/GrammarListView.swift`, `AGENTS.md`, `docs/superpowers/specs/2026-11-06-paper-ink-redesign-design.md` (a row "Grammar list and lesson (built)" under Boards → plans, noting the mockups)

- [ ] **Step 1: List** — the mode picker becomes two `FilterChip`s, "By level" and "My course"; Building blocks and Common mistakes become two side-by-side `paperCard`s at the top (title, one muted line: "Forms lessons attach to", "N slips, by theme"); By level groups lessons under `SectionHeader` per level (N5, N4…, "Other" for none) in `paperRow` cards; `GrammarRow`: title in `Font.headword(.title3)`, `LevelBadge(range:)`, summary one line muted through `JapaneseText`. Search, scope bar, hidden-matches row and My course stay as they are.
- [ ] **Step 2:** iOS and macOS builds succeed; `make test-swift` PASS; `make check-project` clean.
- [ ] **Step 3: Simulator** (iPhone 18 Pro): the list in light and dark; the はず・かもしれない・わけ lesson (formula chips switch the ending and example; Practise under it; usages with underlined examples and the hidden row Show/Hide with N3 hidden; forms table; a mistake with only だ red); a lesson without attachment rules (no formula card); the 可能形 lesson in the Dark theme; AX5 (Review Focus 5). Screenshots into the scratchpad.
- [ ] **Step 4:** Docs; commit — "Grammar list in the paper-and-ink look".
