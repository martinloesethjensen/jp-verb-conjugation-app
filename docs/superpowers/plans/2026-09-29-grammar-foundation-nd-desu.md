# Grammar Foundation + んです / なんです Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Grammar content type — model, GitHub-synced data, SwiftData cache, and a Grammar tab — with んです/なんです as its first lesson, plus eight stored んです forms per verb, shown on the verb detail page and linked to the lesson.

**Architecture:** `grammar.json` is a second published file beside `verbs.json`, tracked by an optional `grammar` block in `manifest.json` and synced by a `GrammarSyncService` that mirrors `VerbSyncService` (including its persist-then-`confirmSynced` contract). `VerbStore` syncs verbs first and grammar after, in the background, so a grammar failure never touches verbs. The UI wraps the existing verb experience in a `TabView` (Verbs / Grammar), and a single `openRoute` environment action lets a verb page jump to a lesson. A small standalone Python script fills the per-verb `nd_*` forms and recomputes the manifest hashes.

**Tech Stack:** Swift 5 language mode on Xcode 27 (SwiftPM tools 6.2), SwiftUI with Liquid Glass, SwiftData, CryptoKit, XCTest; Python 3 (standard library only) for the maintainer script; XcodeGen 2.46.

**Spec:** [docs/superpowers/specs/2026-09-29-grammar-foundation-nd-desu-design.md](../specs/2026-09-29-grammar-foundation-nd-desu-design.md), which builds on the [native rewrite spec](../specs/2026-09-23-native-apple-rewrite-design.md). Read both, including the rewrite spec's section 10 (visual design direction).

**Verified against:** `main` at `3b56c92`. Every task below was executed on branch `feature/grammar-nd-desu` (one commit per task), with all tests passing, both app targets building, and the app run in the iOS Simulator against local copies of the data. **If `main` has moved since then, re-check the "Files changed on main" list in Task 0 before starting.**

## Global Constraints

- Deployment target: **iOS 26 / macOS 26** minimum, Swift language mode 5 (`Package.swift` is `swift-tools-version:6.2` with `swiftLanguageModes: [.v5]`). Do not lower it.
- **Patch existing files; never replace them wholesale.** `main` changes underneath this work. Modified files are given as diffs against `3b56c92`: apply with `git apply --3way`, or make the equivalent edit by hand if the surrounding code has moved. Never paste over a whole existing source file.
- Sync contract (mirrors `VerbSyncService`): `sync()` records **nothing** as synced. The caller persists, then calls `confirmSynced(_:)`. A persistence failure must leave the manifest unrecorded so the next sync re-fetches.
- Grammar data lives in `data/grammar.json`, tracked by an **optional** `grammar: {version, sha256}` block in `data/manifest.json`. The top-level `version` and `sha256` keep meaning "`verbs.json`", so installed builds keep working (spec §2).
- `VerbManifest` compares by whole-struct equality; never nest the grammar entry inside it, or a grammar edit would re-download verbs (spec §2).
- The eight new `VerbForms` fields are **optional** and snake_case in JSON: `nd_pos`, `nd_neg`, `nd_past`, `nd_past_neg`, `nd_casual_pos`, `nd_casual_neg`, `nd_casual_past`, `nd_casual_past_neg` (spec §1).
- A grammar failure must never change `VerbStore.verbs` or `VerbStore.firstLaunchState`. Grammar sync starts only after verbs are available (spec §2).
- `nd_*` forms get **no** `FormKey` cases, so they do not appear in quiz questions (spec §1).
- Visual design direction (rewrite spec §10): custom surfaces use `.glassEffect(...)` / `.glass` and `.glassProminent` button styles; standard containers are left as they are; **no accessibility-specific modifiers** (`.accessibilityLabel`, `.accessibilityHint`, …).
- `List(selection:)` rows use the pattern already in `VerbListView`: a `Button` that sets the selection, `.buttonStyle(.plain)`, and `.tag(value)`.
- The んです section on verb detail is collapsed by default and hidden when the verb has no `nd_*` fields; its "Learn about んです" link is hidden when the lesson hasn't synced (spec §3).
- Out of scope for v1: grammar in the quiz, bookmarks or progress, audio, furigana or reading toggles, grammar filter chips, and sub-projects 2–4 (potential form deep-dive, nuance endings, verb auxiliaries) (spec §3, Decomposition).
- Lesson text is written independently. Do not copy wording or examples from Yokubi (spec, Decomposition). Examples use mostly hiragana with kanji where natural.
- `data/verbs.json` and `data/manifest.json` are changed only by running `scripts/update_data.py`, never by hand. Hashes must match the files byte for byte.
- Any `git push` to the GitHub remote requires explicit user confirmation at execution time. Do not push without asking first.

---

## Task 0: Baseline

**Files:** none.

- [ ] **Step 1: Create the branch and record the baseline**

```bash
git worktree add -b feature/grammar-nd-desu .claude/worktrees/grammar-nd-desu main
cd .claude/worktrees/grammar-nd-desu
git log -1 --format=%h
cd Packages/VerbKit && swift test 2>&1 | grep -E "error:|failed|Executed .* tests" | tail -1
```

Expected: the commit hash you start from, and `Executed 51 tests, with 0 failures` when starting from `3b56c92`. Every count below is relative to that baseline.

- [ ] **Step 2: If `main` is newer than `3b56c92`, see what it touched**

```bash
git diff --name-only 3b56c92 main -- . ':!docs' ':!*.png'
```

Expected: nothing. If files appear, and any is one this plan modifies (`VerbStore.swift`, `VerbSyncService.swift`, `GitHubVerbFetcher.swift`, `VerbForms.swift`, `VerbModelContainer.swift`, `RootView.swift`, `VerbDetailView.swift`, `JPVerbConjugationApp.swift`, `Package.swift`, the sync/fetcher/store tests), read that diff before applying the matching diff below, and adapt rather than overwrite.

---

## Task 1: Grammar models and decoding

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Models/GrammarPoint.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/GrammarDecodingTests.swift`

**Interfaces:**
- Produces (used by every later task): `GrammarPoint` (`Codable, Hashable, Identifiable, Sendable`; fields `id`, `title`, `summary`, `level: GrammarLevel`, `usages: [GrammarUsage]`, `attachment: [AttachmentRule]`, `conjugations: [GrammarConjugation]`, `pitfalls: [GrammarPitfall]`, `related: [String]`; `static let nDesuID = "n-desu"`), `GrammarDataFile` (`version`, `description`, `grammar: [GrammarPoint]`), `GrammarLevel`, `WordClass` (`.verb`, `.iAdjective`, `.naAdjective`, `.noun`), `GrammarRegister`, `GrammarExample` (`jp`, `en`), `GrammarUsage`, `AttachmentRule` (`wordClass`, `condition?`, `pattern`, `example`, `note?`), `GrammarPitfall` (`heading`, `explanation`, `examples` — optional in JSON), `GrammarConjugation` (`form`, `register`, `note?`).

- [ ] **Step 1: Write the failing test**

`Packages/VerbKit/Tests/VerbKitTests/GrammarDecodingTests.swift`:

```swift
import XCTest
@testable import VerbKit

final class GrammarDecodingTests: XCTestCase {
    private let json = """
    {
      "version": "test",
      "description": "d",
      "grammar": [
        {
          "id": "n-desu",
          "title": "んです",
          "summary": "Explanatory ending.",
          "level": "beginner",
          "usages": [
            {
              "heading": "Giving a reason",
              "explanation": "Explains why.",
              "examples": [ { "jp": "頭が痛いんです。", "en": "I have a headache." } ]
            }
          ],
          "attachment": [
            { "word_class": "verb", "pattern": "plain form + んです", "example": "食べるんです" },
            { "word_class": "na-adjective", "condition": "non-past, affirmative", "pattern": "stem + なんです", "example": "静かなんです", "note": "だ becomes な" }
          ],
          "conjugations": [
            { "form": "んです", "register": "polite" },
            { "form": "の (soft statement)", "register": "casual", "note": "sounds softer" }
          ],
          "pitfalls": [
            {
              "heading": "Negation",
              "explanation": "Negating the explanation is not a refusal.",
              "examples": [ { "jp": "食べるんじゃない。", "en": "Don't eat!" } ]
            },
            { "heading": "Past", "explanation": "Put the past on the verb." }
          ],
          "related": []
        }
      ]
    }
    """

    private func decode() throws -> GrammarDataFile {
        try JSONDecoder().decode(GrammarDataFile.self, from: Data(json.utf8))
    }

    func testDecodesGrammarDataFile() throws {
        let file = try decode()
        XCTAssertEqual(file.grammar.count, 1)
        let point = file.grammar[0]
        XCTAssertEqual(point.id, "n-desu")
        XCTAssertEqual(point.level, .beginner)
        XCTAssertEqual(point.usages[0].examples[0].jp, "頭が痛いんです。")
        XCTAssertEqual(point.related, [])
    }

    func testDecodesAttachmentRulesWithOptionalFields() throws {
        let point = try decode().grammar[0]
        XCTAssertEqual(point.attachment[0].wordClass, .verb)
        XCTAssertNil(point.attachment[0].condition)
        XCTAssertNil(point.attachment[0].note)
        XCTAssertEqual(point.attachment[1].wordClass, .naAdjective)
        XCTAssertEqual(point.attachment[1].condition, "non-past, affirmative")
        XCTAssertEqual(point.attachment[1].note, "だ becomes な")
    }

    func testDecodesConjugationRegisters() throws {
        let point = try decode().grammar[0]
        XCTAssertEqual(point.conjugations.map(\.register), [.polite, .casual])
        XCTAssertEqual(point.conjugations[1].note, "sounds softer")
    }

    func testDecodesPitfallsWithAndWithoutExamples() throws {
        let point = try decode().grammar[0]
        XCTAssertEqual(point.pitfalls.map(\.heading), ["Negation", "Past"])
        XCTAssertEqual(point.pitfalls[0].examples[0].en, "Don't eat!")
        XCTAssertEqual(point.pitfalls[1].examples, [])
    }

    func testIDIsSlug() throws {
        XCTAssertEqual(try decode().grammar[0].id, GrammarPoint.nDesuID)
    }

    func testUnknownWordClassFailsDecoding() {
        let bad = json.replacingOccurrences(of: "\"verb\"", with: "\"adverb\"")
        XCTAssertThrowsError(try JSONDecoder().decode(GrammarDataFile.self, from: Data(bad.utf8)))
    }

    func testEncodeDecodeRoundTrip() throws {
        let file = try decode()
        let data = try JSONEncoder().encode(file)
        let again = try JSONDecoder().decode(GrammarDataFile.self, from: data)
        XCTAssertEqual(again.grammar, file.grammar)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd Packages/VerbKit && swift test --filter GrammarDecodingTests 2>&1 | tail -15
```

Expected: build fails with `cannot find 'GrammarDataFile' in scope`.

- [ ] **Step 3: Write the models**

`Packages/VerbKit/Sources/VerbKit/Models/GrammarPoint.swift`:

```swift
public enum GrammarLevel: String, Codable, Hashable, Sendable {
    case beginner
    case intermediate
}

/// Word classes a grammar ending can attach to. Deliberately separate
/// from `VerbType`, which classifies verbs only.
public enum WordClass: String, Codable, Hashable, Sendable {
    case verb
    case iAdjective = "i-adjective"
    case naAdjective = "na-adjective"
    case noun
}

public enum GrammarRegister: String, Codable, Hashable, Sendable {
    case polite
    case casual
    case formal
}

public struct GrammarExample: Codable, Hashable, Sendable {
    public var jp: String
    public var en: String

    public init(jp: String, en: String) {
        self.jp = jp
        self.en = en
    }
}

public struct GrammarUsage: Codable, Hashable, Sendable {
    public var heading: String
    public var explanation: String
    public var examples: [GrammarExample]

    public init(heading: String, explanation: String, examples: [GrammarExample]) {
        self.heading = heading
        self.explanation = explanation
        self.examples = examples
    }
}

/// How the ending attaches to one word class. `condition` narrows a rule
/// to part of a class (e.g. na-adjectives in the non-past affirmative
/// take なんです, but in the past take だったんです).
public struct AttachmentRule: Codable, Hashable, Sendable {
    public var wordClass: WordClass
    public var condition: String?
    public var pattern: String
    public var example: String
    public var note: String?

    public init(wordClass: WordClass, condition: String? = nil, pattern: String, example: String, note: String? = nil) {
        self.wordClass = wordClass
        self.condition = condition
        self.pattern = pattern
        self.example = example
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case wordClass = "word_class"
        case condition
        case pattern
        case example
        case note
    }
}

/// A common mistake or nuance worth calling out ("Watch out" on the
/// detail page). Same shape as a usage, but examples may be empty.
public struct GrammarPitfall: Codable, Hashable, Sendable {
    public var heading: String
    public var explanation: String
    public var examples: [GrammarExample]

    public init(heading: String, explanation: String, examples: [GrammarExample] = []) {
        self.heading = heading
        self.explanation = explanation
        self.examples = examples
    }

    enum CodingKeys: String, CodingKey {
        case heading, explanation, examples
    }

    /// `examples` may be omitted from the JSON.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        heading = try container.decode(String.self, forKey: .heading)
        explanation = try container.decode(String.self, forKey: .explanation)
        examples = try container.decodeIfPresent([GrammarExample].self, forKey: .examples) ?? []
    }
}

public struct GrammarConjugation: Codable, Hashable, Sendable {
    public var form: String
    public var register: GrammarRegister
    public var note: String?

    public init(form: String, register: GrammarRegister, note: String? = nil) {
        self.form = form
        self.register = register
        self.note = note
    }
}

public struct GrammarPoint: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var summary: String
    public var level: GrammarLevel
    public var usages: [GrammarUsage]
    public var attachment: [AttachmentRule]
    public var conjugations: [GrammarConjugation]
    public var pitfalls: [GrammarPitfall]
    public var related: [String]

    /// The id verb detail pages link to for the んです lesson.
    public static let nDesuID = "n-desu"

    public init(
        id: String,
        title: String,
        summary: String,
        level: GrammarLevel,
        usages: [GrammarUsage],
        attachment: [AttachmentRule],
        conjugations: [GrammarConjugation],
        pitfalls: [GrammarPitfall],
        related: [String]
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.level = level
        self.usages = usages
        self.attachment = attachment
        self.conjugations = conjugations
        self.pitfalls = pitfalls
        self.related = related
    }
}

public struct GrammarDataFile: Codable, Sendable {
    public var version: String
    public var description: String
    public var grammar: [GrammarPoint]

