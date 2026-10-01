# Verb Page Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the verb detail page as a short main page (one Plain / Polite Forms card and one More card of rows) with pushed sub-pages for each extended group, quiet system-secondary cards instead of glass tiles, and a weight-and-tone highlight of the part of each form that changed.

**Architecture:** A pure `FormSplit` in `VerbKit` splits a form into the stem it shares with the dictionary form and the ending that changed. In the app, one `FormTable` (with `FormCell`) draws every group; `VerbFormsCard` and `MoreRowsCard` form the main page; `PotentialPage`, `NdesuPage`, `AuxiliariesPage`, `AdvancedPage` and `VerbLessonsPage` are pushed through a `NavigationStack` that `VerbDetailView` owns. The five collapsible section views are deleted. No data or script change.

**Tech Stack:** Swift 5 language mode on Xcode 27 (SwiftPM tools 6.2), SwiftUI with Liquid Glass, XCTest; XcodeGen 2.46.

**Spec:** [docs/superpowers/specs/2026-10-01-verb-page-redesign-design.md](../specs/2026-10-01-verb-page-redesign-design.md), which builds on the grammar sub-project specs and the [native rewrite spec](../specs/2026-09-23-native-apple-rewrite-design.md) (read its section 10, the visual design direction).

**Verified against:** `main` at `1f01772` plus the spec commits on `feature/verb-page-redesign`. Every task below was executed on a scratch branch (one commit per task) with all tests passing, both app targets building, and the app run in the iOS Simulator on iPhone (the Forms card in light and dark, the More card, pushing and popping Potential and Auxiliaries, the Grammar list, and a lesson link switching tabs). **Not exercised on screen: iPad and macOS** (both build; the push inside the detail column is the thing to check there). The test count per task comes from those runs. **If `main` has moved, run Task 0 Step 2 first.**

## Global Constraints

- Deployment target: **iOS 26 / macOS 26**, Swift language mode 5. Do not lower it.
- **Patch existing files; never replace them wholesale.** Modified files are given as diffs against `1f01772`; new files are given in full. Apply diffs with `git apply --3way`, or make the equivalent edit by hand if the surrounding code has moved.
- App-only change: `data/`, `scripts/`, the lessons, the quiz and the Examples sheet are **not** touched. `formLabels` (`App/FormLabels.swift`) stays as it is, because the quiz uses it.
- **Visual system (spec §2):** the glass tiles inside groups go. Groups are cards on the system secondary background (`.background.secondary`). Glass stays for the Examples / Test / Jisho buttons, the **Learn about …** link buttons (`.glass`), the type pill, the notes callout and the system bars. **No accessibility-specific modifiers** (`.accessibilityLabel`, `.accessibilityHint`, …).
- **Highlight (spec §2):** in every form cell, the longest common prefix with the kana dictionary form is the stem (regular weight, `.secondary`) and the rest is the ending (bold, `.primary`). No shared prefix: the whole form is bold (くる, する). Identical to the dictionary form: normal text. No colour, no underline (the ru-verb accent is blue and would read as a link).
- **Rows and pages (spec §1):** the More card has rows for Potential, んです, Auxiliaries, Advanced and Grammar, each hidden when the verb has none of that group's forms (Advanced never shows today; no verb has those forms). ある has no Potential row and its Auxiliaries page shows only the stem rows and ながら. The Grammar row hides until grammar has synced, and each **Learn about …** link hides until its lesson has synced. Lesson links still call `openRoute`, which switches to the Grammar tab.
- **Navigation (spec §1):** a plain `NavigationLink` in the split view's detail column does **not** push (checked while building this), so `VerbDetailView` owns a `NavigationStack` with `navigationDestination(for: VerbSubPage.self)`, keyed on the verb's id (`.id(verb.id)`).
- Out of scope: long-press actions, Jisho and translation links (saved as follow-ups), highlighting on the Examples sheet, the lessons or the quiz, any data change (spec, "Not in this redesign").
- Any `git push` to the GitHub remote requires explicit user confirmation at execution time. Do not push without asking first.

---

## Task 0: Baseline

**Files:** none.

- [ ] **Step 1: Start from the spec branch and record the baseline**

```bash
git worktree add -b feature/verb-page-redesign-impl .claude/worktrees/verb-page-redesign-impl feature/verb-page-redesign
cd .claude/worktrees/verb-page-redesign-impl
git log -1 --format=%h
(cd Packages/VerbKit && swift test 2>&1 | grep -E "error:|failed|Executed .* tests" | tail -1)
python3 -m unittest discover -s scripts -p "test_*.py" 2>&1 | tail -2
python3 scripts/update_data.py --check
```

Expected: a short hash, `Executed 197 tests, with 0 failures`, `Ran 85 tests ... OK`, and `data is up to date`. Every count below is relative to these. (If `feature/verb-page-redesign` has already been merged or deleted, branch from `main` instead.) Run these from the main repository root so the worktree is not nested inside another one.

- [ ] **Step 2: If `main` is newer than `1f01772`, see what it touched**

```bash
git diff --name-only 1f01772 main -- . ':!docs' ':!*.png' | cat
```

Expected: nothing. If files appear and any is one this plan modifies or deletes (`VerbDetailView.swift`, the five section views), read that diff before applying the matching diff below and adapt instead of overwriting.

---

## Task 1: `FormSplit`

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Forms/FormSplit.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/FormSplitTests.swift`, `Packages/VerbKit/Tests/VerbKitTests/RealFormSplitTests.swift`

**Interfaces:**
- Produces: `FormSplit(stem:ending:)` (`Equatable`, `Sendable`), `FormSplit.hasEnding: Bool`, and `FormSplit.split(_ form: String, from dict: String) -> FormSplit`. Used by Task 2.

- [ ] **Step 1: Write the failing tests**

`Packages/VerbKit/Tests/VerbKitTests/FormSplitTests.swift` has hand-written cases (ru-verbs, u-verbs, the irregular verbs, an identical form, a form that extends the dictionary form, empty inputs). Note that する has no shared prefix with しま… because する starts with す:

```swift
import XCTest
@testable import VerbKit

final class FormSplitTests: XCTestCase {
    private func split(_ form: String, _ dict: String) -> FormSplit {
        FormSplit.split(form, from: dict)
    }

    func testARuVerbKeepsItsStem() {
        XCTAssertEqual(split("たべられる", "たべる"), FormSplit(stem: "たべ", ending: "られる"))
        XCTAssertEqual(split("たべます", "たべる"), FormSplit(stem: "たべ", ending: "ます"))
        XCTAssertEqual(split("たべていた", "たべる"), FormSplit(stem: "たべ", ending: "ていた"))
    }

    func testAUVerbKeepsOnlyTheLettersBeforeTheChangingKana() {
        XCTAssertEqual(split("のめる", "のむ"), FormSplit(stem: "の", ending: "める"))
        XCTAssertEqual(split("のみます", "のむ"), FormSplit(stem: "の", ending: "みます"))
        XCTAssertEqual(split("のんでいる", "のむ"), FormSplit(stem: "の", ending: "んでいる"))
        XCTAssertEqual(split("かって", "かう"), FormSplit(stem: "か", ending: "って"))
        XCTAssertEqual(split("いって", "いく"), FormSplit(stem: "い", ending: "って"))
    }

    func testIrregularVerbs() {
        // No shared prefix (する starts with す, しま with し): the whole form is the ending.
        XCTAssertEqual(split("します", "する"), FormSplit(stem: "", ending: "します"))
        XCTAssertEqual(split("した", "する"), FormSplit(stem: "", ending: "した"))
        XCTAssertEqual(split("きます", "くる"), FormSplit(stem: "", ending: "きます"))
        XCTAssertEqual(split("できる", "する"), FormSplit(stem: "", ending: "できる"))
    }

    func testAFormIdenticalToTheDictionaryFormHasNoEnding() {
        let result = split("たべる", "たべる")
        XCTAssertEqual(result, FormSplit(stem: "たべる", ending: ""))
        XCTAssertFalse(result.hasEnding)
    }

    func testAFormThatExtendsTheDictionaryFormKeepsItAsTheStem() {
        XCTAssertEqual(split("たべるんです", "たべる"), FormSplit(stem: "たべる", ending: "んです"))
    }

    func testAnEmptyFormAndAnEmptyDictionaryForm() {
        XCTAssertEqual(split("", "たべる"), FormSplit(stem: "", ending: ""))
        XCTAssertEqual(split("たべる", ""), FormSplit(stem: "", ending: "たべる"))
    }

    func testHasEndingIsTrueWhenSomethingChanged() {
        XCTAssertTrue(split("たべない", "たべる").hasEnding)
        XCTAssertTrue(split("きます", "くる").hasEnding)
    }
}
```

`Packages/VerbKit/Tests/VerbKitTests/RealFormSplitTests.swift` splits every form of every verb in the real `data/verbs.json` and checks that the pieces rebuild the form, that the stem always belongs to the dictionary form, and that only the dictionary form itself has no ending:

```swift
import XCTest
@testable import VerbKit