    public init(version: String, description: String, grammar: [GrammarPoint]) {
        self.version = version
        self.description = description
        self.grammar = grammar
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd Packages/VerbKit && swift test --filter GrammarDecodingTests 2>&1 | grep -E "error:|Executed"
```

Expected: `Executed 7 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Packages/VerbKit/Sources/VerbKit/Models/GrammarPoint.swift Packages/VerbKit/Tests/VerbKitTests/GrammarDecodingTests.swift
git commit -m "$(cat <<'EOF'
Add grammar models and JSON decoding

GrammarPoint carries usages, per-word-class attachment rules, the
ending's own conjugations, and pitfalls. WordClass is separate from
VerbType, which classifies verbs only.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: んです forms on `VerbForms`

**Files:**
- Modify: `Packages/VerbKit/Sources/VerbKit/Models/VerbForms.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/VerbFormsNdTests.swift`

**Interfaces:**
- Consumes: existing `VerbForms`.
- Produces: `VerbForms.ndPos`, `ndNeg`, `ndPast`, `ndPastNeg`, `ndCasualPos`, `ndCasualNeg`, `ndCasualPast`, `ndCasualPastNeg` (all `String?`, defaulting to `nil` in the initializer) and `VerbForms.hasNdForms: Bool`. JSON keys are the snake_case names in Global Constraints.

- [ ] **Step 1: Write the failing test**

`Packages/VerbKit/Tests/VerbKitTests/VerbFormsNdTests.swift`:

```swift
import XCTest
@testable import VerbKit

final class VerbFormsNdTests: XCTestCase {
    private func baseForms() -> VerbForms {
        VerbForms(
            masuPos: "たべます", masuNeg: "たべません", masuPast: "たべました", masuPastNeg: "たべませんでした",
            te: "たべて", shortPos: "たべる", shortNeg: "たべない", shortPast: "たべた", shortPastNeg: "たべなかった"
        )
    }

    func testHasNdFormsIsFalseByDefault() {
        XCTAssertFalse(baseForms().hasNdForms)
    }

    func testHasNdFormsIsTrueWhenAnyFieldIsSet() {
        var forms = baseForms()
        forms.ndCasualPastNeg = "たべなかったんだ"
        XCTAssertTrue(forms.hasNdForms)
    }

    func testDecodesSnakeCaseNdKeys() throws {
        let json = """
        {
          "masu_pos": "a", "masu_neg": "b", "masu_past": "c", "masu_past_neg": "d",
          "te": "e", "short_pos": "f", "short_neg": "g", "short_past": "h", "short_past_neg": "i",
          "nd_pos": "1", "nd_neg": "2", "nd_past": "3", "nd_past_neg": "4",
          "nd_casual_pos": "5", "nd_casual_neg": "6", "nd_casual_past": "7", "nd_casual_past_neg": "8"
        }
        """
        let forms = try JSONDecoder().decode(VerbForms.self, from: Data(json.utf8))
        XCTAssertEqual(
            [forms.ndPos, forms.ndNeg, forms.ndPast, forms.ndPastNeg,
             forms.ndCasualPos, forms.ndCasualNeg, forms.ndCasualPast, forms.ndCasualPastNeg],
            ["1", "2", "3", "4", "5", "6", "7", "8"]
        )
    }

    func testOldDataWithoutNdKeysStillDecodes() throws {
        let json = """
        {
          "masu_pos": "a", "masu_neg": "b", "masu_past": "c", "masu_past_neg": "d",
          "te": "e", "short_pos": "f", "short_neg": "g", "short_past": "h", "short_past_neg": "i"
        }
        """
        let forms = try JSONDecoder().decode(VerbForms.self, from: Data(json.utf8))
        XCTAssertFalse(forms.hasNdForms)
    }

    func testEncodesSnakeCaseNdKeys() throws {
        var forms = baseForms()
        forms.ndPos = "たべるんです"
        forms.ndCasualPastNeg = "たべなかったんだ"
        let data = try JSONEncoder().encode(forms)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["nd_pos"] as? String, "たべるんです")
        XCTAssertEqual(object["nd_casual_past_neg"] as? String, "たべなかったんだ")
        XCTAssertNil(object["nd_neg"])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd Packages/VerbKit && swift test --filter VerbFormsNdTests 2>&1 | tail -15
```

Expected: build fails with `value of type 'VerbForms' has no member 'ndCasualPastNeg'`.

- [ ] **Step 3: Add the fields**

Apply this diff to `Packages/VerbKit/Sources/VerbKit/Models/VerbForms.swift`. It is purely additive (the one removed line only gains a trailing comma):

```diff
diff --git a/Packages/VerbKit/Sources/VerbKit/Models/VerbForms.swift b/Packages/VerbKit/Sources/VerbKit/Models/VerbForms.swift
index d0b61fc..8650023 100644
--- a/Packages/VerbKit/Sources/VerbKit/Models/VerbForms.swift
+++ b/Packages/VerbKit/Sources/VerbKit/Models/VerbForms.swift
@@ -19,6 +19,22 @@ public struct VerbForms: Codable, Hashable, Sendable {
     public var imperative: String?
     public var tai: String?
 
+    // んです forms (grammar point `n-desu`): the plain forms + んです/んだ.
+    public var ndPos: String?
+    public var ndNeg: String?
+    public var ndPast: String?
+    public var ndPastNeg: String?
+    public var ndCasualPos: String?
+    public var ndCasualNeg: String?
+    public var ndCasualPast: String?
+    public var ndCasualPastNeg: String?
+
+    /// True when at least one んです form is populated.
+    public var hasNdForms: Bool {
+        [ndPos, ndNeg, ndPast, ndPastNeg, ndCasualPos, ndCasualNeg, ndCasualPast, ndCasualPastNeg]
+            .contains { $0 != nil }
+    }
+
     public init(
         masuPos: String,
         masuNeg: String,
@@ -37,7 +53,15 @@ public struct VerbForms: Codable, Hashable, Sendable {
         conditionalBa: String? = nil,
         conditionalTara: String? = nil,
         imperative: String? = nil,
-        tai: String? = nil
+        tai: String? = nil,
+        ndPos: String? = nil,
+        ndNeg: String? = nil,
+        ndPast: String? = nil,
+        ndPastNeg: String? = nil,
+        ndCasualPos: String? = nil,
+        ndCasualNeg: String? = nil,
+        ndCasualPast: String? = nil,
+        ndCasualPastNeg: String? = nil
     ) {
         self.masuPos = masuPos
         self.masuNeg = masuNeg
@@ -57,6 +81,14 @@ public struct VerbForms: Codable, Hashable, Sendable {
         self.conditionalTara = conditionalTara
         self.imperative = imperative
         self.tai = tai
+        self.ndPos = ndPos
+        self.ndNeg = ndNeg
+        self.ndPast = ndPast
+        self.ndPastNeg = ndPastNeg
+        self.ndCasualPos = ndCasualPos
+        self.ndCasualNeg = ndCasualNeg
+        self.ndCasualPast = ndCasualPast
+        self.ndCasualPastNeg = ndCasualPastNeg
     }
 
     enum CodingKeys: String, CodingKey {
@@ -78,6 +110,14 @@ public struct VerbForms: Codable, Hashable, Sendable {
         case conditionalTara = "conditional_tara"
         case imperative
         case tai
+        case ndPos = "nd_pos"
+        case ndNeg = "nd_neg"
+        case ndPast = "nd_past"
+        case ndPastNeg = "nd_past_neg"
+        case ndCasualPos = "nd_casual_pos"
+        case ndCasualNeg = "nd_casual_neg"
+        case ndCasualPast = "nd_casual_past"
+        case ndCasualPastNeg = "nd_casual_past_neg"
     }
 
     public subscript(_ key: FormKey) -> String {
```

- [ ] **Step 4: Run the whole suite to verify it passes**

```bash
cd Packages/VerbKit && swift test 2>&1 | grep -E "error:|failed|Executed .* tests" | tail -1
```

Expected: `Executed 63 tests, with 0 failures` (51 baseline, 7 from Task 1, 5 new). The existing tests prove data without `nd_*` keys still decodes.

- [ ] **Step 5: Commit**

```bash
git add Packages/VerbKit
git commit -m "$(cat <<'EOF'
Add optional んです forms to VerbForms

Eight optional fields (polite んです and casual んだ across present and
past, positive and negative) plus hasNdForms. They're optional so data
published before they exist still decodes.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Data maintenance script

The rewrite spec's Python generator (its section 9) is not in the repo. This project needs three things from it, so this task builds them as one small standalone script: fill the `nd_*` forms, validate `grammar.json`, and recompute both manifest hashes.

**Files:**
- Create: `scripts/update_data.py`
- Test: `scripts/test_update_data.py`

**Interfaces:**
- Produces: the CLI `python3 scripts/update_data.py [--check] [--data-dir DIR] [--verbs-version V] [--grammar-version V]`. Exit code 0 on success; with `--check`, exit code 1 if `data/` is stale or invalid. Later tasks run it after every data edit. Library functions (`nd_forms`, `apply_nd_forms`, `dump_verbs`, `validate_grammar`, `build_manifest`, `run`) are what the tests call.
- Manifest written: `{"version", "sha256", "grammar": {"version", "sha256"}}`. A file's version is kept when its hash is unchanged and bumped (minor) when it changed.

- [ ] **Step 1: Write the failing tests**

`scripts/test_update_data.py`:

```python
import copy
import json
import tempfile
import unittest
from pathlib import Path

import update_data as ud


def verb(dict_form, short_pos, short_neg, short_past, short_past_neg):
    return {
        "dict": dict_form,
        "forms": {
            "short_pos": short_pos,
            "short_neg": short_neg,
            "short_past": short_past,
            "short_past_neg": short_past_neg,
        },
    }


def valid_grammar():
    return {
        "version": "1.0.0",
        "description": "d",
        "grammar": [
            {
                "id": "n-desu",
                "title": "んです",
                "summary": "s",
                "level": "beginner",
                "usages": [
                    {"heading": "h", "explanation": "e", "examples": [{"jp": "あ", "en": "a"}]}
                ],
                "attachment": [
                    {"word_class": "verb", "pattern": "p", "example": "x"}
                ],
                "conjugations": [{"form": "んです", "register": "polite"}],
                "pitfalls": [{"heading": "h", "explanation": "e", "examples": []}],
                "related": [],
            }
        ],
    }


class NdFormsTests(unittest.TestCase):
    def test_regular_verb(self):
        v = verb("たべる", "たべる", "たべない", "たべた", "たべなかった")
        self.assertEqual(
            ud.nd_forms(v["forms"]),
            {
                "nd_pos": "たべるんです",
                "nd_neg": "たべないんです",
                "nd_past": "たべたんです",
                "nd_past_neg": "たべなかったんです",
                "nd_casual_pos": "たべるんだ",
                "nd_casual_neg": "たべないんだ",
                "nd_casual_past": "たべたんだ",
                "nd_casual_past_neg": "たべなかったんだ",
            },
        )

    def test_irregular_verb_uses_its_own_plain_forms(self):
        forms = verb("くる", "くる", "こない", "きた", "こなかった")["forms"]
        result = ud.nd_forms(forms)
        self.assertEqual(result["nd_neg"], "こないんです")
        self.assertEqual(result["nd_past"], "きたんです")

    def test_apply_is_idempotent(self):
        doc = {"verbs": [verb("する", "する", "しない", "した", "しなかった")]}
        self.assertTrue(ud.apply_nd_forms(doc))
        self.assertFalse(ud.apply_nd_forms(doc))

    def test_apply_repairs_a_stale_value(self):
        doc = {"verbs": [verb("する", "する", "しない", "した", "しなかった")]}
        ud.apply_nd_forms(doc)
        doc["verbs"][0]["forms"]["nd_pos"] = "wrong"
        self.assertTrue(ud.apply_nd_forms(doc))
        self.assertEqual(doc["verbs"][0]["forms"]["nd_pos"], "するんです")


class DumpTests(unittest.TestCase):
    def test_examples_stay_on_one_line_and_kana_is_not_escaped(self):
        doc = {"verbs": [{"examples": [{"form": "te", "jp": "たべて。", "en": "Eat."}]}]}
        text = ud.dump_verbs(doc)
        self.assertIn('{ "form": "te", "jp": "たべて。", "en": "Eat." }', text)
        self.assertTrue(text.endswith("\n"))


class ValidateGrammarTests(unittest.TestCase):
    def test_valid_document_has_no_errors(self):
        self.assertEqual(ud.validate_grammar(valid_grammar()), [])

    def test_bad_level(self):
        doc = valid_grammar()
        doc["grammar"][0]["level"] = "expert"
        self.assertTrue(any("level" in e for e in ud.validate_grammar(doc)))

    def test_bad_word_class(self):
        doc = valid_grammar()
        doc["grammar"][0]["attachment"][0]["word_class"] = "adverb"
        self.assertTrue(any("word_class" in e for e in ud.validate_grammar(doc)))

    def test_bad_register(self):
        doc = valid_grammar()
        doc["grammar"][0]["conjugations"][0]["register"] = "rude"
        self.assertTrue(any("register" in e for e in ud.validate_grammar(doc)))

    def test_duplicate_ids(self):
        doc = valid_grammar()
        doc["grammar"].append(copy.deepcopy(doc["grammar"][0]))
        self.assertTrue(any("duplicate id" in e for e in ud.validate_grammar(doc)))

    def test_dangling_related_id(self):
        doc = valid_grammar()
        doc["grammar"][0]["related"] = ["nope"]
        self.assertTrue(any("related" in e for e in ud.validate_grammar(doc)))

    def test_pitfall_without_explanation(self):
        doc = valid_grammar()
        doc["grammar"][0]["pitfalls"][0]["explanation"] = ""
        self.assertTrue(any("pitfall" in e for e in ud.validate_grammar(doc)))

    def test_usage_without_examples(self):
        doc = valid_grammar()
        doc["grammar"][0]["usages"][0]["examples"] = []
        self.assertTrue(any("example" in e for e in ud.validate_grammar(doc)))


class ManifestTests(unittest.TestCase):
    def test_unchanged_files_keep_versions(self):
        existing = {
            "version": "1.2.0",
            "sha256": ud.sha256_hex(b"v"),
            "grammar": {"version": "3.0.0", "sha256": ud.sha256_hex(b"g")},
        }
        result = ud.build_manifest(existing, b"v", b"g")
        self.assertEqual(result["version"], "1.2.0")
        self.assertEqual(result["grammar"]["version"], "3.0.0")

    def test_changed_files_bump_minor(self):
        existing = {
            "version": "1.2.0",
            "sha256": "old",
            "grammar": {"version": "3.0.0", "sha256": "old"},
        }
        result = ud.build_manifest(existing, b"v", b"g")
        self.assertEqual(result["version"], "1.3.0")
        self.assertEqual(result["grammar"]["version"], "3.1.0")
        self.assertEqual(result["sha256"], ud.sha256_hex(b"v"))

    def test_missing_grammar_block_starts_at_1_0_0(self):
        result = ud.build_manifest({"version": "1.0.0", "sha256": ud.sha256_hex(b"v")}, b"v", b"g")
        self.assertEqual(result["version"], "1.0.0")
        self.assertEqual(result["grammar"], {"version": "1.0.0", "sha256": ud.sha256_hex(b"g")})

    def test_explicit_versions_win(self):
        result = ud.build_manifest({"version": "1.0.0", "sha256": "old"}, b"v", b"g", "2.0.0", "9.9.9")
        self.assertEqual(result["version"], "2.0.0")
        self.assertEqual(result["grammar"]["version"], "9.9.9")


class RunTests(unittest.TestCase):
    def make_dir(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        d = Path(tmp.name)
        verbs = {
            "version": "1.0.0",
            "description": "d",
            "verbs": [verb("する", "する", "しない", "した", "しなかった")],
        }
        (d / "verbs.json").write_text(ud.dump_verbs(verbs), encoding="utf-8")
        (d / "grammar.json").write_text(json.dumps(valid_grammar(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        (d / "manifest.json").write_text(json.dumps({"version": "1.0.0", "sha256": "x"}) + "\n", encoding="utf-8")
        return d

    def test_check_reports_stale_then_run_fixes_then_check_passes(self):
        d = self.make_dir()
        code, _ = ud.run(d, check=True)
        self.assertEqual(code, 1)
        code, _ = ud.run(d)
        self.assertEqual(code, 0)
        code, _ = ud.run(d, check=True)
        self.assertEqual(code, 0)
        written = json.loads((d / "verbs.json").read_text(encoding="utf-8"))
        self.assertEqual(written["verbs"][0]["forms"]["nd_pos"], "するんです")
        manifest = json.loads((d / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["sha256"], ud.sha256_hex((d / "verbs.json").read_bytes()))
        self.assertEqual(manifest["grammar"]["sha256"], ud.sha256_hex((d / "grammar.json").read_bytes()))

    def test_invalid_grammar_blocks_everything_and_writes_nothing(self):
        d = self.make_dir()
        bad = valid_grammar()
        bad["grammar"][0]["level"] = "expert"
        (d / "grammar.json").write_text(json.dumps(bad), encoding="utf-8")
        before = (d / "verbs.json").read_bytes()
        code, messages = ud.run(d)
        self.assertEqual(code, 1)
        self.assertEqual((d / "verbs.json").read_bytes(), before)
        self.assertTrue(any("level" in m for m in messages))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd scripts && python3 -m unittest test_update_data 2>&1 | tail -5
```

Expected: `ModuleNotFoundError: No module named 'update_data'`.

- [ ] **Step 3: Write the script**

`scripts/update_data.py`:

```python
#!/usr/bin/env python3
"""Maintainer tool for the app's published data (data/).

Run after editing data/verbs.json or data/grammar.json:

    python3 scripts/update_data.py            # rewrite files in place
    python3 scripts/update_data.py --check    # verify only; exit 1 if stale/invalid

It does three things:
  1. Fills the nd_* (んです / んだ) forms on every verb in verbs.json by
     appending to the verb's plain forms. Deterministic; safe to re-run.
  2. Validates data/grammar.json (hand-authored) against the schema the
     app decodes. It never generates lesson text.
  3. Recomputes the SHA-256 of both files into data/manifest.json, bumping
     a file's version (minor) when its content changed.

Standard library only.
"""
import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

ND_SUFFIX = "んです"
ND_CASUAL_SUFFIX = "んだ"

# (nd field, plain-form field it attaches to, suffix)
ND_FIELDS = [
    ("nd_pos", "short_pos", ND_SUFFIX),
    ("nd_neg", "short_neg", ND_SUFFIX),
    ("nd_past", "short_past", ND_SUFFIX),
    ("nd_past_neg", "short_past_neg", ND_SUFFIX),
    ("nd_casual_pos", "short_pos", ND_CASUAL_SUFFIX),
    ("nd_casual_neg", "short_neg", ND_CASUAL_SUFFIX),
    ("nd_casual_past", "short_past", ND_CASUAL_SUFFIX),
    ("nd_casual_past_neg", "short_past_neg", ND_CASUAL_SUFFIX),
]

LEVELS = {"beginner", "intermediate"}
WORD_CLASSES = {"verb", "i-adjective", "na-adjective", "noun"}
REGISTERS = {"polite", "casual", "formal"}


def nd_forms(forms):
    """The eight んです forms for a verb's `forms` dict."""
    return {name: forms[source] + suffix for name, source, suffix in ND_FIELDS}


def apply_nd_forms(verbs_doc):
    """Set nd_* on every verb in place. Returns True if anything changed."""
    changed = False
    for verb in verbs_doc["verbs"]:
        forms = verb["forms"]
        for name, value in nd_forms(forms).items():
            if forms.get(name) != value:
                forms[name] = value
                changed = True
    return changed


def dump_verbs(doc):
    """Serialize verbs.json in the repo's style: 2-space indent, non-ASCII
    kept, and each example object on a single line."""
    text = json.dumps(doc, ensure_ascii=False, indent=2)
    text = re.sub(
        r'\{\n\s+("form": [^\n]+),\n\s+("jp": [^\n]+),\n\s+("en": [^\n]+)\n\s+\}',
        r"{ \1, \2, \3 }",
        text,
    )
    return text + "\n"


def validate_grammar(doc):
    """Returns a list of human-readable problems (empty when valid)."""
    errors = []
    points = doc.get("grammar")
    if not isinstance(points, list) or not points:
        return ["grammar: must be a non-empty list"]
    for key in ("version", "description"):
        if not isinstance(doc.get(key), str):
            errors.append(f"{key}: missing or not a string")

    ids = [p.get("id") for p in points]
    for dup in {i for i in ids if ids.count(i) > 1}:
        errors.append(f"duplicate id: {dup}")

    for p in points:
        pid = p.get("id", "<no id>")
        for key in ("id", "title", "summary"):
            if not isinstance(p.get(key), str) or not p[key]:
                errors.append(f"{pid}: {key} missing or empty")
        if p.get("level") not in LEVELS:
            errors.append(f"{pid}: level must be one of {sorted(LEVELS)}")
        for related in p.get("related", []):
            if related not in ids:
                errors.append(f"{pid}: related id '{related}' does not exist")
        if not isinstance(p.get("related"), list):
            errors.append(f"{pid}: related must be a list")

        usages = p.get("usages")
        if not isinstance(usages, list) or not usages:
            errors.append(f"{pid}: usages must be a non-empty list")
            usages = []
        for u in usages:
            heading = u.get("heading", "<no heading>")
            for key in ("heading", "explanation"):
                if not isinstance(u.get(key), str) or not u[key]:
                    errors.append(f"{pid}/{heading}: {key} missing or empty")
            examples = u.get("examples")
            if not isinstance(examples, list) or not examples:
                errors.append(f"{pid}/{heading}: needs at least one example")
                examples = []
            for e in examples:
                if not e.get("jp") or not e.get("en"):
                    errors.append(f"{pid}/{heading}: example needs jp and en")

        attachment = p.get("attachment")
        if not isinstance(attachment, list):
            errors.append(f"{pid}: attachment must be a list")
            attachment = []
        for a in attachment:
            if a.get("word_class") not in WORD_CLASSES:
                errors.append(f"{pid}: attachment word_class must be one of {sorted(WORD_CLASSES)}")
            for key in ("pattern", "example"):
                if not isinstance(a.get(key), str) or not a[key]:
                    errors.append(f"{pid}: attachment {key} missing or empty")

        pitfalls = p.get("pitfalls")
        if not isinstance(pitfalls, list):
            errors.append(f"{pid}: pitfalls must be a list")
            pitfalls = []
        for f in pitfalls:
            heading = f.get("heading", "<no heading>")
            for key in ("heading", "explanation"):
                if not isinstance(f.get(key), str) or not f[key]:
                    errors.append(f"{pid}/{heading}: pitfall {key} missing or empty")
            for e in f.get("examples", []):
                if not e.get("jp") or not e.get("en"):
                    errors.append(f"{pid}/{heading}: pitfall example needs jp and en")

        conjugations = p.get("conjugations")
        if not isinstance(conjugations, list):
            errors.append(f"{pid}: conjugations must be a list")
            conjugations = []
        for c in conjugations:
            if not isinstance(c.get("form"), str) or not c["form"]:
                errors.append(f"{pid}: conjugation form missing or empty")
            if c.get("register") not in REGISTERS:
                errors.append(f"{pid}: conjugation register must be one of {sorted(REGISTERS)}")
    return errors


def sha256_hex(data):
    return hashlib.sha256(data).hexdigest()


def bump_minor(version):
    major, minor, _patch = version.split(".")
    return f"{major}.{int(minor) + 1}.0"


def build_manifest(existing, verbs_bytes, grammar_bytes, verbs_version=None, grammar_version=None):
    """New manifest dict. A file's version is kept when its hash is
    unchanged, bumped (minor) when it changed, or forced by an explicit
    version. A grammar block that did not exist yet starts at 1.0.0."""
    verbs_hash = sha256_hex(verbs_bytes)
    grammar_hash = sha256_hex(grammar_bytes)

    old_verbs_version = existing.get("version", "1.0.0")
    if verbs_version:
        new_verbs_version = verbs_version
    elif existing.get("sha256") == verbs_hash:
        new_verbs_version = old_verbs_version
    else:
        new_verbs_version = bump_minor(old_verbs_version)

    old_grammar = existing.get("grammar")
    if grammar_version:
        new_grammar_version = grammar_version
    elif old_grammar is None:
        new_grammar_version = "1.0.0"
    elif old_grammar.get("sha256") == grammar_hash:
        new_grammar_version = old_grammar["version"]
    else:
        new_grammar_version = bump_minor(old_grammar["version"])

    return {
        "version": new_verbs_version,
        "sha256": verbs_hash,
        "grammar": {"version": new_grammar_version, "sha256": grammar_hash},
    }


def run(data_dir, check=False, verbs_version=None, grammar_version=None):
    """Returns (exit_code, messages)."""
    data_dir = Path(data_dir)
    verbs_path = data_dir / "verbs.json"
    grammar_path = data_dir / "grammar.json"
    manifest_path = data_dir / "manifest.json"
    messages = []

    grammar_bytes = grammar_path.read_bytes()
    problems = validate_grammar(json.loads(grammar_bytes))
    if problems:
        return 1, ["grammar.json is invalid:"] + [f"  - {p}" for p in problems]

    verbs_doc = json.loads(verbs_path.read_text(encoding="utf-8"))
    apply_nd_forms(verbs_doc)
    verbs_text = dump_verbs(verbs_doc)
    verbs_bytes = verbs_text.encode("utf-8")

    existing = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest = build_manifest(existing, verbs_bytes, grammar_bytes, verbs_version, grammar_version)
    manifest_text = json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"

    stale = []
    if verbs_path.read_bytes() != verbs_bytes:
        stale.append("data/verbs.json")
    if manifest_path.read_text(encoding="utf-8") != manifest_text:
        stale.append("data/manifest.json")

    if check:
        if stale:
            return 1, [f"stale: {', '.join(stale)} (run scripts/update_data.py)"]
        return 0, ["data is up to date"]

    if "data/verbs.json" in stale:
        verbs_path.write_bytes(verbs_bytes)
        messages.append("updated data/verbs.json")
    if "data/manifest.json" in stale:
        manifest_path.write_text(manifest_text, encoding="utf-8")
        messages.append(
            f"updated data/manifest.json (verbs {manifest['version']}, grammar {manifest['grammar']['version']})"
        )
    if not stale:
        messages.append("nothing to do; data is up to date")
    return 0, messages


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--data-dir", default=str(Path(__file__).resolve().parent.parent / "data"))
    parser.add_argument("--check", action="store_true", help="verify only; write nothing")
    parser.add_argument("--verbs-version", help="force the verbs.json manifest version")
    parser.add_argument("--grammar-version", help="force the grammar.json manifest version")
    args = parser.parse_args(argv)
    code, messages = run(args.data_dir, args.check, args.verbs_version, args.grammar_version)
    for line in messages:
        print(line)
    return code


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd scripts && python3 -m unittest test_update_data -v 2>&1 | tail -6
chmod +x update_data.py
```

Expected: `Ran 19 tests` and `OK`.

- [ ] **Step 5: Commit**

```bash
git add scripts/update_data.py scripts/test_update_data.py
git commit -m "$(cat <<'EOF'
Add data maintenance script for んです forms and manifest hashes

Fills the nd_* forms on every verb by appending んです/んだ to its plain
forms, validates the hand-authored grammar.json against the schema the
app decodes, and recomputes both manifest hashes (bumping a file's
version when its content changed). --check verifies without writing.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: んです / なんです lesson and published data

**Files:**
- Create: `data/grammar.json`
- Modify: `data/verbs.json`, `data/manifest.json` (both only via the script)
- Test: `Packages/VerbKit/Tests/VerbKitTests/RealGrammarDataTests.swift`

**Interfaces:**
- Consumes: `GrammarDataFile`, `GrammarPoint.nDesuID`, `VerbForms.nd*` (Tasks 1–2), `scripts/update_data.py` (Task 3), the internal `sha256Hex(of:)` from `Data/Hashing.swift`.
- Produces: the published data the app syncs. `RealGrammarDataTests` reads `data/` straight from the checkout, so any later edit to the data that skips the script fails a test. `main`'s existing `RealDataFileTests` guards `verbs.json` against the manifest hash, which this task also changes (and must keep passing).

- [ ] **Step 1: Write the failing test**

`Packages/VerbKit/Tests/VerbKitTests/RealGrammarDataTests.swift`:

```swift
import XCTest
@testable import VerbKit

/// Tests against the grammar half of the real published files in `data/`
/// (`RealDataFileTests` already guards `verbs.json` against its manifest
/// hash). They read the files straight from the repo checkout, so they
/// fail when someone edits the data and forgets `scripts/update_data.py`.
final class RealGrammarDataTests: XCTestCase {
    private func dataURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // VerbKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // VerbKit
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("data")
            .appendingPathComponent(name)
    }

    private func loadVerbs() throws -> [Verb] {
        let data = try Data(contentsOf: dataURL("verbs.json"))
        return try JSONDecoder().decode(VerbDataFile.self, from: data).verbs
    }

    private func loadGrammar() throws -> [GrammarPoint] {
        let data = try Data(contentsOf: dataURL("grammar.json"))
        return try JSONDecoder().decode(GrammarDataFile.self, from: data).grammar
    }

    func testEveryVerbHasNdFormsBuiltFromItsPlainForms() throws {
        let verbs = try loadVerbs()
        XCTAssertFalse(verbs.isEmpty)
        for verb in verbs {
            let f = verb.forms
            XCTAssertEqual(f.ndPos, f.shortPos + "んです", verb.dict)
            XCTAssertEqual(f.ndNeg, f.shortNeg + "んです", verb.dict)
            XCTAssertEqual(f.ndPast, f.shortPast + "んです", verb.dict)
            XCTAssertEqual(f.ndPastNeg, f.shortPastNeg + "んです", verb.dict)
            XCTAssertEqual(f.ndCasualPos, f.shortPos + "んだ", verb.dict)
            XCTAssertEqual(f.ndCasualNeg, f.shortNeg + "んだ", verb.dict)
            XCTAssertEqual(f.ndCasualPast, f.shortPast + "んだ", verb.dict)
            XCTAssertEqual(f.ndCasualPastNeg, f.shortPastNeg + "んだ", verb.dict)
        }
    }

    /// Hand-verified values, one per verb class: ichidan, godan, and both irregulars.
    func testNdFormsSpotChecks() throws {
        let verbs = try loadVerbs()
        func forms(_ dict: String) throws -> VerbForms {
            try XCTUnwrap(verbs.first { $0.dict == dict }, dict).forms
        }
        XCTAssertEqual(try forms("たべる").ndPastNeg, "たべなかったんです")
        XCTAssertEqual(try forms("かう").ndNeg, "かわないんです")
        XCTAssertEqual(try forms("かう").ndPast, "かったんです")
        XCTAssertEqual(try forms("する").ndCasualPos, "するんだ")
        XCTAssertEqual(try forms("くる").ndNeg, "こないんです")
        XCTAssertEqual(try forms("くる").ndPast, "きたんです")
    }

    func testGrammarFileDecodesAndContainsNDesu() throws {
        let points = try loadGrammar()
        let nDesu = try XCTUnwrap(points.first { $0.id == GrammarPoint.nDesuID })
        XCTAssertEqual(nDesu.title, "んです")
        XCTAssertEqual(nDesu.usages.count, 7)
        XCTAssertEqual(nDesu.attachment.count, 6)
        XCTAssertEqual(nDesu.pitfalls.count, 3)
        XCTAssertTrue(nDesu.conjugations.contains { $0.form == "の" && $0.register == .casual })
    }

    func testGrammarIDsAreUniqueAndRelatedIDsExist() throws {
        let points = try loadGrammar()
        let ids = points.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        for point in points {
            for related in point.related {
                XCTAssertTrue(ids.contains(related), "\(point.id) -> \(related)")
            }
        }
    }

    func testManifestGrammarHashMatchesTheGrammarFile() throws {
        let manifestData = try Data(contentsOf: dataURL("manifest.json"))
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        let grammar = try XCTUnwrap(manifest["grammar"] as? [String: String], "manifest.json has no grammar block")
        XCTAssertEqual(grammar["sha256"], sha256Hex(of: try Data(contentsOf: dataURL("grammar.json"))))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd Packages/VerbKit && swift test --filter RealGrammarDataTests 2>&1 | grep -E "error|failed|Executed" | head
```

Expected: failures. `nd_*` values are `nil`, and `grammar.json` does not exist.

- [ ] **Step 3: Write the lesson**

`data/grammar.json`:

```json
{
  "version": "1.0.0",
  "description": "Japanese grammar points for the JP Verb Conjugation app. Hand-authored; run scripts/update_data.py after editing.",
  "grammar": [
    {
      "id": "n-desu",
      "title": "んです",
      "summary": "Marks a sentence as explanation, context or reason. Use んです after verbs and い-adjectives, and なんです after nouns and な-adjectives.",
      "level": "beginner",
      "usages": [
        {
          "heading": "Asking for or giving a reason",
          "explanation": "The most basic use. A question with んですか asks for the story behind something you can see or have just heard, and a statement with んです supplies it.",
          "examples": [
            { "jp": "どうしたんですか。頭が痛いんです。", "en": "What's wrong? I have a headache." },
            { "jp": "どうして遅れたんですか。電車が止まったんです。", "en": "Why were you late? The train stopped." }
          ]
        },
        {
          "heading": "Softening a request or a lead-in",
          "explanation": "Before asking for something, んですが or んですけど sets the scene and leaves the request unsaid. It sounds much gentler than asking outright.",
          "examples": [
            { "jp": "すみません、道を聞きたいんですが。", "en": "Excuse me, I'd like to ask for directions." },
            { "jp": "ちょっと手伝ってほしいんですけど。", "en": "I'd like a little help, if that's okay." }
          ]
        },
        {
          "heading": "Refusing with a reason",
          "explanation": "Turning a refusal into an explanation makes it softer and more polite than a flat no. Verbs in the potential form are very common here.",
          "examples": [
            { "jp": "すみません、今日は行けないんです。", "en": "Sorry, I can't go today." },
            { "jp": "お酒は飲めないんです。", "en": "I can't drink alcohol." }
          ]
        },
        {
          "heading": "Reacting to something you noticed",
          "explanation": "With ね, んです shows you have just realized or been impressed by something.",
          "examples": [
            { "jp": "日本語が上手なんですね。", "en": "Your Japanese is good, isn't it. I'm impressed." },
            { "jp": "外は雨が降っているんですね。", "en": "So it's raining outside." }
          ]
        },
        {
          "heading": "Emphasis and background",
          "explanation": "Use it to give the background to what you are about to say, to correct an assumption, or to put the focus on one part of the sentence.",
          "examples": [
            { "jp": "実は、まだ食べていないんです。", "en": "Actually, I haven't eaten yet." },
            { "jp": "昨日買ったのは、この本なんです。", "en": "What I bought yesterday is this book." }
          ]
        },
        {
          "heading": "Checking an inference",
          "explanation": "You have guessed something from what you can see or hear, and you ask whether you are right.",
          "examples": [
            { "jp": "疲れているんですか。", "en": "Are you tired? (You look it.)" },
            { "jp": "日本に住んでいたんですか。", "en": "So you used to live in Japan?" }
          ]
        },
        {
          "heading": "Acknowledging what someone told you",
          "explanation": "Saying そうなんですか shows you have taken in new information: \"oh, is that so?\" The casual version is そうなんだ.",
          "examples": [
            { "jp": "来月、京都に行くんです。そうなんですか。", "en": "I'm going to Kyoto next month. Oh, really?" },
            { "jp": "来週、引っ越すんだ。そうなんだ。", "en": "I'm moving next week. Oh, I see." }
          ]
        }
      ],
      "attachment": [
        {
          "word_class": "verb",
          "pattern": "plain form + んです",
          "example": "食べるんです / 食べないんです / 食べたんです / 食べなかったんです",
          "note": "The polite form never comes before it: 食べますんです is wrong."
        },
        {
          "word_class": "i-adjective",
          "pattern": "plain form + んです",
          "example": "高いんです / 高くないんです / 高かったんです / 高くなかったんです"
        },
        {
          "word_class": "na-adjective",
          "condition": "non-past, affirmative",
          "pattern": "stem + なんです",
          "example": "静かなんです",
          "note": "The な is the plain だ turning into な before の, which is why it only appears here."
        },
        {
          "word_class": "noun",
          "condition": "non-past, affirmative",
          "pattern": "noun + なんです",
          "example": "学生なんです"
        },
        {
          "word_class": "na-adjective",
          "condition": "past or negative",
          "pattern": "stem + だった / じゃない + んです",
          "example": "静かだったんです / 静かじゃないんです"
        },
        {
          "word_class": "noun",
          "condition": "past or negative",
          "pattern": "noun + だった / じゃない + んです",
          "example": "学生だったんです / 学生じゃないんです"
        }
      ],
      "conjugations": [
        { "form": "んです", "register": "polite" },
        { "form": "んですか", "register": "polite", "note": "Asks for an explanation." },
        { "form": "んですが / んですけど", "register": "polite", "note": "Sets the scene, often before a request." },
        { "form": "んですね", "register": "polite", "note": "Reacts to something you just noticed." },
        { "form": "んじゃないですか", "register": "polite", "note": "\"Isn't it that...?\" Used to suggest or double-check." },
        { "form": "んじゃありません", "register": "polite", "note": "Denies the explanation. After a plain verb it can also mean \"don't do it!\" (see Watch out)." },
        { "form": "んでした", "register": "polite", "note": "Rare. The past normally goes on the verb instead: 食べたんです." },
        { "form": "んだ", "register": "casual" },
        { "form": "んだよ", "register": "casual", "note": "Adds \"you know\" when telling someone." },
        { "form": "の？ / んだ？", "register": "casual", "note": "A casual question. の？ is very common and neutral." },
        { "form": "の", "register": "casual", "note": "As a statement (行くの。) it sounds softer and, for many speakers, feminine." },
        { "form": "んじゃない", "register": "casual" },
        { "form": "のです", "register": "formal", "note": "The written or formal version of んです." },
        { "form": "のだ", "register": "formal" },
        { "form": "のではありません", "register": "formal" }
      ],
      "pitfalls": [
        {
          "heading": "Negating it is not a plain refusal",
          "explanation": "食べないんです explains why you are not eating. But 食べるんじゃない (or 食べるんじゃありません) is a strong \"don't eat!\", and 食べたんじゃない means \"it's not that I ate\".",
          "examples": [
            { "jp": "今は食べないんです。", "en": "I'm not eating right now (and there's a reason)." },
            { "jp": "そんなに食べるんじゃない。", "en": "Don't eat so much!" },
            { "jp": "食べたんじゃないんです。", "en": "It's not that I ate it." }
          ]
        },
        {
          "heading": "Don't overuse it",
          "explanation": "For plain new information, use the ordinary polite form. Adding んです makes a sentence sound like an explanation. And んですか asks for one, so it can sound probing or, in the wrong tone, demanding or aggressive. It is not a neutral question marker.",
          "examples": [
            { "jp": "毎日学校に行きます。", "en": "I go to school every day. (a plain statement)" },
            { "jp": "毎日学校に行くんです。", "en": "I go to school every day. (explaining, e.g. why you get up early)" }
          ]
        },
        {
          "heading": "The past goes on the verb",
          "explanation": "To explain something that happened, put the past tense on the verb before んです. 〜んでした exists but is rare.",
          "examples": [
            { "jp": "昨日は早く寝たんです。", "en": "I went to bed early yesterday." }
          ]
        }
      ],
      "related": []
    }
  ]
}
```

- [ ] **Step 4: Run the script**

```bash
python3 scripts/update_data.py
```

Expected output:

```
updated data/verbs.json
updated data/manifest.json (verbs 1.1.0, grammar 1.0.0)
```

- [ ] **Step 5: Check the data changes are what you expect**

```bash
git diff --stat data/
python3 scripts/update_data.py --check
cat data/manifest.json
```

Expected: `verbs.json` gains eight `nd_*` lines per verb across 25 verbs (about 230 insertions, 27 deletions including the trailing comma on each verb's previously-last form). `manifest.json` has version `1.1.0`, a fresh `sha256`, and a `grammar` block at `1.0.0`. `--check` prints `data is up to date`. The manifest should contain `"sha256": "1ea0408b78db165c9b31bb574b0b242a3201871bac4c3845a1e88aa42965cdaf"` and grammar `"52564ae50911554f78b900df9c862e396f433d06609cd3ad95e96eda695bd8e2"` — the script is deterministic, so a different hash means the inputs differ.

- [ ] **Step 6: Run the whole suite**

```bash
cd Packages/VerbKit && swift test 2>&1 | grep -E "error:|failed|Executed .* tests" | tail -1
```

Expected: `Executed 68 tests, with 0 failures`, which includes `main`'s `RealDataFileTests` passing against the regenerated manifest.

- [ ] **Step 7: Commit**

```bash
git add data Packages/VerbKit/Tests/VerbKitTests/RealGrammarDataTests.swift
git commit -m "$(cat <<'EOF'
Publish the んです / なんです lesson and per-verb んです forms

Adds data/grammar.json (seven usages, six attachment rules, the ending's
own conjugations, three pitfalls), fills nd_* on all 25 verbs, and adds a
grammar block to the manifest. RealGrammarDataTests pins the nd_* values,
the lesson's shape, and that the manifest's grammar hash matches the file.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Grammar sync (fetcher, sync state, `GrammarSyncService`)

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Data/GrammarManifest.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Data/GrammarSyncService.swift`
- Modify: `Packages/VerbKit/Sources/VerbKit/Data/VerbDataFetching.swift`, `SyncStateStoring.swift`, `UserDefaultsSyncStateStore.swift`, `GitHubVerbFetcher.swift`
- Modify: `Packages/VerbKit/Tests/VerbKitTests/VerbSyncServiceTests.swift` (mocks), `GitHubVerbFetcherTests.swift`
- Create: `Packages/VerbKit/Tests/VerbKitTests/GrammarTestSupport.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/GrammarSyncServiceTests.swift`

**Interfaces:**
- Consumes: `GrammarDataFile`, `GrammarPoint` (Task 1), `sha256Hex(of:)`, `VerbSyncError`.
- Produces: `GrammarManifest(version:sha256:)`; `VerbDataFetching.fetchGrammarManifest() async throws -> GrammarManifest?` (`nil` = no grammar published) and `fetchGrammarData() async throws -> Data`; `SyncStateStoring.lastSyncedGrammarManifest()` / `saveLastSyncedGrammarManifest(_:)`; `GitHubVerbFetcher.init(manifestURL:verbsURL:grammarURL:session:)`; `GrammarSyncService(fetcher:syncState:)` with `sync() async throws -> GrammarSyncResult` (`.upToDate` or `.updated(manifest:points:)`, **recording nothing**) and `confirmSynced(_ manifest: GrammarManifest)`; test helpers `GrammarFixture.json/data/points` (used by Tasks 6–8) and grammar members on `MockVerbDataFetcher` / `InMemorySyncStateStore`.

- [ ] **Step 1: Add the shared grammar test fixture**

`Packages/VerbKit/Tests/VerbKitTests/GrammarTestSupport.swift`:

```swift
import Foundation
@testable import VerbKit

/// A small, valid grammar file shared by the grammar sync, persistence,
/// store, search and route tests.
enum GrammarFixture {
    static let json = """
    {
      "version": "test-fixture",
      "description": "Fixture for grammar tests.",
      "grammar": [
        {
          "id": "n-desu",
          "title": "んです",
          "summary": "Marks explanation. なんです after nouns and な-adjectives.",
          "level": "beginner",
          "usages": [
            {
              "heading": "Giving a reason",
              "explanation": "Explains why.",
              "examples": [ { "jp": "頭が痛いんです。", "en": "I have a headache." } ]
            }
          ],
          "attachment": [
            { "word_class": "verb", "pattern": "plain form + んです", "example": "食べるんです" }
          ],
          "conjugations": [ { "form": "んです", "register": "polite" } ],
          "pitfalls": [],
          "related": [ "wake-desu" ]
        },
        {
          "id": "wake-desu",
          "title": "わけです",
          "summary": "Marks a logical conclusion.",
          "level": "intermediate",
          "usages": [
            {
              "heading": "Conclusion",
              "explanation": "That is why.",
              "examples": [ { "jp": "だから太ったわけです。", "en": "So that's why I gained weight." } ]
            }
          ],
          "attachment": [],
          "conjugations": [],
          "pitfalls": [],
          "related": []
        }
      ]
    }
    """

    static var data: Data { Data(json.utf8) }

    static var points: [GrammarPoint] {
        // Force-try is fine: the fixture is a compile-time constant.
        try! JSONDecoder().decode(GrammarDataFile.self, from: data).grammar
    }
}
```

- [ ] **Step 2: Write the sync service tests**

`Packages/VerbKit/Tests/VerbKitTests/GrammarSyncServiceTests.swift`:

```swift
import XCTest
@testable import VerbKit

final class GrammarSyncServiceTests: XCTestCase {
    private func manifest(for data: Data, version: String = "1.0.0") -> GrammarManifest {
        GrammarManifest(version: version, sha256: sha256Hex(of: data))
    }

    func testNoGrammarEntryInManifestIsUpToDate() async throws {
        let fetcher = MockVerbDataFetcher()
        fetcher.grammarManifestResult = .success(nil)
        fetcher.grammarDataResult = .failure(VerbSyncError.serverUnreachable) // must not be called

        let service = GrammarSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore())
        let result = try await service.sync()

        XCTAssertEqual(result, .upToDate)
    }

    func testUnchangedConfirmedManifestSkipsGrammarDataFetch() async throws {
        let entry = manifest(for: GrammarFixture.data)
        let fetcher = MockVerbDataFetcher()
        fetcher.grammarManifestResult = .success(entry)
        fetcher.grammarDataResult = .failure(VerbSyncError.serverUnreachable) // must not be called

        let syncState = InMemorySyncStateStore()
        syncState.saveLastSyncedGrammarManifest(entry)

        let result = try await GrammarSyncService(fetcher: fetcher, syncState: syncState).sync()
        XCTAssertEqual(result, .upToDate)
    }

    func testChangedManifestFetchesAndDecodesButDoesNotRecordState() async throws {
        let entry = manifest(for: GrammarFixture.data, version: "1.1.0")
        let fetcher = MockVerbDataFetcher()
        fetcher.grammarManifestResult = .success(entry)
        fetcher.grammarDataResult = .success(GrammarFixture.data)

        let syncState = InMemorySyncStateStore()
        let result = try await GrammarSyncService(fetcher: fetcher, syncState: syncState).sync()

        guard case let .updated(updatedManifest, points) = result else {
            return XCTFail("expected .updated")
        }
        XCTAssertEqual(updatedManifest, entry)
        XCTAssertEqual(points.map(\.id), ["n-desu", "wake-desu"])
        // Recording is the caller's job, after it has persisted the points.
        XCTAssertNil(syncState.lastSyncedGrammarManifest())
    }

    func testConfirmSyncedRecordsTheManifestOnlyWhenCalled() async throws {
        let entry = manifest(for: GrammarFixture.data)
        let fetcher = MockVerbDataFetcher()
        fetcher.grammarManifestResult = .success(entry)
        fetcher.grammarDataResult = .success(GrammarFixture.data)

        let syncState = InMemorySyncStateStore()
        let service = GrammarSyncService(fetcher: fetcher, syncState: syncState)
        _ = try await service.sync()
        XCTAssertNil(syncState.lastSyncedGrammarManifest())

        service.confirmSynced(entry)
        XCTAssertEqual(syncState.lastSyncedGrammarManifest(), entry)
        // After confirming, the same manifest is up to date.
        let again = try await service.sync()
        XCTAssertEqual(again, .upToDate)
    }

    func testGrammarSyncDoesNotTouchVerbSyncState() async throws {
        let entry = manifest(for: GrammarFixture.data)
        let fetcher = MockVerbDataFetcher()
        fetcher.grammarManifestResult = .success(entry)
        fetcher.grammarDataResult = .success(GrammarFixture.data)

        let syncState = InMemorySyncStateStore()
        let service = GrammarSyncService(fetcher: fetcher, syncState: syncState)
        _ = try await service.sync()
        service.confirmSynced(entry)

        XCTAssertNil(syncState.lastSyncedManifest())
    }

    func testHashMismatchThrowsMalformedData() async throws {
        let fetcher = MockVerbDataFetcher()
        fetcher.grammarManifestResult = .success(GrammarManifest(version: "1.1.0", sha256: "not-the-real-hash"))
        fetcher.grammarDataResult = .success(GrammarFixture.data)

        let syncState = InMemorySyncStateStore()
        do {
            _ = try await GrammarSyncService(fetcher: fetcher, syncState: syncState).sync()
            XCTFail("expected malformedData")
        } catch VerbSyncError.malformedData {
            XCTAssertNil(syncState.lastSyncedGrammarManifest())
        }
    }

    func testMalformedJSONThrowsMalformedData() async throws {
        let bad = Data("not json".utf8)
        let fetcher = MockVerbDataFetcher()
        fetcher.grammarManifestResult = .success(manifest(for: bad))
        fetcher.grammarDataResult = .success(bad)

        do {
            _ = try await GrammarSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore()).sync()
            XCTFail("expected malformedData")
        } catch VerbSyncError.malformedData {
            // expected
        }
    }

    func testOfflineErrorPropagates() async throws {
        let fetcher = MockVerbDataFetcher()
        fetcher.grammarManifestResult = .failure(VerbSyncError.offline)

        do {
            _ = try await GrammarSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore()).sync()
            XCTFail("expected offline")
        } catch VerbSyncError.offline {
            // expected
        }
    }
}
```

- [ ] **Step 3: Extend the existing test mocks and fetcher tests**

Apply these diffs. The first only replaces the two mock classes at the bottom of the file, leaving `main`'s newer sync tests alone; the second adds a `grammarURL` constant, updates the three existing initializer calls, and adds fetcher tests. `grammarManifestResult` defaults to "no grammar published", so existing verb-only tests are unaffected.

```diff
diff --git a/Packages/VerbKit/Tests/VerbKitTests/VerbSyncServiceTests.swift b/Packages/VerbKit/Tests/VerbKitTests/VerbSyncServiceTests.swift
index bb4f3e9..2593734 100644
--- a/Packages/VerbKit/Tests/VerbKitTests/VerbSyncServiceTests.swift
+++ b/Packages/VerbKit/Tests/VerbKitTests/VerbSyncServiceTests.swift
@@ -114,13 +114,21 @@ final class VerbSyncServiceTests: XCTestCase {
 final class MockVerbDataFetcher: VerbDataFetching, @unchecked Sendable {
     var manifestResult: Result<VerbManifest, Error> = .failure(VerbSyncError.offline)
     var verbDataResult: Result<Data, Error> = .failure(VerbSyncError.offline)
+    /// Defaults to "no grammar published" so verb-only tests are unaffected.
+    var grammarManifestResult: Result<GrammarManifest?, Error> = .success(nil)
+    var grammarDataResult: Result<Data, Error> = .failure(VerbSyncError.offline)
 
     func fetchManifest() async throws -> VerbManifest { try manifestResult.get() }
     func fetchVerbData() async throws -> Data { try verbDataResult.get() }
+    func fetchGrammarManifest() async throws -> GrammarManifest? { try grammarManifestResult.get() }
+    func fetchGrammarData() async throws -> Data { try grammarDataResult.get() }
 }
 
 final class InMemorySyncStateStore: SyncStateStoring, @unchecked Sendable {
     private var manifest: VerbManifest?
+    private var grammarManifest: GrammarManifest?
     func lastSyncedManifest() -> VerbManifest? { manifest }
     func saveLastSyncedManifest(_ manifest: VerbManifest) { self.manifest = manifest }
+    func lastSyncedGrammarManifest() -> GrammarManifest? { grammarManifest }
+    func saveLastSyncedGrammarManifest(_ manifest: GrammarManifest) { grammarManifest = manifest }
 }
```

```diff
diff --git a/Packages/VerbKit/Tests/VerbKitTests/GitHubVerbFetcherTests.swift b/Packages/VerbKit/Tests/VerbKitTests/GitHubVerbFetcherTests.swift
index 16ed2eb..20e6201 100644
--- a/Packages/VerbKit/Tests/VerbKitTests/GitHubVerbFetcherTests.swift
+++ b/Packages/VerbKit/Tests/VerbKitTests/GitHubVerbFetcherTests.swift
@@ -10,6 +10,7 @@ final class GitHubVerbFetcherTests: XCTestCase {
 
     private let manifestURL = URL(string: "https://raw.githubusercontent.com/example/repo/main/data/manifest.json")!
     private let verbsURL = URL(string: "https://raw.githubusercontent.com/example/repo/main/data/verbs.json")!
+    private let grammarURL = URL(string: "https://raw.githubusercontent.com/example/repo/main/data/grammar.json")!
 
     override func tearDown() {
         StubURLProtocol.handler = nil
@@ -22,7 +23,7 @@ final class GitHubVerbFetcherTests: XCTestCase {
             let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
             return (response, json)
         }
-        let fetcher = GitHubVerbFetcher(manifestURL: manifestURL, verbsURL: verbsURL, session: makeSession())
+        let fetcher = GitHubVerbFetcher(manifestURL: manifestURL, verbsURL: verbsURL, grammarURL: grammarURL, session: makeSession())
 
         let manifest = try await fetcher.fetchManifest()
         XCTAssertEqual(manifest, VerbManifest(version: "1.0.0", sha256: "abc"))
@@ -33,7 +34,7 @@ final class GitHubVerbFetcherTests: XCTestCase {
             let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
             return (response, Data())
         }
-        let fetcher = GitHubVerbFetcher(manifestURL: manifestURL, verbsURL: verbsURL, session: makeSession())
+        let fetcher = GitHubVerbFetcher(manifestURL: manifestURL, verbsURL: verbsURL, grammarURL: grammarURL, session: makeSession())
 
         do {
             _ = try await fetcher.fetchManifest()
@@ -45,7 +46,7 @@ final class GitHubVerbFetcherTests: XCTestCase {
 
     func testFetchManifestMapsOfflineURLErrorToOffline() async throws {
         StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
-        let fetcher = GitHubVerbFetcher(manifestURL: manifestURL, verbsURL: verbsURL, session: makeSession())
+        let fetcher = GitHubVerbFetcher(manifestURL: manifestURL, verbsURL: verbsURL, grammarURL: grammarURL, session: makeSession())
 
         do {
             _ = try await fetcher.fetchManifest()
@@ -54,6 +55,66 @@ final class GitHubVerbFetcherTests: XCTestCase {
             // expected
         }
     }
+
+    func testFetchGrammarManifestReadsTheGrammarBlock() async throws {
+        let json = Data(#"{"version": "1.1.0", "sha256": "abc", "grammar": {"version": "2.0.0", "sha256": "def"}}"#.utf8)
+        StubURLProtocol.handler = { request in
+            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
+        }
+        let fetcher = GitHubVerbFetcher(manifestURL: manifestURL, verbsURL: verbsURL, grammarURL: grammarURL, session: makeSession())
+
+        let grammar = try await fetcher.fetchGrammarManifest()
+        XCTAssertEqual(grammar, GrammarManifest(version: "2.0.0", sha256: "def"))
+    }
+
+    func testFetchGrammarManifestIsNilWithoutAGrammarBlock() async throws {
+        let json = Data(#"{"version": "1.0.0", "sha256": "abc"}"#.utf8)
+        StubURLProtocol.handler = { request in
+            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
+        }
+        let fetcher = GitHubVerbFetcher(manifestURL: manifestURL, verbsURL: verbsURL, grammarURL: grammarURL, session: makeSession())
+
+        let grammar = try await fetcher.fetchGrammarManifest()
+        XCTAssertNil(grammar)
+    }
+
+    /// Builds already installed must keep working once the manifest gains a grammar block.
+    func testVerbManifestStillDecodesWhenGrammarBlockIsPresent() async throws {
+        let json = Data(#"{"version": "1.1.0", "sha256": "abc", "grammar": {"version": "2.0.0", "sha256": "def"}}"#.utf8)
+        StubURLProtocol.handler = { request in
+            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
+        }
+        let fetcher = GitHubVerbFetcher(manifestURL: manifestURL, verbsURL: verbsURL, grammarURL: grammarURL, session: makeSession())
+
+        let manifest = try await fetcher.fetchManifest()
+        XCTAssertEqual(manifest, VerbManifest(version: "1.1.0", sha256: "abc"))
+    }
+
+    func testFetchGrammarDataRequestsTheGrammarURL() async throws {
+        let body = Data("grammar-bytes".utf8)
+        StubURLProtocol.handler = { request in
+            XCTAssertEqual(request.url?.lastPathComponent, "grammar.json")
+            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
+        }
+        let fetcher = GitHubVerbFetcher(manifestURL: manifestURL, verbsURL: verbsURL, grammarURL: grammarURL, session: makeSession())
+
+        let data = try await fetcher.fetchGrammarData()
+        XCTAssertEqual(data, body)
+    }
+
+    func testFetchGrammarManifestMapsMalformedManifestToMalformedData() async throws {
+        StubURLProtocol.handler = { request in
+            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("nope".utf8))
+        }
+        let fetcher = GitHubVerbFetcher(manifestURL: manifestURL, verbsURL: verbsURL, grammarURL: grammarURL, session: makeSession())
+
+        do {
+            _ = try await fetcher.fetchGrammarManifest()
+            XCTFail("expected malformedData")
+        } catch VerbSyncError.malformedData {
+            // expected
+        }
+    }
 }
 
 private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
```

- [ ] **Step 4: Run the tests to verify they fail**

```bash
cd Packages/VerbKit && swift test 2>&1 | grep -E "error:" | head -5
```

Expected: build errors such as `cannot find 'GrammarManifest' in scope`.

- [ ] **Step 5: Implement the sync layer**

New files:

`Packages/VerbKit/Sources/VerbKit/Data/GrammarManifest.swift`:

```swift
/// The optional `grammar` block of `manifest.json`. It has the same shape
/// as `VerbManifest` but is a separate type on purpose: `VerbManifest`
/// compares by whole-struct equality to decide whether verbs changed, so
/// nesting grammar inside it would make a grammar edit re-download verbs.
public struct GrammarManifest: Codable, Equatable, Sendable {
    public var version: String
    public var sha256: String

    public init(version: String, sha256: String) {
        self.version = version
        self.sha256 = sha256
    }
}
```

`Packages/VerbKit/Sources/VerbKit/Data/GrammarSyncService.swift`:

```swift
import Foundation

public enum GrammarSyncResult: Equatable, Sendable {
    case upToDate
    case updated(manifest: GrammarManifest, points: [GrammarPoint])
}

/// Mirrors `VerbSyncService` for `grammar.json`, including its contract:
/// `sync()` does not record anything as synced. The caller persists the
/// points and only then calls `confirmSynced(_:)`, so a persistence
/// failure can't be mistaken for "nothing changed" on the next attempt.
///
/// It is deliberately a second concrete service, not a generic one: with
/// two users an abstraction isn't earning its keep yet.
public struct GrammarSyncService: Sendable {
    private let fetcher: VerbDataFetching
    private let syncState: SyncStateStoring

    public init(fetcher: VerbDataFetching, syncState: SyncStateStoring) {
        self.fetcher = fetcher
        self.syncState = syncState
    }

    /// Fetches the manifest's `grammar` entry. No entry, or an entry
    /// unchanged since the last confirmed sync, returns `.upToDate`
    /// without fetching grammar data. Otherwise fetches it, verifies its
    /// hash (a mismatch is corrupted/incomplete data), decodes it, and
    /// returns the points. Does NOT record the manifest as synced.
    public func sync() async throws -> GrammarSyncResult {
        guard let manifest = try await fetcher.fetchGrammarManifest() else {
            return .upToDate
        }
        if let last = syncState.lastSyncedGrammarManifest(), last == manifest {
            return .upToDate
        }

        let data = try await fetcher.fetchGrammarData()
        guard sha256Hex(of: data) == manifest.sha256 else {
            throw VerbSyncError.malformedData
        }

        let decoded: GrammarDataFile
        do {
            decoded = try JSONDecoder().decode(GrammarDataFile.self, from: data)
        } catch {
            throw VerbSyncError.malformedData
        }

        return .updated(manifest: manifest, points: decoded.grammar)
    }

    /// Records `manifest` as the last successfully synced grammar
    /// manifest. Call only after the points that came with it have been
    /// durably persisted.
    public func confirmSynced(_ manifest: GrammarManifest) {
        syncState.saveLastSyncedGrammarManifest(manifest)
    }
}
```

Modified files (apply each diff; note `GitHubVerbFetcher.swift` on `main` no longer maps `.timedOut` to offline, and the diff leaves that alone):

```diff
diff --git a/Packages/VerbKit/Sources/VerbKit/Data/VerbDataFetching.swift b/Packages/VerbKit/Sources/VerbKit/Data/VerbDataFetching.swift
index 25a5151..f9c7a35 100644
--- a/Packages/VerbKit/Sources/VerbKit/Data/VerbDataFetching.swift
+++ b/Packages/VerbKit/Sources/VerbKit/Data/VerbDataFetching.swift
@@ -3,4 +3,8 @@ import Foundation
 public protocol VerbDataFetching: Sendable {
     func fetchManifest() async throws -> VerbManifest
     func fetchVerbData() async throws -> Data
+
+    /// The manifest's `grammar` entry, or `nil` if none is published.
+    func fetchGrammarManifest() async throws -> GrammarManifest?
+    func fetchGrammarData() async throws -> Data
 }
```

```diff
diff --git a/Packages/VerbKit/Sources/VerbKit/Data/SyncStateStoring.swift b/Packages/VerbKit/Sources/VerbKit/Data/SyncStateStoring.swift
index e83e213..79b92f7 100644
--- a/Packages/VerbKit/Sources/VerbKit/Data/SyncStateStoring.swift
+++ b/Packages/VerbKit/Sources/VerbKit/Data/SyncStateStoring.swift
@@ -1,4 +1,7 @@
 public protocol SyncStateStoring: Sendable {
     func lastSyncedManifest() -> VerbManifest?
     func saveLastSyncedManifest(_ manifest: VerbManifest)
+
+    func lastSyncedGrammarManifest() -> GrammarManifest?
+    func saveLastSyncedGrammarManifest(_ manifest: GrammarManifest)
 }
```

```diff
diff --git a/Packages/VerbKit/Sources/VerbKit/Data/UserDefaultsSyncStateStore.swift b/Packages/VerbKit/Sources/VerbKit/Data/UserDefaultsSyncStateStore.swift
index 12f342a..7595d38 100644
--- a/Packages/VerbKit/Sources/VerbKit/Data/UserDefaultsSyncStateStore.swift
+++ b/Packages/VerbKit/Sources/VerbKit/Data/UserDefaultsSyncStateStore.swift
@@ -4,6 +4,8 @@ public final class UserDefaultsSyncStateStore: SyncStateStoring, @unchecked Send
     private let defaults: UserDefaults
     private let versionKey = "VerbKit.lastSyncedManifest.version"
     private let hashKey = "VerbKit.lastSyncedManifest.sha256"
+    private let grammarVersionKey = "VerbKit.lastSyncedGrammarManifest.version"
+    private let grammarHashKey = "VerbKit.lastSyncedGrammarManifest.sha256"
 
     public init(defaults: UserDefaults = .standard) {
         self.defaults = defaults
@@ -19,4 +21,15 @@ public final class UserDefaultsSyncStateStore: SyncStateStoring, @unchecked Send
         defaults.set(manifest.version, forKey: versionKey)
         defaults.set(manifest.sha256, forKey: hashKey)
     }
+
+    public func lastSyncedGrammarManifest() -> GrammarManifest? {
+        guard let version = defaults.string(forKey: grammarVersionKey),
+              let sha256 = defaults.string(forKey: grammarHashKey) else { return nil }
+        return GrammarManifest(version: version, sha256: sha256)
+    }
+
+    public func saveLastSyncedGrammarManifest(_ manifest: GrammarManifest) {
+        defaults.set(manifest.version, forKey: grammarVersionKey)
+        defaults.set(manifest.sha256, forKey: grammarHashKey)
+    }
 }
```

```diff
diff --git a/Packages/VerbKit/Sources/VerbKit/Data/GitHubVerbFetcher.swift b/Packages/VerbKit/Sources/VerbKit/Data/GitHubVerbFetcher.swift
index 15a6eed..ad677d7 100644
--- a/Packages/VerbKit/Sources/VerbKit/Data/GitHubVerbFetcher.swift
+++ b/Packages/VerbKit/Sources/VerbKit/Data/GitHubVerbFetcher.swift
@@ -3,11 +3,13 @@ import Foundation
 public struct GitHubVerbFetcher: VerbDataFetching {
     private let manifestURL: URL
     private let verbsURL: URL
+    private let grammarURL: URL
     private let session: URLSession
 
-    public init(manifestURL: URL, verbsURL: URL, session: URLSession = .shared) {
+    public init(manifestURL: URL, verbsURL: URL, grammarURL: URL, session: URLSession = .shared) {
         self.manifestURL = manifestURL
         self.verbsURL = verbsURL
+        self.grammarURL = grammarURL
         self.session = session
     }
 
@@ -24,6 +26,24 @@ public struct GitHubVerbFetcher: VerbDataFetching {
         try await fetchData(from: verbsURL)
     }
 
+    public func fetchGrammarManifest() async throws -> GrammarManifest? {
+        let data = try await fetchData(from: manifestURL)
+        do {
+            return try JSONDecoder().decode(ManifestFile.self, from: data).grammar
+        } catch {
+            throw VerbSyncError.malformedData
+        }
+    }
+
+    public func fetchGrammarData() async throws -> Data {
+        try await fetchData(from: grammarURL)
+    }
+
+    /// Just the part of `manifest.json` that carries the grammar entry.
+    private struct ManifestFile: Decodable {
+        let grammar: GrammarManifest?
+    }
+
     private func fetchData(from url: URL) async throws -> Data {
         let data: Data
         let response: URLResponse
@@ -51,6 +71,7 @@ public extension GitHubVerbFetcher {
         return GitHubVerbFetcher(
             manifestURL: URL(string: base + "manifest.json")!,
             verbsURL: URL(string: base + "verbs.json")!,
+            grammarURL: URL(string: base + "grammar.json")!,
             session: session
         )
     }
```

- [ ] **Step 6: Run the whole suite to verify it passes**

```bash
cd Packages/VerbKit && swift test 2>&1 | grep -E "error:|failed|Executed .* tests" | tail -1
```

Expected: `Executed 81 tests, with 0 failures` (68 so far, plus 8 sync-service and 5 fetcher tests).

- [ ] **Step 7: Commit**

```bash
git add Packages/VerbKit
git commit -m "$(cat <<'EOF'
Add grammar sync: fetcher, per-file sync state, GrammarSyncService

GrammarManifest is a separate type from VerbManifest on purpose: nesting
it would make a grammar edit re-download verbs, because VerbManifest
compares by whole-struct equality. Old app builds ignore the manifest's
new grammar block, and a manifest without one just means nothing to sync.

GrammarSyncService follows VerbSyncService's contract: sync() records
nothing, and the caller calls confirmSynced(_:) only after persisting.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Grammar persistence

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Persistence/GrammarPersisting.swift`, `GrammarEntity.swift`, `SwiftDataGrammarPersisting.swift`
- Modify: `Packages/VerbKit/Sources/VerbKit/Persistence/VerbModelContainer.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/SwiftDataGrammarPersistingTests.swift`

**Interfaces:**
- Consumes: `GrammarPoint` (Task 1), `GrammarFixture.points` (Task 5).
- Produces: `GrammarPersisting` (`@MainActor`; `loadAllGrammarPoints() throws -> [GrammarPoint]`, `replaceAllGrammarPoints(with:) throws`), `SwiftDataGrammarPersisting(modelContext:)`, `GrammarEntity`, and `VerbModelContainer`'s schema now includes `GrammarEntity` in both `make()` and `makeInMemory()`.

- [ ] **Step 1: Write the failing test**

`Packages/VerbKit/Tests/VerbKitTests/SwiftDataGrammarPersistingTests.swift`:

```swift
import XCTest
import SwiftData
@testable import VerbKit

@MainActor
final class SwiftDataGrammarPersistingTests: XCTestCase {
    private func makePersisting() throws -> SwiftDataGrammarPersisting {
        let container = try VerbModelContainer.makeInMemory()
        return SwiftDataGrammarPersisting(modelContext: ModelContext(container))
    }

    private func makePoint(id: String) -> GrammarPoint {
        GrammarPoint(
            id: id, title: id, summary: "s", level: .beginner,
            usages: [], attachment: [], conjugations: [], pitfalls: [], related: []
        )
    }

    func testLoadIsEmptyInitially() throws {
        XCTAssertEqual(try makePersisting().loadAllGrammarPoints(), [])
    }

    func testReplaceInsertsAndRoundTripsEveryField() throws {
        let persisting = try makePersisting()
        try persisting.replaceAllGrammarPoints(with: GrammarFixture.points)

        let loaded = try persisting.loadAllGrammarPoints()
        XCTAssertEqual(loaded, GrammarFixture.points)
    }

    func testAttachmentWordClassSurvivesTheRoundTrip() throws {
        let persisting = try makePersisting()
        try persisting.replaceAllGrammarPoints(with: GrammarFixture.points)

        let nDesu = try XCTUnwrap(try persisting.loadAllGrammarPoints().first { $0.id == "n-desu" })
        XCTAssertEqual(nDesu.attachment.first?.wordClass, .verb)
    }

    func testLoadPreservesAuthoredOrder() throws {
        let persisting = try makePersisting()
        let ids = ["c", "a", "d", "b"]
        try persisting.replaceAllGrammarPoints(with: ids.map(makePoint))

        XCTAssertEqual(try persisting.loadAllGrammarPoints().map(\.id), ids)
    }

    func testReplaceRemovesStaleEntries() throws {
        let persisting = try makePersisting()
        try persisting.replaceAllGrammarPoints(with: [makePoint(id: "old")])
        try persisting.replaceAllGrammarPoints(with: [makePoint(id: "new")])

        XCTAssertEqual(try persisting.loadAllGrammarPoints().map(\.id), ["new"])
    }

    func testGrammarAndVerbsShareOneContainerWithoutInterfering() throws {
        let container = try VerbModelContainer.makeInMemory()
        let context = ModelContext(container)
        let grammar = SwiftDataGrammarPersisting(modelContext: context)
        let verbs = SwiftDataVerbPersisting(modelContext: context)

        try grammar.replaceAllGrammarPoints(with: [makePoint(id: "g")])
        try verbs.replaceAllVerbs(with: [])

        XCTAssertEqual(try grammar.loadAllGrammarPoints().map(\.id), ["g"])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd Packages/VerbKit && swift test --filter SwiftDataGrammarPersistingTests 2>&1 | grep -E "error:" | head -3
```

Expected: `cannot find 'SwiftDataGrammarPersisting' in scope`.

- [ ] **Step 3: Implement persistence**

`Packages/VerbKit/Sources/VerbKit/Persistence/GrammarPersisting.swift`:

```swift
@MainActor
public protocol GrammarPersisting {
    func loadAllGrammarPoints() throws -> [GrammarPoint]
    func replaceAllGrammarPoints(with points: [GrammarPoint]) throws
}
```

`Packages/VerbKit/Sources/VerbKit/Persistence/GrammarEntity.swift`:

```swift
import Foundation
import SwiftData

@Model
public final class GrammarEntity {
    @Attribute(.unique) public var id: String

    /// Position in the source file, so lessons keep their authored order
    /// (a SwiftData fetch is otherwise unordered).
    public var sortOrder: Int

    // The whole point is stored as JSON `Data`, like `VerbEntity.forms`,
    // which sidesteps SwiftData's struct decomposition (it mishandles
    // custom `CodingKeys` such as `AttachmentRule`'s `word_class`) and
    // means adding a field to `GrammarPoint` needs no store migration.
    private var payload: Data

    public init(_ point: GrammarPoint, sortOrder: Int) {
        self.id = point.id
        self.sortOrder = sortOrder
        self.payload = (try? JSONEncoder().encode(point)) ?? Data()
    }

    /// `nil` if the stored payload can't be decoded by this build (e.g.
    /// cached by a newer app version) — callers skip such rows.
    public func toGrammarPoint() -> GrammarPoint? {
        try? JSONDecoder().decode(GrammarPoint.self, from: payload)
    }
}
```

`Packages/VerbKit/Sources/VerbKit/Persistence/SwiftDataGrammarPersisting.swift` (note `import Foundation`; `SortDescriptor` needs it):

```swift
import Foundation
import SwiftData

@MainActor
public final class SwiftDataGrammarPersisting: GrammarPersisting {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func loadAllGrammarPoints() throws -> [GrammarPoint] {
        let descriptor = FetchDescriptor<GrammarEntity>(sortBy: [SortDescriptor(\.sortOrder)])
        return try modelContext.fetch(descriptor).compactMap { $0.toGrammarPoint() }
    }

    public func replaceAllGrammarPoints(with points: [GrammarPoint]) throws {
        try modelContext.delete(model: GrammarEntity.self)
        for (index, point) in points.enumerated() {
            modelContext.insert(GrammarEntity(point, sortOrder: index))
        }
        try modelContext.save()
    }
}
```

Apply this diff to `VerbModelContainer.swift`:

```diff
diff --git a/Packages/VerbKit/Sources/VerbKit/Persistence/VerbModelContainer.swift b/Packages/VerbKit/Sources/VerbKit/Persistence/VerbModelContainer.swift
index a6a9712..9a3c797 100644
--- a/Packages/VerbKit/Sources/VerbKit/Persistence/VerbModelContainer.swift
+++ b/Packages/VerbKit/Sources/VerbKit/Persistence/VerbModelContainer.swift
@@ -11,7 +11,7 @@ public enum VerbModelContainer {
     /// The real, on-disk, App Group-shared store — used by the app and,
     /// later, the widget/Shortcuts extension.
     public static func make() throws -> ModelContainer {
-        let schema = Schema([VerbEntity.self])
+        let schema = Schema([VerbEntity.self, GrammarEntity.self])
         guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
             throw VerbModelContainerError.appGroupUnavailable
         }
@@ -22,7 +22,7 @@ public enum VerbModelContainer {
 
     /// An in-memory store for tests and previews — never touches disk.
     public static func makeInMemory() throws -> ModelContainer {
-        let schema = Schema([VerbEntity.self])
+        let schema = Schema([VerbEntity.self, GrammarEntity.self])
         let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
         return try ModelContainer(for: schema, configurations: [configuration])
     }
```

- [ ] **Step 4: Run the whole suite to verify it passes**

```bash
cd Packages/VerbKit && swift test 2>&1 | grep -E "error:|failed|Executed .* tests" | tail -1
```

Expected: `Executed 87 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Packages/VerbKit
git commit -m "$(cat <<'EOF'
Add SwiftData persistence for grammar points

GrammarEntity stores each point as JSON (like VerbEntity.forms, to avoid
SwiftData's struct decomposition mishandling custom CodingKeys) plus its
position in the source file, so lessons keep their authored order.
Shares the verb cache's ModelContainer.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: `VerbStore` grammar integration

**Files:**
- Modify: `Packages/VerbKit/Sources/VerbKit/Store/VerbStore.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/VerbStoreGrammarTests.swift`

**Interfaces:**
- Consumes: `GrammarSyncService` incl. `confirmSynced` (Task 5), `GrammarPersisting` (Task 6), `GrammarFixture`, `MockVerbDataFetcher`, `InMemorySyncStateStore`.
- Produces: `VerbStore.init(syncService:persisting:networkMonitor:grammarSyncService:grammarPersisting:)` (the last two default to `nil`, so existing call sites are unchanged), `VerbStore.grammarPoints: [GrammarPoint]`, `VerbStore.hasGrammar: Bool`, `VerbStore.retryGrammarSync() async`.

- [ ] **Step 1: Write the failing test**

`Packages/VerbKit/Tests/VerbKitTests/VerbStoreGrammarTests.swift`:

```swift
import XCTest
import SwiftData
@testable import VerbKit

@MainActor
final class VerbStoreGrammarTests: XCTestCase {
    private func verbData() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "verbs-fixture", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private struct Harness {
        let store: VerbStore
        let fetcher: MockVerbDataFetcher
        let verbPersisting: SwiftDataVerbPersisting
        let grammarPersisting: SwiftDataGrammarPersisting
        let syncState: InMemorySyncStateStore
    }

    /// A store wired for both verbs and grammar, with both syncs succeeding
    /// unless a test changes the mock.
    private func makeHarness() throws -> Harness {
        let verbBytes = try verbData()
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .success(VerbManifest(version: "1.0.0", sha256: sha256Hex(of: verbBytes)))
        fetcher.verbDataResult = .success(verbBytes)
        fetcher.grammarManifestResult = .success(GrammarManifest(version: "1.0.0", sha256: sha256Hex(of: GrammarFixture.data)))
        fetcher.grammarDataResult = .success(GrammarFixture.data)

        let container = try VerbModelContainer.makeInMemory()
        let context = ModelContext(container)
        let verbPersisting = SwiftDataVerbPersisting(modelContext: context)
        let grammarPersisting = SwiftDataGrammarPersisting(modelContext: context)
        let syncState = InMemorySyncStateStore()
        let store = VerbStore(
            syncService: VerbSyncService(fetcher: fetcher, syncState: syncState),
            persisting: verbPersisting,
            networkMonitor: NetworkMonitor(),
            grammarSyncService: GrammarSyncService(fetcher: fetcher, syncState: syncState),
            grammarPersisting: grammarPersisting
        )
        return Harness(store: store, fetcher: fetcher, verbPersisting: verbPersisting, grammarPersisting: grammarPersisting, syncState: syncState)
    }

    func testFirstLaunchSyncsGrammarAfterVerbs() async throws {
        let h = try makeHarness()

        await h.store.start()

        XCTAssertEqual(h.store.firstLaunchState, .success)
        XCTAssertEqual(h.store.grammarPoints.map(\.id), ["n-desu", "wake-desu"])
        XCTAssertTrue(h.store.hasGrammar)
        XCTAssertEqual(try h.grammarPersisting.loadAllGrammarPoints().count, 2)
    }

    func testGrammarFailureNeverAffectsVerbs() async throws {
        let h = try makeHarness()
        h.fetcher.grammarManifestResult = .failure(VerbSyncError.serverUnreachable)

        await h.store.start()

        XCTAssertEqual(h.store.firstLaunchState, .success)
        XCTAssertEqual(h.store.verbs.count, 2)
        XCTAssertTrue(h.store.grammarPoints.isEmpty)
        XCTAssertFalse(h.store.hasGrammar)
    }

    func testGrammarIsNotAttemptedWhenTheVerbFetchFails() async throws {
        let h = try makeHarness()
        h.fetcher.manifestResult = .failure(VerbSyncError.offline)

        await h.store.start()

        XCTAssertEqual(h.store.firstLaunchState, .failed(.offline))
        XCTAssertTrue(h.store.grammarPoints.isEmpty)
    }

    func testCachedGrammarLoadsEvenWhenOffline() async throws {
        let h = try makeHarness()
        try h.verbPersisting.replaceAllVerbs(with: JSONDecoder().decode(VerbDataFile.self, from: verbData()).verbs)
        try h.grammarPersisting.replaceAllGrammarPoints(with: GrammarFixture.points)
        h.fetcher.manifestResult = .failure(VerbSyncError.offline)
        h.fetcher.grammarManifestResult = .failure(VerbSyncError.offline)

        await h.store.start()

        XCTAssertEqual(h.store.grammarPoints.map(\.id), ["n-desu", "wake-desu"])
        XCTAssertEqual(h.store.verbs.count, 2)
    }

    func testCachedVerbsPathSyncsGrammarInTheBackground() async throws {
        let h = try makeHarness()
        try h.verbPersisting.replaceAllVerbs(with: JSONDecoder().decode(VerbDataFile.self, from: verbData()).verbs)

        await h.store.start()

        XCTAssertEqual(h.store.grammarPoints.count, 2)
    }

    func testRetryGrammarSyncRecoversAfterAFailure() async throws {
        let h = try makeHarness()
        h.fetcher.grammarManifestResult = .failure(VerbSyncError.offline)
        await h.store.start()
        XCTAssertTrue(h.store.grammarPoints.isEmpty)

        h.fetcher.grammarManifestResult = .success(GrammarManifest(version: "1.0.0", sha256: sha256Hex(of: GrammarFixture.data)))
        await h.store.retryGrammarSync()

        XCTAssertEqual(h.store.grammarPoints.count, 2)
    }

    // MARK: persistence failure (same contract as verbs)

    func testGrammarPersistenceFailureLeavesManifestUnconfirmedSoRetryRefetches() async throws {
        let entry = GrammarManifest(version: "1.0.0", sha256: sha256Hex(of: GrammarFixture.data))
        let verbBytes = try verbData()
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .success(VerbManifest(version: "1.0.0", sha256: sha256Hex(of: verbBytes)))
        fetcher.verbDataResult = .success(verbBytes)
        fetcher.grammarManifestResult = .success(entry)
        fetcher.grammarDataResult = .success(GrammarFixture.data)

        let container = try VerbModelContainer.makeInMemory()
        let syncState = InMemorySyncStateStore()
        let grammarPersisting = FailingGrammarPersisting(shouldFail: true)
        let store = VerbStore(
            syncService: VerbSyncService(fetcher: fetcher, syncState: syncState),
            persisting: SwiftDataVerbPersisting(modelContext: ModelContext(container)),
            networkMonitor: NetworkMonitor(),
            grammarSyncService: GrammarSyncService(fetcher: fetcher, syncState: syncState),
            grammarPersisting: grammarPersisting
        )

        await store.start()

        // Verbs are unaffected, and the failed grammar persist is not
        // recorded as synced.
        XCTAssertEqual(store.firstLaunchState, .success)
        XCTAssertEqual(store.verbs.count, 2)
        XCTAssertTrue(store.grammarPoints.isEmpty)
        XCTAssertNil(syncState.lastSyncedGrammarManifest())

        // Once persistence works again, a retry must really re-fetch
        // instead of short-circuiting to "up to date".
        grammarPersisting.shouldFail = false
        await store.retryGrammarSync()

        XCTAssertEqual(store.grammarPoints.count, 2)
        XCTAssertEqual(syncState.lastSyncedGrammarManifest(), entry)
    }

    func testSuccessfulGrammarSyncConfirmsTheManifestAfterPersisting() async throws {
        let h = try makeHarness()
        let entry = GrammarManifest(version: "1.0.0", sha256: sha256Hex(of: GrammarFixture.data))

        await h.store.start()

        XCTAssertEqual(h.syncState.lastSyncedGrammarManifest(), entry)
        XCTAssertEqual(try h.grammarPersisting.loadAllGrammarPoints().count, 2)
    }

    func testStoreWithoutGrammarDependenciesIgnoresGrammar() async throws {
        let verbBytes = try verbData()
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .success(VerbManifest(version: "1.0.0", sha256: sha256Hex(of: verbBytes)))
        fetcher.verbDataResult = .success(verbBytes)
        let container = try VerbModelContainer.makeInMemory()
        let store = VerbStore(
            syncService: VerbSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore()),
            persisting: SwiftDataVerbPersisting(modelContext: ModelContext(container)),
            networkMonitor: NetworkMonitor()
        )

        await store.start()
        await store.retryGrammarSync()

        XCTAssertEqual(store.verbs.count, 2)
        XCTAssertTrue(store.grammarPoints.isEmpty)
    }
}

/// A `GrammarPersisting` whose `replaceAllGrammarPoints(with:)` can be made
/// to throw on demand, to simulate a persistence failure.
private enum FailingGrammarPersistingError: Error {
    case persistFailed
}

@MainActor
private final class FailingGrammarPersisting: GrammarPersisting {
    var shouldFail: Bool
    private var stored: [GrammarPoint] = []

    init(shouldFail: Bool) {
        self.shouldFail = shouldFail
    }

    func loadAllGrammarPoints() throws -> [GrammarPoint] { stored }

    func replaceAllGrammarPoints(with points: [GrammarPoint]) throws {
        if shouldFail { throw FailingGrammarPersistingError.persistFailed }
        stored = points
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd Packages/VerbKit && swift test --filter VerbStoreGrammarTests 2>&1 | grep -E "error:" | head -3
```

Expected: `extra arguments at positions #4, #5 in call` (the store does not take grammar dependencies yet).

- [ ] **Step 3: Extend `VerbStore`**

Apply this diff. It only adds; the one removed line is the old `init` signature, and `main`'s `confirmSynced` handling for verbs is untouched:

```diff
diff --git a/Packages/VerbKit/Sources/VerbKit/Store/VerbStore.swift b/Packages/VerbKit/Sources/VerbKit/Store/VerbStore.swift
index 867ad1c..7aa0737 100644
--- a/Packages/VerbKit/Sources/VerbKit/Store/VerbStore.swift
+++ b/Packages/VerbKit/Sources/VerbKit/Store/VerbStore.swift
@@ -7,14 +7,29 @@ public final class VerbStore {
     public private(set) var firstLaunchState: FirstLaunchState = .checking
     public var hasLocalData: Bool { !verbs.isEmpty }
 
+    /// Grammar is non-blocking: empty until its first sync succeeds, and
+    /// a grammar failure never affects `verbs` or `firstLaunchState`.
+    public private(set) var grammarPoints: [GrammarPoint] = []
+    public var hasGrammar: Bool { !grammarPoints.isEmpty }
+
     private let syncService: VerbSyncService
     private let persisting: VerbPersisting
     private let networkMonitor: NetworkMonitor
+    private let grammarSyncService: GrammarSyncService?
+    private let grammarPersisting: GrammarPersisting?
 
-    public init(syncService: VerbSyncService, persisting: VerbPersisting, networkMonitor: NetworkMonitor) {
+    public init(
+        syncService: VerbSyncService,
+        persisting: VerbPersisting,
+        networkMonitor: NetworkMonitor,
+        grammarSyncService: GrammarSyncService? = nil,
+        grammarPersisting: GrammarPersisting? = nil
+    ) {
         self.syncService = syncService
         self.persisting = persisting
         self.networkMonitor = networkMonitor
+        self.grammarSyncService = grammarSyncService
+        self.grammarPersisting = grammarPersisting
     }
 
     public func start() async {
@@ -26,9 +41,12 @@ public final class VerbStore {
             }
         }
 
+        loadCachedGrammar()
+
         if let cached = try? persisting.loadAllVerbs(), !cached.isEmpty {
             verbs = cached
             await syncInBackground()
+            await syncGrammar()
             return
         }
 
@@ -39,6 +57,11 @@ public final class VerbStore {
         await runFirstLaunchFetch()
     }
 
+    /// Re-attempts the grammar sync, e.g. from the Grammar tab's Try Again.
+    public func retryGrammarSync() async {
+        await syncGrammar()
+    }
+
     private func runFirstLaunchFetch() async {
         firstLaunchState = .checking
         firstLaunchState = .fetching
@@ -61,6 +84,8 @@ public final class VerbStore {
                 syncService.confirmSynced(manifest)
                 verbs = fetchedVerbs
                 firstLaunchState = .success
+                // Verbs are the gate; grammar follows once they're in.
+                await syncGrammar()
             }
         } catch let error as VerbSyncError {
             firstLaunchState = .failed(error)
@@ -84,4 +109,27 @@ public final class VerbStore {
         syncService.confirmSynced(manifest)
         verbs = fetchedVerbs
     }
+
+    private func loadCachedGrammar() {
+        guard let grammarPersisting,
+              let cached = try? grammarPersisting.loadAllGrammarPoints() else { return }
+        grammarPoints = cached
+    }
+
+    /// Same contract as the verb sync: persist first, and only then
+    /// confirm the manifest, so a persistence failure leaves it
+    /// unrecorded and the next sync genuinely retries. Every failure
+    /// here is silent and never touches `verbs` or `firstLaunchState`.
+    private func syncGrammar() async {
+        guard let grammarSyncService, let grammarPersisting else { return }
+        guard let result = try? await grammarSyncService.sync() else { return }
+        guard case let .updated(manifest, points) = result else { return }
+        do {
+            try grammarPersisting.replaceAllGrammarPoints(with: points)
+        } catch {
+            return
+        }
+        grammarSyncService.confirmSynced(manifest)
+        grammarPoints = points
+    }
 }
```

- [ ] **Step 4: Run the whole suite to verify it passes**

```bash
cd Packages/VerbKit && swift test 2>&1 | grep -E "error:|failed|Executed .* tests" | tail -1
```

Expected: `Executed 96 tests, with 0 failures`. `main`'s existing `VerbStoreTests` passing unchanged shows the new parameters really are optional.

- [ ] **Step 5: Commit**

```bash
git add Packages/VerbKit
git commit -m "$(cat <<'EOF'
Sync grammar from VerbStore, non-blocking and after verbs

Grammar sync starts only once verbs are available and never changes
verbs or firstLaunchState when it fails. Like verbs, it persists first
and only then confirms the manifest, so a persistence failure leaves the
manifest unrecorded and the next sync retries. Cached grammar loads at
start, so lessons work offline. The grammar dependencies are optional
parameters, so existing call sites are unchanged.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Grammar search and `Route`

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Search/GrammarSearch.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Navigation/Route.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/GrammarSearchTests.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/RouteTests.swift`

**Interfaces:**
- Consumes: `GrammarPoint` (Task 1), `Verb`, `GrammarFixture` (Task 5).
- Produces: `matchesGrammarSearch(_:query:) -> Bool` (matches title, summary, and the Japanese text of usage examples); `Route` (`.verb(String)`, `.grammar(String)`; `Hashable, Sendable`); `RouteTarget` (`.verb(Verb)`, `.grammar(GrammarPoint)`); `Route.resolve(verbs:grammarPoints:) -> RouteTarget?` (returns `nil` when the target isn't available locally).

- [ ] **Step 1: Write the failing tests**

`Packages/VerbKit/Tests/VerbKitTests/GrammarSearchTests.swift`:

```swift
import XCTest
@testable import VerbKit

final class GrammarSearchTests: XCTestCase {
    private var nDesu: GrammarPoint { GrammarFixture.points[0] }

    func testEmptyAndWhitespaceQueriesMatchEverything() {
        XCTAssertTrue(matchesGrammarSearch(nDesu, query: ""))
        XCTAssertTrue(matchesGrammarSearch(nDesu, query: "   "))
    }

    func testMatchesTitle() {
        XCTAssertTrue(matchesGrammarSearch(nDesu, query: "んです"))
    }

    func testMatchesSummaryText() {
        // "なんです" only appears in the summary, not the title.
        XCTAssertTrue(matchesGrammarSearch(nDesu, query: "なんです"))
        XCTAssertTrue(matchesGrammarSearch(nDesu, query: "EXPLANATION"))
    }

    func testMatchesJapaneseExampleText() {
        XCTAssertTrue(matchesGrammarSearch(nDesu, query: "頭が痛い"))
    }

    func testDoesNotMatchEnglishExampleText() {
        XCTAssertFalse(matchesGrammarSearch(nDesu, query: "headache"))
    }

    func testNoMatch() {
        XCTAssertFalse(matchesGrammarSearch(nDesu, query: "はず"))
    }
}
```

`Packages/VerbKit/Tests/VerbKitTests/RouteTests.swift`:

```swift
import XCTest
@testable import VerbKit

final class RouteTests: XCTestCase {
    private func makeVerb(dict: String) -> Verb {
        Verb(
            type: .ru, label: "Ru-verb", dict: dict, kanji: nil, meaning: "m", description: "d",
            forms: VerbForms(
                masuPos: "a", masuNeg: "b", masuPast: "c", masuPastNeg: "d",
                te: "e", shortPos: "f", shortNeg: "g", shortPast: "h", shortPastNeg: "i"
            ),
            examples: []
        )
    }

    func testResolvesVerbByDictionaryForm() {
        let taberu = makeVerb(dict: "たべる")
        let target = Route.verb("たべる").resolve(verbs: [makeVerb(dict: "のむ"), taberu], grammarPoints: [])
        XCTAssertEqual(target, .verb(taberu))
    }

    func testResolvesGrammarByID() {
        let points = GrammarFixture.points
        let target = Route.grammar(GrammarPoint.nDesuID).resolve(verbs: [], grammarPoints: points)
        XCTAssertEqual(target, .grammar(points[0]))
    }

    func testUnknownTargetsResolveToNil() {
        XCTAssertNil(Route.verb("ない").resolve(verbs: [makeVerb(dict: "たべる")], grammarPoints: GrammarFixture.points))
        XCTAssertNil(Route.grammar("nope").resolve(verbs: [], grammarPoints: GrammarFixture.points))
    }

    func testGrammarLinkIsHiddenUntilGrammarHasSynced() {
        XCTAssertNil(Route.grammar(GrammarPoint.nDesuID).resolve(verbs: [], grammarPoints: []))
    }

    func testRoutesOfDifferentKindsWithTheSameIDAreDistinct() {
        XCTAssertNotEqual(Route.verb("x"), Route.grammar("x"))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd Packages/VerbKit && swift test --filter "GrammarSearchTests|RouteTests" 2>&1 | grep -E "error:" | head -3
```

Expected: `cannot find 'matchesGrammarSearch' in scope`.

- [ ] **Step 3: Implement**

`Packages/VerbKit/Sources/VerbKit/Search/GrammarSearch.swift`:

```swift
import Foundation

/// Matches the title, the summary, and the Japanese text of every usage
/// example, so typing なんです or 頭が痛い both find the んです lesson.
public func matchesGrammarSearch(_ point: GrammarPoint, query: String) -> Bool {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return true }

    if point.title.contains(trimmed) { return true }
    if point.summary.localizedCaseInsensitiveContains(trimmed) { return true }
    for usage in point.usages {
        for example in usage.examples where example.jp.contains(trimmed) {
            return true
        }
    }
    return false
}
```

`Packages/VerbKit/Sources/VerbKit/Navigation/Route.swift`:

```swift
/// A place the app can navigate to. Both the Verbs and Grammar stacks —
/// and, later, widget taps and Shortcuts — resolve through this one type.
public enum Route: Hashable, Sendable {
    /// `Verb.id` (the dictionary form).
    case verb(String)
    /// `GrammarPoint.id`.
    case grammar(String)
}

public enum RouteTarget: Equatable, Sendable {
    case verb(Verb)
    case grammar(GrammarPoint)
}

public extension Route {
    /// `nil` when the target doesn't exist locally (e.g. a grammar point
    /// that hasn't synced yet), so callers can hide the link instead of
    /// navigating nowhere.
    func resolve(verbs: [Verb], grammarPoints: [GrammarPoint]) -> RouteTarget? {
        switch self {
        case let .verb(id):
            return verbs.first { $0.id == id }.map(RouteTarget.verb)
        case let .grammar(id):
            return grammarPoints.first { $0.id == id }.map(RouteTarget.grammar)
        }
    }
}
```

- [ ] **Step 4: Run the whole suite to verify it passes**

```bash
cd Packages/VerbKit && swift test 2>&1 | grep -E "error:|failed|Executed .* tests" | tail -1
cd ../.. && python3 -m unittest discover -s scripts -p "test_*.py" 2>&1 | tail -2
```

Expected: `Executed 107 tests, with 0 failures`, and `Ran 19 tests ... OK`.

- [ ] **Step 5: Commit**

```bash
git add Packages/VerbKit
git commit -m "$(cat <<'EOF'
Add grammar search and Route resolution

matchesGrammarSearch covers title, summary and Japanese example text, so
なんです and 頭が痛い both find the んです lesson. Route resolves to nil
when a target isn't available locally, so links to a lesson that hasn't
synced can be hidden instead of dead-ending.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Grammar tab (screens, tab bar, wiring)

**Files:**
- Create: `App/GrammarDisplay.swift`, `App/OpenRouteAction.swift`, `App/ExampleRow.swift`, `App/GrammarListView.swift`, `App/GrammarDetailView.swift`, `App/MainTabView.swift`
- Modify: `App/RootView.swift`, `App/JPVerbConjugationApp.swift`

**Interfaces:**
- Consumes: `VerbStore.grammarPoints/hasGrammar/retryGrammarSync()` (Task 7), `matchesGrammarSearch` and `Route` (Task 8), the model types (Task 1), and the app's `VerbStore` environment object and `RootView`.
- Produces: `OpenRouteAction` and `EnvironmentValues.openRoute` (call `openRoute(.grammar("n-desu"))`; Task 10 uses it); `MainTabView(verbSelection:verbsTab:)`; `GrammarListView(selection:)`, `GrammarDetailView(point:)`, `ExampleRow(example:)`.

- [ ] **Step 1: Add the presentation helpers**

`App/GrammarDisplay.swift`:

```swift
import VerbKit

// Presentation strings for grammar enums. They live in the app target,
// not VerbKit, because wording is a UI concern.

extension WordClass {
    var displayName: String {
        switch self {
        case .verb: return "Verb"
        case .iAdjective: return "い-adjective"
        case .naAdjective: return "な-adjective"
        case .noun: return "Noun"
        }
    }
}

extension GrammarLevel {
    var displayName: String {
        switch self {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        }
    }
}

extension GrammarRegister {
    var displayName: String {
        switch self {
        case .polite: return "Polite"
        case .casual: return "Casual"
        case .formal: return "Formal / written"
        }
    }
}
```

`App/OpenRouteAction.swift`:

```swift
import SwiftUI
import VerbKit

/// Lets any view navigate to a `Route` (verb or grammar point) without
/// knowing which tab or stack owns it. `MainTabView` provides the real
/// handler; the default is a no-op so previews and isolated views work.
struct OpenRouteAction {
    var handler: (Route) -> Void = { _ in }

    func callAsFunction(_ route: Route) {
        handler(route)
    }
}

private struct OpenRouteKey: EnvironmentKey {
    static let defaultValue = OpenRouteAction()
}

extension EnvironmentValues {
    var openRoute: OpenRouteAction {
        get { self[OpenRouteKey.self] }
        set { self[OpenRouteKey.self] = newValue }
    }
}
```

`App/ExampleRow.swift` (no accessibility modifiers, per the design direction):

```swift
import SwiftUI
import VerbKit

/// A Japanese example whose English translation is hidden until tapped,
/// so a grammar page doubles as self-testing.
struct ExampleRow: View {
    let example: GrammarExample
    @State private var revealed = false

    var body: some View {
        Button {
            revealed.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(example.jp)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                Text(revealed ? example.en : "Tap to show English")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Add the Grammar screens and the tab container**

`App/GrammarListView.swift`. Rows use the same `Button` + `.tag` pattern as `VerbListView`; `List(selection:)` alone matches the row's `id` (a `String`), not the element, so taps would silently do nothing.

```swift
import SwiftUI
import VerbKit

struct GrammarRow: View {
    let point: GrammarPoint

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(point.title)
                    .font(.title3.weight(.bold))
                Text(point.level.displayName)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .glassEffect(in: Capsule())
            }
            Text(point.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

struct GrammarListView: View {
    @Environment(VerbStore.self) private var verbStore
    @Binding var selection: GrammarPoint?
    @State private var search = ""

    private var filtered: [GrammarPoint] {
        verbStore.grammarPoints.filter { matchesGrammarSearch($0, query: search) }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(filtered) { point in
                // Same row pattern as VerbListView: an explicit Button
                // sets the selection, and .tag keeps List's own selection
                // in sync (List(selection:) alone matches the row's id,
                // not the element, so taps would silently do nothing).
                Button {
                    selection = point
                } label: {
                    GrammarRow(point: point)
                }
                .buttonStyle(.plain)
                .tag(point)
            }
        }
        .searchable(text: $search, prompt: "Search grammar…")
        .navigationTitle("Grammar")
        .overlay {
            if !verbStore.hasGrammar {
                ContentUnavailableView {
                    Label("Grammar Not Downloaded Yet", systemImage: "icloud.and.arrow.down")
                } description: {
                    Text("Grammar lessons download in the background. Check your connection and try again.")
                } actions: {
                    Button("Try Again") {
                        Task { await verbStore.retryGrammarSync() }
                    }
                    .buttonStyle(.glassProminent)
                }
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
    }
}
```

`App/GrammarDetailView.swift`:

```swift
import SwiftUI
import VerbKit

struct GrammarDetailView: View {
    let point: GrammarPoint
    @Environment(VerbStore.self) private var verbStore
    @Environment(\.openRoute) private var openRoute

    private let registerOrder: [GrammarRegister] = [.polite, .casual, .formal]

    /// Related points that exist locally; a link to a lesson that hasn't
    /// synced is hidden rather than dead.
    private var relatedPoints: [GrammarPoint] {
        point.related.compactMap { id in
            if case let .grammar(related)? = Route.grammar(id).resolve(verbs: [], grammarPoints: verbStore.grammarPoints) {
                return related
            }
            return nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if !point.attachment.isEmpty { attachmentSection }
                usagesSection
                if !point.conjugations.isEmpty { conjugationsSection }
                if !point.pitfalls.isEmpty { pitfallsSection }
                if !relatedPoints.isEmpty { relatedSection }
            }
            .padding()
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(point.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(point.level.displayName)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .glassEffect(in: Capsule())
            Text(point.title)
                .font(.system(size: 34, weight: .heavy))
            Text(point.summary)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private func sectionHeader(_ title: String, systemImage: String? = nil) -> some View {
        Label {
            Text(title)
        } icon: {
            if let systemImage { Image(systemName: systemImage) }
        }
        .font(.title3.weight(.semibold))
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: How it attaches

    private var attachmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("How it attaches")
            ForEach(Array(point.attachment.enumerated()), id: \.offset) { _, rule in
                card {
                    HStack(spacing: 6) {
                        Text(rule.wordClass.displayName).font(.subheadline.weight(.semibold))
                        if let condition = rule.condition {
                            Text("· \(condition)").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Text(rule.pattern).font(.headline)
                    // Examples are " / "-separated; one per line so long
                    // strings never wrap mid-word.
                    ForEach(rule.example.components(separatedBy: " / "), id: \.self) { example in
                        Text(example).font(.title3)
                    }
                    if let note = rule.note {
                        Text(note).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Usages

    private var usagesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Usages")
            ForEach(Array(point.usages.enumerated()), id: \.offset) { index, usage in
                card {
                    Text("\(index + 1). \(usage.heading)").font(.headline)
                    Text(usage.explanation).font(.subheadline)
                    ForEach(Array(usage.examples.enumerated()), id: \.offset) { _, example in
                        Divider()
                        ExampleRow(example: example)
                    }
                }
            }
        }
    }

    // MARK: Conjugations

    private var conjugationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Conjugations")
            ForEach(registerOrder, id: \.self) { register in
                let forms = point.conjugations.filter { $0.register == register }
                if !forms.isEmpty {
                    card {
                        Text(register.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(Array(forms.enumerated()), id: \.offset) { _, conjugation in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(conjugation.form).font(.headline)
                                if let note = conjugation.note {
                                    Text(note).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Watch out

    private var pitfallsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Watch out", systemImage: "exclamationmark.triangle")
            ForEach(Array(point.pitfalls.enumerated()), id: \.offset) { _, pitfall in
                card {
                    Text(pitfall.heading).font(.headline)
                    Text(pitfall.explanation).font(.subheadline)
                    ForEach(Array(pitfall.examples.enumerated()), id: \.offset) { _, example in
                        Divider()
                        ExampleRow(example: example)
                    }
                }
            }
        }
    }

    // MARK: Related

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Related")
            ForEach(relatedPoints) { related in
                Button {
                    openRoute(.grammar(related.id))
                } label: {
                    Label(related.title, systemImage: "arrow.right.circle")
                }
                .buttonStyle(.glass)
            }
        }
    }
}
```

`App/MainTabView.swift`. `preferredCompactColumn` makes a cross-link land on the lesson even when the Grammar tab hasn't been visited yet; without it, iPhone shows the list instead. `.sidebarAdaptable` turns the tabs into a sidebar on iPad and Mac.

```swift
import SwiftUI
import VerbKit

enum AppTab: Hashable {
    case verbs
    case grammar
}

/// Verbs and Grammar as two tabs, each its own `NavigationSplitView`
/// (list/detail at regular width, a stack on iPhone). Also owns the
/// `openRoute` action, so a verb page can jump to a lesson and a lesson
/// can jump to a related one.
struct MainTabView<VerbsTab: View>: View {
    @Environment(VerbStore.self) private var verbStore
    @Binding var verbSelection: Verb?
    @State private var tab: AppTab = .verbs
    @State private var grammarSelection: GrammarPoint?
    /// On iPhone a `NavigationSplitView` shows its list until told
    /// otherwise; `open` sets this to `.detail` so a cross-link lands on
    /// the lesson even when the Grammar tab hasn't been visited yet.
    @State private var grammarColumn: NavigationSplitViewColumn = .sidebar
    private let verbsTab: VerbsTab

    init(verbSelection: Binding<Verb?>, @ViewBuilder verbsTab: () -> VerbsTab) {
        _verbSelection = verbSelection
        self.verbsTab = verbsTab()
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Verbs", systemImage: "character.book.closed", value: AppTab.verbs) {
                verbsTab
            }
            Tab("Grammar", systemImage: "text.book.closed", value: AppTab.grammar) {
                GrammarTab(selection: $grammarSelection, preferredColumn: $grammarColumn)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .environment(\.openRoute, OpenRouteAction { open($0) })
    }

    private func open(_ route: Route) {
        switch route.resolve(verbs: verbStore.verbs, grammarPoints: verbStore.grammarPoints) {
        case let .verb(verb)?:
            verbSelection = verb
            tab = .verbs
        case let .grammar(point)?:
            grammarSelection = point
            grammarColumn = .detail
            tab = .grammar
        case nil:
            break
        }
    }
}

struct GrammarTab: View {
    @Binding var selection: GrammarPoint?
    @Binding var preferredColumn: NavigationSplitViewColumn

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredColumn) {
            GrammarListView(selection: $selection)
        } detail: {
            if let selection {
                GrammarDetailView(point: selection)
            } else {
                ContentUnavailableView("Select a Grammar Point", systemImage: "text.book.closed")
            }
        }
    }
}
```

- [ ] **Step 3: Wrap the Verbs experience in the tab container**

The existing verb experience (a `NavigationSplitView` plus the sheets and quiz presentation chained onto it) is **moved, unchanged**, into a `verbsTab` property, and `RootView` hosts it inside `MainTabView`. Apply this diff to `App/RootView.swift`; the removed and added blocks are the same code, dedented:

```diff
diff --git a/App/RootView.swift b/App/RootView.swift
index 2ed45ae..4fabf89 100644
--- a/App/RootView.swift
+++ b/App/RootView.swift
@@ -17,52 +17,9 @@ struct RootView: View {
     var body: some View {
         Group {
             if verbStore.hasLocalData {
-                NavigationSplitView {
-                    VerbListView(
-                        selection: $selection,
-                        onRandomQuiz: { quizQuestions = buildQuestions(verbs: verbStore.verbs, count: quizQuestionCount) },
-                        onSettings: { showingSettings = true }
-                    )
-                } detail: {
-                    if let selection {
-                        VerbDetailView(
-                            verb: selection,
-                            onExamples: { showingExamples = true },
-                            onQuiz: { quizQuestions = buildQuestions(verbs: [selection], count: min(quizQuestionCount, 9)) }
-                        )
-                    } else {
-                        ContentUnavailableView("Select a Verb", systemImage: "text.book.closed")
-                    }
-                }
-                .sheet(isPresented: $showingExamples) {
-                    if let selection {
-                        ExamplesView(verb: selection)
-                    }
-                }
-                .sheet(isPresented: $showingSettings) {
-                    NavigationStack {
-                        SettingsView()
-                            .toolbar {
-                                ToolbarItem(placement: .confirmationAction) {
-                                    Button("Done") { showingSettings = false }
-                                }
-                            }
-                    }
-                }
-                #if os(iOS)
-                .fullScreenCover(isPresented: quizPresentationBinding) {
-                    if let quizQuestions {
-                        QuizView(questions: quizQuestions, onDone: { self.quizQuestions = nil })
-                    }
-                }
-                #else
-                .sheet(isPresented: quizPresentationBinding) {
-                    if let quizQuestions {
-                        QuizView(questions: quizQuestions, onDone: { self.quizQuestions = nil })
-                            .frame(minWidth: 560, minHeight: 640)
-                    }
+                MainTabView(verbSelection: $selection) {
+                    verbsTab
                 }
-                #endif
             } else {
                 DataLoadingView(state: verbStore.firstLaunchState) {
                     Task { await verbStore.retryFirstLaunch() }
@@ -72,6 +29,59 @@ struct RootView: View {
         .preferredColorScheme(appearance.colorScheme)
     }
 
+    /// The existing Verbs experience — moved here unchanged, including the
+    /// sheets and quiz presentation chained onto it — so `MainTabView`
+    /// can host it as one tab.
+    @ViewBuilder
+    private var verbsTab: some View {
+        NavigationSplitView {
+            VerbListView(
+                selection: $selection,
+                onRandomQuiz: { quizQuestions = buildQuestions(verbs: verbStore.verbs, count: quizQuestionCount) },
+                onSettings: { showingSettings = true }
+            )
+        } detail: {
+            if let selection {
+                VerbDetailView(
+                    verb: selection,
+                    onExamples: { showingExamples = true },
+                    onQuiz: { quizQuestions = buildQuestions(verbs: [selection], count: min(quizQuestionCount, 9)) }
+                )
+            } else {
+                ContentUnavailableView("Select a Verb", systemImage: "text.book.closed")
+            }
+        }
+        .sheet(isPresented: $showingExamples) {
+            if let selection {
+                ExamplesView(verb: selection)
+            }
+        }
+        .sheet(isPresented: $showingSettings) {
+            NavigationStack {
+                SettingsView()
+                    .toolbar {
+                        ToolbarItem(placement: .confirmationAction) {
+                            Button("Done") { showingSettings = false }
+                        }
+                    }
+            }
+        }
+        #if os(iOS)
+        .fullScreenCover(isPresented: quizPresentationBinding) {
+            if let quizQuestions {
+                QuizView(questions: quizQuestions, onDone: { self.quizQuestions = nil })
+            }
+        }
+        #else
+        .sheet(isPresented: quizPresentationBinding) {
+            if let quizQuestions {
+                QuizView(questions: quizQuestions, onDone: { self.quizQuestions = nil })
+                    .frame(minWidth: 560, minHeight: 640)
+            }
+        }
+        #endif
+    }
+
     private var quizPresentationBinding: Binding<Bool> {
         Binding(
             get: { quizQuestions != nil },
```

If `RootView` has changed since `3b56c92`, do the same move by hand instead of applying the diff: cut the `NavigationSplitView { … }` expression **together with every modifier chained onto it** into `@ViewBuilder private var verbsTab: some View { … }`, and in its place inside the `if verbStore.hasLocalData` branch write `MainTabView(verbSelection: $selection) { verbsTab }`. Leave `.preferredColorScheme(...)`, the `Group`, `quizPresentationBinding` and all `@State` / `@AppStorage` properties where they are.

- [ ] **Step 4: Hand the store its grammar dependencies**

Apply this diff to `App/JPVerbConjugationApp.swift`. One `ModelContext`, one fetcher and one sync-state store are shared by the verb and grammar services:

```diff
diff --git a/App/JPVerbConjugationApp.swift b/App/JPVerbConjugationApp.swift
index d780802..fd2056e 100644
--- a/App/JPVerbConjugationApp.swift
+++ b/App/JPVerbConjugationApp.swift
@@ -9,14 +9,18 @@ struct JPVerbConjugationApp: App {
 
     init() {
         let container = Self.makeModelContainer()
-        let persisting = SwiftDataVerbPersisting(modelContext: ModelContext(container))
-        let syncService = VerbSyncService(
-            fetcher: GitHubVerbFetcher.githubMain(),
-            syncState: UserDefaultsSyncStateStore()
-        )
+        let context = ModelContext(container)
+        let fetcher = GitHubVerbFetcher.githubMain()
+        let syncState = UserDefaultsSyncStateStore()
         let monitor = NetworkMonitor()
         _networkMonitor = State(initialValue: monitor)
-        _verbStore = State(initialValue: VerbStore(syncService: syncService, persisting: persisting, networkMonitor: monitor))
+        _verbStore = State(initialValue: VerbStore(
+            syncService: VerbSyncService(fetcher: fetcher, syncState: syncState),
+            persisting: SwiftDataVerbPersisting(modelContext: context),
+            networkMonitor: monitor,
+            grammarSyncService: GrammarSyncService(fetcher: fetcher, syncState: syncState),
+            grammarPersisting: SwiftDataGrammarPersisting(modelContext: context)
+        ))
     }
 
     var body: some Scene {
```

- [ ] **Step 5: Generate the project and build both platforms**

```bash
./scripts/generate-project.sh
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_macOS -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **` for both. (`CODE_SIGNING_ALLOWED=NO` avoids needing the signing identity; the App Group is then unavailable and the app falls back to an in-memory store, which is fine for this check.)

- [ ] **Step 6: Verify in the Simulator against the local data**

The app fetches from GitHub `main`, where the new data is not published yet. To verify now, serve `data/` locally and temporarily point the fetcher at it.

1. In a separate terminal, from the repo root: `python3 -m http.server 8765 --bind 127.0.0.1 --directory data`.
2. **Temporarily** edit `base` in `GitHubVerbFetcher.githubMain` (`Packages/VerbKit/Sources/VerbKit/Data/GitHubVerbFetcher.swift`) to `"http://127.0.0.1:8765/"`. (ATS does not block plain HTTP to an IP address.) Do not commit this.
3. Rebuild the iOS scheme, then boot an iPhone simulator and install and launch the app with the iOS Simulator tool.
4. Between runs, uninstall to clear the recorded sync state: `xcrun simctl uninstall booted dev.martinloeseth.jpverbconjugation`. (With no App Group the store is in-memory but sync state persists in `UserDefaults`, so a relaunch would report "up to date" with no data.)

Expected, in the app:
- The Verbs tab looks as it did before (colour-coded rows, toolbar, guide), now with a floating **Verbs** / **Grammar** tab bar.
- **Grammar** lists one row, "んです", with a Beginner glass badge and a two-line summary.
- Tapping the row opens the lesson: badge, title, summary, "How it attaches" (six glass cards; long examples one per line), "Usages" (seven cards; tapping an example reveals its English), "Conjugations" (Polite / Casual / Formal), "Watch out" (three cards). The navigation title is inline, not a second large title.
- Tapping a verb in the **Verbs** tab still opens its detail.
- On an iPad simulator the tabs appear as a floating switcher above the list/detail split. (Launch it with `xcrun simctl install/launch` if the tool has no permission for that device.)

Then revert the temporary edit: `git checkout Packages/VerbKit/Sources/VerbKit/Data/GitHubVerbFetcher.swift`, and stop the local server.

> The offline path ("Grammar Not Downloaded Yet" with Try Again) is covered by `VerbStoreGrammarTests` and was not exercised by hand. The iPad sidebar-toggle state was not exercised either.

- [ ] **Step 7: Commit**

```bash
git status --short   # confirm GitHubVerbFetcher.swift is unchanged (no local-server URL)
git add App/ExampleRow.swift App/GrammarDetailView.swift App/GrammarDisplay.swift App/GrammarListView.swift App/MainTabView.swift App/OpenRouteAction.swift App/RootView.swift App/JPVerbConjugationApp.swift
git commit -m "$(cat <<'EOF'
Add Grammar tab: list, lesson detail, and Verbs/Grammar tab bar

MainTabView hosts the existing verb experience as one tab and the new
grammar screens as the other (sidebar-adaptable on iPad and Mac), and
provides an openRoute environment action so any view can navigate to a
lesson. preferredCompactColumn makes a cross-link land on the lesson
even if the tab hasn't been opened yet.

RootView's verb experience is moved unchanged into a verbsTab property,
sheets and quiz presentation included. Grammar rows use the same
Button + .tag pattern as the verb list, and custom surfaces use
.glassEffect() per the design direction.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: んです section on verb detail, linked to the lesson

**Files:**
- Create: `App/NdesuFormsSection.swift`
- Modify: `App/VerbDetailView.swift`

**Interfaces:**
- Consumes: `VerbForms.nd*` and `hasNdForms` (Task 2), `Route`, `GrammarPoint.nDesuID`, `VerbStore.grammarPoints` (Tasks 7–8), `openRoute` (Task 9).
- Produces: `NdesuFormsSection(forms:)`, which reads `VerbStore` and `openRoute` from the environment, so `VerbDetailView` needs no new parameters.

- [ ] **Step 1: Create the section**

`App/NdesuFormsSection.swift`. The grid sits on a glass tile like `FormGroupSection`'s cells, and the link is a glass button:

```swift
import SwiftUI
import VerbKit

/// The verb's んです forms — polite and casual side by side — plus a link
/// to the lesson. Shown on verb detail only when the verb has `nd_*` data.
struct NdesuFormsSection: View {
    let forms: VerbForms
    @Environment(VerbStore.self) private var verbStore
    @Environment(\.openRoute) private var openRoute
    @State private var isExpanded = false

    private struct Row {
        let label: String
        let polite: String?
        let casual: String?
    }

    private var rows: [Row] {
        [
            Row(label: "Present +", polite: forms.ndPos, casual: forms.ndCasualPos),
            Row(label: "Present −", polite: forms.ndNeg, casual: forms.ndCasualNeg),
            Row(label: "Past +", polite: forms.ndPast, casual: forms.ndCasualPast),
            Row(label: "Past −", polite: forms.ndPastNeg, casual: forms.ndCasualPastNeg),
        ]
    }

    /// The link is hidden until the lesson has synced, so it never dead-ends.
    private var lessonIsAvailable: Bool {
        Route.grammar(GrammarPoint.nDesuID)
            .resolve(verbs: [], grammarPoints: verbStore.grammarPoints) != nil
    }

    var body: some View {
        DisclosureGroup("んです", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow {
                        Text("Polite").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                        Text("Casual").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    }
                    ForEach(rows, id: \.label) { row in
                        // Each tense gets a caption row spanning both
                        // columns, so the forms below can use half the
                        // width each without wrapping.
                        GridRow {
                            Text(row.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 6)
                                .gridCellColumns(2)
                        }
                        GridRow {
                            Text(row.polite ?? "—").font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                            Text(row.casual ?? "—").font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(in: RoundedRectangle(cornerRadius: 8))

                if lessonIsAvailable {
                    Button {
                        openRoute(.grammar(GrammarPoint.nDesuID))
                    } label: {
                        Label("Learn about んです", systemImage: "arrow.right.circle")
                    }
                    .buttonStyle(.glass)
                    .font(.subheadline)
                }
            }
            .padding(.top, 4)
        }
        .font(.subheadline.weight(.semibold))
    }
}
```

- [ ] **Step 2: Show it on verb detail**

Apply this diff to `App/VerbDetailView.swift`. The block goes directly **after** the `if hasAdvancedForms { … }` block, inside `formGroups`:

```diff
diff --git a/App/VerbDetailView.swift b/App/VerbDetailView.swift
index 0b3f5a9..8112f4c 100644
--- a/App/VerbDetailView.swift
+++ b/App/VerbDetailView.swift
@@ -121,6 +121,10 @@ struct VerbDetailView: View {
                     defaultExpanded: false
                 )
             }
+
+            if verb.forms.hasNdForms {
+                NdesuFormsSection(forms: verb.forms)
+            }
         }
     }
 }
```

- [ ] **Step 3: Build both platforms**

```bash
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_macOS -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **` for both.

- [ ] **Step 4: Verify in the Simulator**

Repeat Task 9 Step 6's setup (local server, temporary base-URL edit, fresh install). Then, in the Simulator:
- Open **Verbs → たべる**. Below the て-form section there is a collapsed **んです** section.
- Expanding it shows a Polite / Casual grid on glass tiles: たべるんです / たべるんだ, たべないんです / たべないんだ, たべたんです / たべたんだ, たべなかったんです / たべなかったんだ, none of them wrapping.
- Tapping **Learn about んです** switches to the Grammar tab and lands on the んです lesson. This must work even if the Grammar tab was never opened before (fresh install).
- Repeat for **くる**: the negative reads こないんです and the past きたんです.

Then revert the temporary edit and stop the server, as in Task 9.

- [ ] **Step 5: Commit**

```bash
git status --short   # GitHubVerbFetcher.swift must be unchanged
git add App/NdesuFormsSection.swift App/VerbDetailView.swift
git commit -m "$(cat <<'EOF'
Show んです forms on verb detail, linked to the lesson

A collapsed section after Advanced, shown only for verbs that have nd_*
data, with polite and casual forms side by side on glass tiles. Its
Learn about link resolves through Route and is hidden until the lesson
has synced.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Full verification, merge and publishing

**Files:** none (verification only).

- [ ] **Step 1: Run every test suite**

```bash
cd Packages/VerbKit && swift test 2>&1 | grep -E "error:|failed|Executed .* tests" | tail -1
cd ../.. && python3 -m unittest discover -s scripts -p "test_*.py" 2>&1 | tail -2
python3 scripts/update_data.py --check
```

Expected: `Executed 107 tests, with 0 failures`; `Ran 19 tests ... OK`; `data is up to date`.

- [ ] **Step 2: Build both app targets from a clean generate**

```bash
./scripts/generate-project.sh
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_macOS -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **` twice.

- [ ] **Step 3: Confirm no temporary changes are left**

```bash
grep -n "raw.githubusercontent.com" Packages/VerbKit/Sources/VerbKit/Data/GitHubVerbFetcher.swift
grep -rn "127.0.0.1" Packages App scripts | grep -v "/.build/"
git status --short
```

Expected: the first command shows the `raw.githubusercontent.com/.../main/data/` line; the second prints nothing; the third shows a clean tree.

- [ ] **Step 4: Merge gracefully**

The branch must merge without clobbering anything `main` has gained. Before merging:

```bash
git fetch origin 2>/dev/null; git log --oneline main..HEAD | cat        # only this work's commits
git diff --name-only HEAD...main -- . ':!docs' | cat                    # files main changed since we branched
```

Expected: the second command prints nothing. If `main` has moved, do **not** force anything: `git rebase main` (or `git merge main` into the branch), resolve conflicts by keeping `main`'s side and re-applying only this work's additions, re-run Steps 1–3, and only then merge. If `main` has not moved, the merge is a fast-forward: `git switch main && git merge --ff-only feature/grammar-nd-desu`. Get the user's go-ahead before merging into `main`.

- [ ] **Step 5: Publish (needs the user's explicit go-ahead)**

The app reads the data from GitHub `main`, so the lesson and `nd_*` forms reach users only after the commits are pushed. **Do not push without asking the user first.** After they approve and the push lands:

```bash
curl -s https://raw.githubusercontent.com/martinloesethjensen/jp-verb-conjugation-app/main/data/manifest.json
shasum -a 256 data/verbs.json data/grammar.json
```

Expected: the manifest's `sha256` and `grammar.sha256` match the two `shasum` lines. If GitHub's raw cache serves the old manifest, wait a minute and retry.

- [ ] **Step 6: Final review checklist**

Every item is verified by a step above; confirm none was skipped:
- [ ] Grammar syncs from the manifest's `grammar` block, only when its hash changes (Task 5 tests).
- [ ] `sync()` records nothing; a persistence failure leaves the manifest unconfirmed and a retry re-fetches (Tasks 5 and 7 tests).
- [ ] A grammar failure never changes verbs or first-launch state (Task 7 tests).
- [ ] Cached grammar loads offline (Task 7 tests).
- [ ] Old app builds ignore the new manifest block (Task 5 fetcher test).
- [ ] Grammar tab lists, searches and shows the lesson (Task 9 Simulator run).
- [ ] Verb detail shows the んです section only for verbs with `nd_*` data, and the link works from a never-visited Grammar tab (Task 10 Simulator run).
- [ ] `data/` is byte-consistent with its manifest (Task 4 tests and Task 3 `--check`).
- [ ] No `.accessibility*` modifiers and no flat `.quaternary` / `.tertiary` backgrounds were added (`grep -rn "accessibility\|quaternary\|tertiary" App/Grammar* App/ExampleRow.swift App/NdesuFormsSection.swift App/MainTabView.swift` prints nothing).

---

## Notes for the executor

- **Two manifest requests per sync:** the verb and grammar services each fetch the (tiny) `manifest.json`. Keeping the services independent was worth one extra small request.
- **Follow-ups, out of scope here:** verb links from other lessons once sub-projects 2–4 add them; `nd_*` in the quiz; furigana; exercising the iPad sidebar-toggle state and the Mac window by hand.