/// Splits every form of every verb in the real `data/verbs.json` and checks the
/// pieces always rebuild the form and the stem always belongs to the dictionary form.
final class RealFormSplitTests: XCTestCase {
    private func loadVerbs() throws -> [Verb] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // VerbKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // VerbKit
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("data")
            .appendingPathComponent("verbs.json")
        return try JSONDecoder().decode(VerbDataFile.self, from: Data(contentsOf: url)).verbs
    }

    /// Every populated form string on a verb, via its JSON representation.
    private func allForms(of verb: Verb) throws -> [String] {
        let data = try JSONEncoder().encode(verb.forms)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        return Array(object.values)
    }

    func testStemPlusEndingAlwaysRebuildsTheForm() throws {
        var checked = 0
        for verb in try loadVerbs() {
            for form in try allForms(of: verb) {
                let split = FormSplit.split(form, from: verb.dict)
                XCTAssertEqual(split.stem + split.ending, form, "\(verb.dict): \(form)")
                XCTAssertTrue(verb.dict.hasPrefix(split.stem), "\(verb.dict): \(form) stem \(split.stem)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 25 * 40)
    }

    func testOnlyTheDictionaryFormItselfHasNoEnding() throws {
        for verb in try loadVerbs() {
            for form in try allForms(of: verb) where !FormSplit.split(form, from: verb.dict).hasEnding {
                XCTAssertEqual(form, verb.dict, "\(verb.dict) has a form with no ending: \(form)")
            }
        }
    }

    func testWellKnownSplits() throws {
        let verbs = try loadVerbs()
        func forms(_ dict: String) throws -> VerbForms {
            try XCTUnwrap(verbs.first { $0.dict == dict }, dict).forms
        }
        XCTAssertEqual(FormSplit.split(try forms("たべる").potential!, from: "たべる"), FormSplit(stem: "たべ", ending: "られる"))
        XCTAssertEqual(FormSplit.split(try forms("のむ").potential!, from: "のむ"), FormSplit(stem: "の", ending: "める"))
        XCTAssertEqual(FormSplit.split(try forms("くる").masuPos, from: "くる"), FormSplit(stem: "", ending: "きます"))
        XCTAssertEqual(FormSplit.split(try forms("する").potential!, from: "する"), FormSplit(stem: "", ending: "できる"))
        XCTAssertEqual(FormSplit.split(try forms("たべる").shortPos, from: "たべる").hasEnding, false)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd Packages/VerbKit && swift test --filter FormSplit 2>&1 | grep -E "error:" | head -2
```

Expected: `cannot find 'FormSplit' in scope`.

- [ ] **Step 3: Implement**

`Packages/VerbKit/Sources/VerbKit/Forms/FormSplit.swift`:

```swift
/// A conjugated form split into the part it shares with the dictionary form (the
/// stem) and the part that changed (the ending). The verb page shows the stem in
/// grey and the ending in bold.
public struct FormSplit: Equatable, Sendable {
    public let stem: String
    public let ending: String

    public init(stem: String, ending: String) {
        self.stem = stem
        self.ending = ending
    }

    /// True when something changed, so the cell has an ending to emphasise.
    /// A form identical to the dictionary form has none.
    public var hasEnding: Bool { !ending.isEmpty }

    /// The longest common prefix of `form` and `dict` is the stem and the rest of
    /// `form` is the ending. No shared prefix (くる → きます) makes the whole form
    /// the ending; an identical form (たべる → たべる) has an empty ending.
    public static func split(_ form: String, from dict: String) -> FormSplit {
        var shared = 0
        for (a, b) in zip(form, dict) {
            guard a == b else { break }
            shared += 1
        }
        return FormSplit(stem: String(form.prefix(shared)), ending: String(form.dropFirst(shared)))
    }
}
```

- [ ] **Step 4: Run the whole suite to verify it passes**

```bash
cd Packages/VerbKit && swift test 2>&1 | grep -E "error:|failed|Executed .* tests" | tail -1
```

Expected: `Executed 207 tests, with 0 failures` (197 baseline plus 10 new).

- [ ] **Step 5: Commit**

```bash
git add Packages/VerbKit
git commit -m "$(cat <<'EOF'
Add FormSplit: the stem a form shares with its dictionary form

The longest common prefix with the kana dictionary form is the stem and the
rest is the ending, which the verb page will show in grey and bold.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: The table component and the Forms card

**Files:**
- Create: `App/FormCell.swift`, `App/FormTable.swift`, `App/VerbFormsCard.swift`
- Modify: `App/VerbDetailView.swift`

**Interfaces:**
- Consumes: `FormSplit` (Task 1).
- Produces: `FormCell(form:dict:)`; `FormTableRow(label:values:)` with `values: [String?]` (a `nil` leaves the cell empty); `FormTable(columns:rows:dict:)`; `View.formCard()` (the quiet card surface); `VerbFormsCard(verb:)`. Used by Tasks 3 and 4.

- [ ] **Step 1: Create the components**

`App/FormCell.swift`. The stem is regular weight and `.secondary`, the ending bold and `.primary`, joined as one `Text` so it wraps and scales like ordinary text; a form with no ending is drawn normally:

```swift
import SwiftUI
import VerbKit

/// One conjugated form in a table. The part shared with the dictionary form is
/// light grey and the part that changed is bold, with no colour so nothing reads
/// as a link. A form identical to the dictionary form is drawn normally.
struct FormCell: View {
    let form: String
    let dict: String

    var body: some View {
        let split = FormSplit.split(form, from: dict)
        Group {
            if split.hasEnding {
                Text(split.stem).fontWeight(.regular).foregroundStyle(.secondary)
                    + Text(split.ending).fontWeight(.bold).foregroundStyle(.primary)
            } else {
                Text(form)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}
```

`App/FormTable.swift`. A `Grid` with bold column headers, a caption and the values per row, hairline `Divider`s between rows, on the `formCard()` surface (`.background.secondary`):

```swift
import SwiftUI
import VerbKit

/// One row of a `FormTable`: a caption and a value per column. A `nil` value
/// leaves its cell empty (for example the て-form has no polite value).
struct FormTableRow: Identifiable {
    let label: String
    let values: [String?]
    var id: String { label }
}

/// The table every group of forms is drawn with: bold column headers, then a row
/// per form with a caption on the left, the values on the right and hairline
/// separators, on a quiet system-secondary card.
struct FormTable: View {
    let columns: [String]
    let rows: [FormTableRow]
    /// The verb's kana dictionary form, which the cells compare each form with.
    let dict: String

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("")
                ForEach(columns, id: \.self) { column in
                    Text(column)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(rows) { row in
                Divider()
                GridRow {
                    Text(row.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(Array(row.values.enumerated()), id: \.offset) { _, value in
                        if let value {
                            FormCell(form: value, dict: dict)
                                .font(.body)
                        } else {
                            Text("")
                        }
                    }
                }
            }
        }
        .formCard()
    }
}

extension View {
    /// The quiet card surface for groups of forms: the system's secondary
    /// background, which adapts to light and dark on iOS and macOS.
    func formCard() -> some View {
        self
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }
}
```

`App/VerbFormsCard.swift`. The everyday forms in one Plain / Polite table:

```swift
import SwiftUI
import VerbKit

/// The everyday forms in one Plain / Polite table: present and past, positive and
/// negative, and the て-form.
struct VerbFormsCard: View {
    let verb: Verb

    private var rows: [FormTableRow] {
        let f = verb.forms
        return [
            FormTableRow(label: "present +", values: [f.shortPos, f.masuPos]),
            FormTableRow(label: "present −", values: [f.shortNeg, f.masuNeg]),
            FormTableRow(label: "past +", values: [f.shortPast, f.masuPast]),
            FormTableRow(label: "past −", values: [f.shortPastNeg, f.masuPastNeg]),
            FormTableRow(label: "て-form", values: [f.te, nil]),
        ]
    }

    var body: some View {
        FormTable(columns: ["Plain", "Polite"], rows: rows, dict: verb.dict)
    }
}
```

- [ ] **Step 2: Use the card on the verb page**

Apply this diff to `App/VerbDetailView.swift`. It replaces the Polite, Plain and て-form collapsible groups with the one card (the other groups stay for now):

```diff
diff --git a/App/VerbDetailView.swift b/App/VerbDetailView.swift
index 301a3c3..701d59f 100644
--- a/App/VerbDetailView.swift
+++ b/App/VerbDetailView.swift
@@ -86,23 +86,7 @@ struct VerbDetailView: View {
 
     private var formGroups: some View {
         VStack(alignment: .leading, spacing: 16) {
-            FormGroupSection(title: "Polite", forms: [
-                ("ます (polite +)", verb.forms.masuPos),
-                ("ません (polite −)", verb.forms.masuNeg),
-                ("ました (polite past +)", verb.forms.masuPast),
-                ("ませんでした (polite past −)", verb.forms.masuPastNeg),
-            ], defaultExpanded: true)
-
-            FormGroupSection(title: "Plain", forms: [
-                ("short (present +)", verb.forms.shortPos),
-                ("short (present −)", verb.forms.shortNeg),
-                ("short (past +)", verb.forms.shortPast),
-                ("short (past −)", verb.forms.shortPastNeg),
-            ], defaultExpanded: true)
-
-            FormGroupSection(title: "て-form", forms: [
-                ("て-form", verb.forms.te),
-            ], defaultExpanded: true)
+            VerbFormsCard(verb: verb)
 
             if verb.forms.hasPotentialForms {
                 PotentialFormsSection(forms: verb.forms)
```

- [ ] **Step 3: Build both platforms**

```bash
./scripts/generate-project.sh
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_macOS -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
```

Expected: `** BUILD SUCCEEDED **` twice.

- [ ] **Step 4: Look at it in the iOS Simulator**

The app reads its data from GitHub `main`, which already has everything this page needs, so no local server is required. **Use a unique bundle id**, so your install and its saved sync state cannot collide with another session's build of the same app (a collision shows up as a bogus "Something Went Wrong" screen):

```bash
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/rdcheck CODE_SIGNING_ALLOWED=NO PRODUCT_BUNDLE_IDENTIFIER=dev.martinloeseth.jpverbconjugation.rdcheck build 2>&1 | tail -3
xcrun simctl uninstall booted dev.martinloeseth.jpverbconjugation.rdcheck
```

Then install and launch `/tmp/rdcheck/Build/Products/Debug-iphonesimulator/JP Verb Conjugation.app` with the iOS Simulator tool, passing that bundle id. Uninstall between runs (the same command as above): with no App Group the store is in memory but sync state persists, so a relaunch would report "up to date" with no data.

Expected, on **Verbs → たべる**: under the description, one card with **Plain** and **Polite** column headers and rows present +, present −, past +, past −, and て-form. The stem (たべ) is grey and the ending is bold in every cell: たべ**ます**, たべ**ない**, たべ**ませんでした**, たべ**て**. The Plain present たべる is normal black, because it equals the dictionary form, and the て-form row has only a Plain value. The card is a flat light grey, with no glass. Switch the simulator to dark (`xcrun simctl ui booted appearance dark`), check that the grey stem is still readable, then put it back to `light` (the simulator may be shared with other sessions). The old Potential, んです, Auxiliaries and Grammar groups still appear below, unchanged.

- [ ] **Step 5: Clean up and commit**

```bash
xcrun simctl uninstall booted dev.martinloeseth.jpverbconjugation.rdcheck
git status --short                       # only the App/ files of this task
git add App
git commit -m "$(cat <<'EOF'
Add FormTable and the Plain / Polite Forms card

One table component for every group of forms, on a quiet system-secondary
card. The part of each form shared with the dictionary form is grey and the
part that changed is bold, with no colour so nothing reads as a link. The
Polite, Plain and て-form groups on the verb page become one card.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: The More card, the Potential and んです pages, and the detail stack

**Files:**
- Create: `App/VerbSubPage.swift`, `App/LessonLinks.swift`, `App/PotentialPage.swift`, `App/NdesuPage.swift`, `App/MoreRowsCard.swift`
- Modify: `App/VerbDetailView.swift`
- Delete: `App/PotentialFormsSection.swift`, `App/NdesuFormsSection.swift`

**Interfaces:**
- Consumes: `FormTable`, `FormTableRow`, `formCard()` (Task 2), `VerbStore.grammarPoints`, `openRoute`, `JapaneseText`, `GrammarPoint.potentialID` / `nDesuID`.
- Produces: `enum VerbSubPage: Hashable` (`potential`, `nDesu`, `auxiliaries`, `advanced`, `lessons`, with `title`); `LessonLinks(ids:)` (a full-width glass **Learn about …** button per lesson that has synced, in the order given); `PotentialPage(verb:)`, `NdesuPage(verb:)`; `MoreRowsCard(verb:)` (rows that push `VerbSubPage` values; so far only Potential and んです); and a `NavigationStack` in `VerbDetailView`. Task 4 extends `MoreRowsCard` and the destination switch.

- [ ] **Step 1: Create the pages and the card**

`App/VerbSubPage.swift`:

```swift
import Foundation

/// The pages a verb's "More" card pushes.
enum VerbSubPage: Hashable {
    case potential
    case nDesu
    case auxiliaries
    case advanced
    case lessons

    var title: String {
        switch self {
        case .potential: "Potential"
        case .nDesu: "んです"
        case .auxiliaries: "Auxiliaries"
        case .advanced: "Advanced"
        case .lessons: "Grammar"
        }
    }
}
```

`App/LessonLinks.swift`. Each button's label has `maxWidth: .infinity`; without it the ruby label has no width to flow into and wraps ("Learn about" above 可能形):

```swift
import SwiftUI
import VerbKit

/// "Learn about …" buttons for the given lessons, in the given order. A lesson
/// that has not synced yet shows no button, so a link never dead-ends.
struct LessonLinks: View {
    let ids: [String]
    @Environment(VerbStore.self) private var verbStore
    @Environment(\.openRoute) private var openRoute

    private var lessons: [GrammarPoint] {
        ids.compactMap { id in
            verbStore.grammarPoints.first { $0.id == id }
        }
    }

    var body: some View {
        ForEach(lessons) { lesson in
            Button {
                openRoute(.grammar(lesson.id))
            } label: {
                Label {
                    JapaneseText("Learn about \(lesson.title)")
                } icon: {
                    Image(systemName: "arrow.right.circle")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.glass)
            .font(.subheadline)
        }
    }
}
```

`App/PotentialPage.swift`:

```swift
import SwiftUI
import VerbKit

/// The verb's nine potential forms, plain and polite, and the link to the lesson.
struct PotentialPage: View {
    let verb: Verb

    private var rows: [FormTableRow] {
        let f = verb.forms
        return [
            FormTableRow(label: "present +", values: [f.potential, f.potMasuPos]),
            FormTableRow(label: "present −", values: [f.potShortNeg, f.potMasuNeg]),
            FormTableRow(label: "past +", values: [f.potShortPast, f.potMasuPast]),
            FormTableRow(label: "past −", values: [f.potShortPastNeg, f.potMasuPastNeg]),
            FormTableRow(label: "て-form", values: [f.potTe, nil]),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FormTable(columns: ["Plain", "Polite"], rows: rows, dict: verb.dict)
                LessonLinks(ids: [GrammarPoint.potentialID])
            }
            .padding()
        }
        .navigationTitle(VerbSubPage.potential.title)
    }
}
```

`App/NdesuPage.swift`:

```swift
import SwiftUI
import VerbKit

/// The verb's んです forms, polite and casual, and the link to the lesson.
struct NdesuPage: View {
    let verb: Verb

    private var rows: [FormTableRow] {
        let f = verb.forms
        return [
            FormTableRow(label: "present +", values: [f.ndPos, f.ndCasualPos]),
            FormTableRow(label: "present −", values: [f.ndNeg, f.ndCasualNeg]),
            FormTableRow(label: "past +", values: [f.ndPast, f.ndCasualPast]),
            FormTableRow(label: "past −", values: [f.ndPastNeg, f.ndCasualPastNeg]),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FormTable(columns: ["Polite", "Casual"], rows: rows, dict: verb.dict)
                LessonLinks(ids: [GrammarPoint.nDesuID])
            }
            .padding()
        }
        .navigationTitle(VerbSubPage.nDesu.title)
    }
}
```

`App/MoreRowsCard.swift`. A row per extended group the verb has, each a `NavigationLink(value:)` with the group's name, a preview form and a chevron, drawn on one card with hairlines between:

```swift
import SwiftUI
import VerbKit

/// The extended groups as rows that push their own page, each previewing one
/// form. A row is left out when the verb has none of that group's forms.
struct MoreRowsCard: View {
    let verb: Verb

    private struct Row: Identifiable {
        let page: VerbSubPage
        let preview: String
        var id: VerbSubPage { page }
    }

    private var rows: [Row] {
        let f = verb.forms
        var rows: [Row] = []
        if f.hasPotentialForms, let preview = f.potential {
            rows.append(Row(page: .potential, preview: preview))
        }
        if f.hasNdForms, let preview = f.ndPos {
            rows.append(Row(page: .nDesu, preview: preview))
        }
        return rows
    }

    var body: some View {
        if !rows.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider() }
                    NavigationLink(value: row.page) {
                        HStack {
                            Text(row.page.title)
                            Spacer()
                            Text(row.preview).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .formCard()
        }
    }
}
```

- [ ] **Step 2: Wire the page and delete the old sections**

Apply this diff to `App/VerbDetailView.swift`. It wraps the page in a `NavigationStack` keyed on the verb (a plain `NavigationLink` does not push in the split view's detail column), adds the destinations, shows the More card, and removes the Potential and んです groups:

```diff
diff --git a/App/VerbDetailView.swift b/App/VerbDetailView.swift
index 701d59f..2eaa6dd 100644
--- a/App/VerbDetailView.swift
+++ b/App/VerbDetailView.swift
@@ -22,20 +22,33 @@ struct VerbDetailView: View {
     }
 
     var body: some View {
-        ScrollView {
-            VStack(alignment: .leading, spacing: 20) {
-                header
-                actions
-                if let notes = verb.notes {
-                    notesBox(notes)
+        // The detail column of a split view does not push navigation links by
+        // itself, so the page owns a stack. Keyed on the verb, so choosing
+        // another verb returns to the main page.
+        NavigationStack {
+            ScrollView {
+                VStack(alignment: .leading, spacing: 20) {
+                    header
+                    actions
+                    if let notes = verb.notes {
+                        notesBox(notes)
+                    }
+                    JapaneseText(verb.description)
+                        .font(.body)
+                    formGroups
+                }
+                .padding()
+            }
+            .navigationTitle(verb.dict)
+            .navigationDestination(for: VerbSubPage.self) { page in
+                switch page {
+                case .potential: PotentialPage(verb: verb)
+                case .nDesu: NdesuPage(verb: verb)
+                case .auxiliaries, .advanced, .lessons: EmptyView()
                 }
-                JapaneseText(verb.description)
-                    .font(.body)
-                formGroups
             }
-            .padding()
         }
-        .navigationTitle(verb.dict)
+        .id(verb.id)
     }
 
     private var header: some View {
@@ -88,9 +101,7 @@ struct VerbDetailView: View {
         VStack(alignment: .leading, spacing: 16) {
             VerbFormsCard(verb: verb)
 
-            if verb.forms.hasPotentialForms {
-                PotentialFormsSection(forms: verb.forms)
-            }
+            MoreRowsCard(verb: verb)
 
             if hasAdvancedForms {
                 FormGroupSection(
@@ -109,10 +120,6 @@ struct VerbDetailView: View {
                 )
             }
 
-            if verb.forms.hasNdForms {
-                NdesuFormsSection(forms: verb.forms)
-            }
-
             if verb.forms.hasAuxiliaryForms {
                 AuxiliaryFormsSection(forms: verb.forms)
             }
```

```bash
git rm App/PotentialFormsSection.swift App/NdesuFormsSection.swift
```

- [ ] **Step 3: Build both platforms**

```bash
./scripts/generate-project.sh
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_macOS -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
```

Expected: `** BUILD SUCCEEDED **` twice.

- [ ] **Step 4: Check the push in the iOS Simulator**

Build and launch as in Task 2 Step 4 (unique bundle id `…rdcheck`, uninstall between runs). The page scrolls and re-lays out after a tap, so take a fresh screenshot before each tap. Expected, on **Verbs → たべる**:
- Below the Forms card there is a **More** card with two rows: **Potential** (preview たべられる) and **んです** (preview たべるんです), each with a chevron. The old Auxiliaries and Grammar groups still appear below it.
- Tapping **Potential** pushes a page titled **Potential**: a Plain / Polite table of nine forms (たべられる / たべられます … たべられて, with the ending られる… bold), the longest cell たべられませんでした fitting without wrapping, then a full-width **Learn about 可能形** button on one line with かのうけい above 可能形. Back returns to the verb page. Repeat for **んです** (columns Polite and Casual).
- Choosing another verb from the list while a sub-page is open returns to that verb's main page.

- [ ] **Step 5: Clean up and commit**

```bash
xcrun simctl uninstall booted dev.martinloeseth.jpverbconjugation.rdcheck
git status --short                       # only the App/ files of this task
git add App
git commit -m "$(cat <<'EOF'
Add the More card and the Potential and んです pages

Extended groups become rows that push their own page, each drawn with the
same table. The detail owns a NavigationStack keyed on the verb, because a
plain NavigationLink does not push in a split view's detail column. The
Potential and んです collapsible groups are removed.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: The Auxiliaries, Advanced and Grammar pages

**Files:**
- Create: `App/AuxiliariesPage.swift`, `App/AdvancedPage.swift`, `App/VerbLessonsPage.swift`
- Modify: `App/MoreRowsCard.swift`, `App/VerbDetailView.swift`
- Delete: `App/AuxiliaryFormsSection.swift`, `App/VerbGrammarSection.swift`, `App/FormGroupSection.swift`

**Interfaces:**
- Consumes: Task 3's `VerbSubPage`, `LessonLinks`, `MoreRowsCard`, the destination switch; `GrammarPoint.attachingToVerbs` and `VerbForms.hasAuxiliaryForms`.
- Produces: `AuxiliariesPage(verb:)`, `AdvancedPage(verb:)` (with `VerbForms.hasAdvancedForms`), `VerbLessonsPage()`, and the complete More card (Potential, んです, Auxiliaries, Advanced, Grammar).

- [ ] **Step 1: Create the pages**

`App/AuxiliariesPage.swift`. The ている table (when the verb has it), a second table with a row per other auxiliary (ながら has no polite value), and the four lesson links. For ある the ている table and the て-form rows are absent, so only the stem rows and ながら show:

```swift
import SwiftUI
import VerbKit

/// The verb's auxiliary forms: ている in full, then a row per other auxiliary,
/// and the four lesson links. A verb with no て-form auxiliaries (ある) shows only
/// the stem-based rows.
struct AuxiliariesPage: View {
    let verb: Verb

    private var teiruRows: [FormTableRow] {
        let f = verb.forms
        guard f.teiru != nil else { return [] }
        return [
            FormTableRow(label: "present +", values: [f.teiru, f.teiruMasuPos]),
            FormTableRow(label: "present −", values: [f.teiruNeg, f.teiruMasuNeg]),
            FormTableRow(label: "past +", values: [f.teiruPast, f.teiruMasuPast]),
            FormTableRow(label: "past −", values: [f.teiruPastNeg, f.teiruMasuPastNeg]),
            FormTableRow(label: "て-form", values: [f.teiruTe, nil]),
        ]
    }

    /// One row per auxiliary the verb has, in teaching order.
    private var otherRows: [FormTableRow] {
        let f = verb.forms
        let all: [(String, String?, String?)] = [
            ("てしまう", f.teshimau, f.teshimauPolite),
            ("ておく", f.teoku, f.teokuPolite),
            ("てみる", f.temiru, f.temiruPolite),
            ("ながら", f.nagara, nil),
            ("すぎる", f.sugiru, f.sugiruPolite),
            ("やすい", f.yasui, f.yasuiPolite),
            ("にくい", f.nikui, f.nikuiPolite),
        ]
        return all.compactMap { label, plain, polite in
            plain.map { FormTableRow(label: label, values: [$0, polite]) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !teiruRows.isEmpty {
                    Text("ている")
                        .font(.headline)
                    FormTable(columns: ["Plain", "Polite"], rows: teiruRows, dict: verb.dict)
                }
                Text("Others")
                    .font(.headline)
                FormTable(columns: ["Plain", "Polite"], rows: otherRows, dict: verb.dict)
                LessonLinks(ids: ["teiru", "teshimau", "temiru", "sugiru"])
            }
            .padding()
        }
        .navigationTitle(VerbSubPage.auxiliaries.title)
    }
}
```

`App/AdvancedPage.swift`. A one-column table of whichever optional advanced forms the verb has, plus the `hasAdvancedForms` helper. No verb has these forms today, so the row that opens this page never shows yet:

```swift
import SwiftUI
import VerbKit

/// The optional advanced forms (volitional, passive, causative, conditionals,
/// imperative, たい). No verb in the data has them yet, so the row that opens
/// this page stays hidden until one does.
struct AdvancedPage: View {
    let verb: Verb

    private var rows: [FormTableRow] {
        let f = verb.forms
        let all: [(String, String?)] = [
            ("Volitional", f.volitional),
            ("Passive", f.passive),
            ("Causative", f.causative),
            ("Causative-passive", f.causativePassive),
            ("Conditional (ば)", f.conditionalBa),
            ("Conditional (たら)", f.conditionalTara),
            ("Imperative", f.imperative),
            ("たい (want to)", f.tai),
        ]
        return all.compactMap { label, value in
            value.map { FormTableRow(label: label, values: [$0]) }
        }
    }

    var body: some View {
        ScrollView {
            FormTable(columns: ["Form"], rows: rows, dict: verb.dict)
                .padding()
        }
        .navigationTitle(VerbSubPage.advanced.title)
    }
}

extension VerbForms {
    /// True when at least one advanced form is populated.
    var hasAdvancedForms: Bool {
        [volitional, passive, causative, causativePassive, conditionalBa, conditionalTara, imperative, tai]
            .contains { $0 != nil }
    }
}
```

`App/VerbLessonsPage.swift`. Every lesson that attaches to verbs, one row each, opening it through `openRoute`:

```swift
import SwiftUI
import VerbKit

/// Every lesson that attaches to verbs, one row each, opening the lesson in the
/// Grammar tab. Driven by the lesson data, so lessons added later appear on
/// their own.
struct VerbLessonsPage: View {
    @Environment(VerbStore.self) private var verbStore
    @Environment(\.openRoute) private var openRoute

    private var lessons: [GrammarPoint] {
        verbStore.grammarPoints.attachingToVerbs
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(lessons.enumerated()), id: \.element.id) { index, lesson in
                    if index > 0 { Divider() }
                    Button {
                        openRoute(.grammar(lesson.id))
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            JapaneseText(lesson.title)
                                .font(.headline)
                            JapaneseText(lesson.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .formCard()
            .padding()
        }
        .navigationTitle(VerbSubPage.lessons.title)
    }
}
```

- [ ] **Step 2: Finish the More card and the page, and delete the old sections**

Apply these diffs. The first adds the Auxiliaries, Advanced and Grammar rows (the Grammar row shows "N lessons" and hides until grammar has synced); the second routes the new pages and reduces the page to the two cards:

```diff
diff --git a/App/MoreRowsCard.swift b/App/MoreRowsCard.swift
index 7aa385c..3e6c2d4 100644
--- a/App/MoreRowsCard.swift
+++ b/App/MoreRowsCard.swift
@@ -5,6 +5,7 @@ import VerbKit
 /// form. A row is left out when the verb has none of that group's forms.
 struct MoreRowsCard: View {
     let verb: Verb
+    @Environment(VerbStore.self) private var verbStore
 
     private struct Row: Identifiable {
         let page: VerbSubPage
@@ -21,6 +22,16 @@ struct MoreRowsCard: View {
         if f.hasNdForms, let preview = f.ndPos {
             rows.append(Row(page: .nDesu, preview: preview))
         }
+        if f.hasAuxiliaryForms, let preview = f.teiru ?? f.nagara {
+            rows.append(Row(page: .auxiliaries, preview: preview))
+        }
+        if f.hasAdvancedForms, let preview = f.volitional ?? f.tai ?? f.imperative {
+            rows.append(Row(page: .advanced, preview: preview))
+        }
+        let lessonCount = verbStore.grammarPoints.attachingToVerbs.count
+        if lessonCount > 0 {
+            rows.append(Row(page: .lessons, preview: "\(lessonCount) lessons"))
+        }
         return rows
     }
 
```

```diff
diff --git a/App/VerbDetailView.swift b/App/VerbDetailView.swift
index 2eaa6dd..fbca125 100644
--- a/App/VerbDetailView.swift
+++ b/App/VerbDetailView.swift
@@ -15,12 +15,6 @@ struct VerbDetailView: View {
         return URL(string: "https://jisho.org/search/\(encoded)")!
     }
 
-    private var hasAdvancedForms: Bool {
-        let f = verb.forms
-        return [f.volitional, f.passive, f.causative, f.causativePassive, f.conditionalBa, f.conditionalTara, f.imperative, f.tai]
-            .contains { $0 != nil }
-    }
-
     var body: some View {
         // The detail column of a split view does not push navigation links by
         // itself, so the page owns a stack. Keyed on the verb, so choosing
@@ -44,7 +38,9 @@ struct VerbDetailView: View {
                 switch page {
                 case .potential: PotentialPage(verb: verb)
                 case .nDesu: NdesuPage(verb: verb)
-                case .auxiliaries, .advanced, .lessons: EmptyView()
+                case .auxiliaries: AuxiliariesPage(verb: verb)
+                case .advanced: AdvancedPage(verb: verb)
+                case .lessons: VerbLessonsPage()
                 }
             }
         }
@@ -100,31 +96,7 @@ struct VerbDetailView: View {
     private var formGroups: some View {
         VStack(alignment: .leading, spacing: 16) {
             VerbFormsCard(verb: verb)
-
             MoreRowsCard(verb: verb)
-
-            if hasAdvancedForms {
-                FormGroupSection(
-                    title: "Advanced",
-                    forms: [
-                        ("Volitional", verb.forms.volitional),
-                        ("Passive", verb.forms.passive),
-                        ("Causative", verb.forms.causative),
-                        ("Causative-passive", verb.forms.causativePassive),
-                        ("Conditional (ば)", verb.forms.conditionalBa),
-                        ("Conditional (たら)", verb.forms.conditionalTara),
-                        ("Imperative", verb.forms.imperative),
-                        ("たい (want to)", verb.forms.tai),
-                    ].compactMap { label, value in value.map { (label, $0) } },
-                    defaultExpanded: false
-                )
-            }
-
-            if verb.forms.hasAuxiliaryForms {
-                AuxiliaryFormsSection(forms: verb.forms)
-            }
-
-            VerbGrammarSection()
         }
     }
 }
```

```bash
git rm App/AuxiliaryFormsSection.swift App/VerbGrammarSection.swift App/FormGroupSection.swift
```

- [ ] **Step 3: Build both platforms and run the tests**

```bash
./scripts/generate-project.sh
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_macOS -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
(cd Packages/VerbKit && swift test 2>&1 | grep -E "error:|failed|Executed .* tests" | tail -1)
```

Expected: `** BUILD SUCCEEDED **` twice and `Executed 207 tests, with 0 failures`.

- [ ] **Step 4: Check the whole page in the iOS Simulator**

Build and launch as in Task 2 Step 4 (unique bundle id `…rdcheck`, uninstall between runs; take a fresh screenshot before each tap). Expected, on **Verbs → たべる**:
- The page is now short: header, buttons, notes, description, the Forms card, and one **More** card with four rows: **Potential** (たべられる), **んです** (たべるんです), **Auxiliaries** (たべている) and **Grammar** (10 lessons). There are no collapsible groups left.
- **Auxiliaries** pushes a page with a **ている** heading and a Plain / Polite table (たべている / たべています … たべていて), an **Others** heading and a table with rows てしまう, ておく, てみる, ながら (empty Polite cell), すぎる, やすい, にくい, then four full-width **Learn about …** buttons. The longest cells (たべていませんでした, たべてしまいます) do not wrap.
- **Grammar** pushes a card listing the ten lessons (んです, 可能形, はず・かもしれない・わけ, べき・ものだ, よう・みたい・そう・らしい, っぽい, ている・てある, てしまう・ておく, てみる・ながら, すぎる・やすい・にくい), each with a two-line summary. Tapping a lesson switches to the Grammar tab and opens it, even on a fresh install where the Grammar tab was never opened.
- Spot-check **する** (the whole of each form is bold, e.g. **します**), **のむ** (の**める**) and **ある**: its More card has **Auxiliaries** but **no Potential row**, and its Auxiliaries page has no ている table and only the rows すぎる, やすい, にくい and ながら.
- **Check iPad and macOS** if a simulator or the Mac app is to hand (the verification run did not): in the split view's detail column, a row must push its page, Back must return to the verb page, and choosing another verb must reset to the main page.

- [ ] **Step 5: Clean up and commit**

```bash
xcrun simctl uninstall booted dev.martinloeseth.jpverbconjugation.rdcheck
git status --short                       # only the App/ files of this task
git add App
git commit -m "$(cat <<'EOF'
Move Auxiliaries, Advanced and Grammar to their own pages

The More card gains the remaining rows, and the verb page is now just the
header, the Forms card and the More card. The last collapsible section views
and the glass tile group are deleted.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Full verification, merge and publishing

**Files:** none (verification only).

- [ ] **Step 1: Run every test suite**

```bash
cd Packages/VerbKit && swift test 2>&1 | grep -E "error:|failed|Executed .* tests" | tail -1
cd ../.. && python3 -m unittest discover -s scripts -p "test_*.py" 2>&1 | tail -2
python3 scripts/update_data.py --check
```

Expected: `Executed 207 tests, with 0 failures`; `Ran 85 tests ... OK`; `data is up to date`.

- [ ] **Step 2: Build both app targets from a clean generate**

```bash
./scripts/generate-project.sh
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_macOS -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)"
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)"
```

Expected: `** BUILD SUCCEEDED **` twice.

- [ ] **Step 3: Confirm nothing was left behind**

```bash
grep -rn "FormGroupSection\|PotentialFormsSection\|NdesuFormsSection\|AuxiliaryFormsSection\|VerbGrammarSection" App Packages | grep -v "/.build/"
grep -rn "accessibility" App | grep -E "FormTable|FormCell|MoreRowsCard|Page|LessonLinks"
git status --short
```

Expected: the first two print nothing and the last shows a clean tree. (`formLabels` is deliberately still used by the quiz.)

- [ ] **Step 4: Merge gracefully**

```bash
git log --oneline main..HEAD | cat                      # only this work's commits
git diff --name-only HEAD...main -- . ':!docs' | cat    # what main changed since we branched
```

If the second command prints nothing, the merge is a fast-forward: from the main checkout, `git merge --ff-only feature/verb-page-redesign-impl`. If `main` has moved, do **not** force anything: fetch, merge `origin/main` into the branch (or rebase), keep `main`'s side of any conflict and re-apply only this plan's edits to that file, then re-run Steps 1–3. Get the user's go-ahead before merging into `main`.

- [ ] **Step 5: Publish (needs the user's explicit go-ahead)**

This is an app-only change: nothing here is read from the data repository, so a push changes the source and not what any installed build sees. **Do not push without asking the user first.**
