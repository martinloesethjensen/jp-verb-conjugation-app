# Nuance Endings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add four intermediate grammar lessons on the nuance endings (はず・かもしれない・わけ, べき・ものだ, よう・みたい・そう・らしい, っぽい) and a collapsed **Grammar** section on every verb page that links to every lesson attaching to verbs.

**Architecture:** The lessons are data: four entries in `data/grammar.json` in the existing lesson shape, plus readings in `data/furigana.json` (the furigana coverage check enforces them). A pure `GrammarPoint.attachesToVerbs` in `VerbKit` picks the lessons for the verb page; `VerbGrammarSection` lists them and opens each through the existing `Route`. One new data guard: every `related` link must be mutual.

**Tech Stack:** Swift 5 language mode on Xcode 27 (SwiftPM tools 6.2), SwiftUI with Liquid Glass, XCTest; Python 3 (standard library only); XcodeGen 2.46.

**Spec:** [docs/superpowers/specs/2026-10-01-nuance-endings-design.md](../specs/2026-10-01-nuance-endings-design.md), which builds on [the grammar foundation spec](../specs/2026-09-29-grammar-foundation-nd-desu-design.md), [the furigana spec](../specs/2026-09-30-furigana-design.md) and the [native rewrite spec](../specs/2026-09-23-native-apple-rewrite-design.md) (read its section 10, the visual design direction).

**Verified against:** `main` at `d034bcf` plus the spec commits on `feature/nuance-endings`. Every task below was executed on a scratch branch (one commit per task) with all tests passing, both app targets building, and the app run in the iOS Simulator against local copies of the data (the Grammar section on a verb page, a row opening the lesson, the lesson page scrolling with readings). The test counts quoted per task come from those runs. **If `main` has moved, run Task 0 Step 2 first.**

## Global Constraints

- Deployment target: **iOS 26 / macOS 26**, Swift language mode 5. Do not lower it.
- **Patch existing files; never replace them wholesale.** Modified files are given as diffs against `d034bcf`: apply with `git apply --3way`, or make the equivalent edit by hand if the surrounding code has moved. New files are given in full.
- `data/grammar.json` and `data/furigana.json` are hand-authored; `data/verbs.json` is not touched and its version does not change. `data/manifest.json` is changed only by running `scripts/update_data.py`. Hashes must match the files byte for byte. `grammar.json` keeps its layout (examples and conjugations on one line each, `related` inline).
- Lessons are `level: intermediate`, written independently (not copied from Yokubi), mostly hiragana with kanji where natural, and **reviewed by the maintainer** (spec §1). They use no model change: `attachment`, `conjugations`, `pitfalls` and `related` already fit.
- Every new kanji run needs an entry in `furigana.json`; keys are a kanji run plus at most three kana, values hiragana only (reading of the kanji part, never okurigana). The script's coverage check fails and names any run without one.
- Every `related` link must be **mutual** across the whole file (spec §3). The cross-links are: `certainty` ↔ `appearance`, `certainty` ↔ `obligation`, `appearance` ↔ `ppoi`, `certainty` ↔ `n-desu`.
- The verb-page Grammar section lists the lessons for which `GrammarPoint.attachesToVerbs` is true (any attachment rule with `wordClass == .verb`), in the order of `VerbStore.grammarPoints`. It is last on the page, collapsed by default, styled like the other sections, hidden when the list is empty, and opens a lesson through `openRoute(.grammar(id))` (spec §2).
- Visual design direction (rewrite spec §10): custom surfaces use `.glassEffect(...)`; **no accessibility-specific modifiers** (`.accessibilityLabel`, `.accessibilityHint`, …).
- Out of scope: per-verb ordering, search or filtering in the new section, the verb auxiliaries (sub-project 4) (spec, "Not in this sub-project").
- Any `git push` to the GitHub remote requires explicit user confirmation at execution time. Do not push without asking first.

---

## Task 0: Baseline

**Files:** none.

- [ ] **Step 1: Start from the spec branch and record the baseline**

```bash
git worktree add -b feature/nuance-endings-impl .claude/worktrees/nuance-endings-impl feature/nuance-endings
cd .claude/worktrees/nuance-endings-impl
git log -1 --format=%h
(cd Packages/VerbKit && swift test 2>&1 | grep -E "error:|failed|Executed .* tests" | tail -1)
python3 -m unittest discover -s scripts -p "test_*.py" 2>&1 | tail -2
python3 scripts/update_data.py --check
```

Expected: a short hash, `Executed 174 tests, with 0 failures`, `Ran 70 tests ... OK`, and `data is up to date`. Every count below is relative to these. (If `feature/nuance-endings` has already been merged or deleted, branch from `main` instead.)

- [ ] **Step 2: If `main` is newer than `d034bcf`, see what it touched**

```bash
git diff --name-only d034bcf main -- . ':!docs' ':!*.png' | cat
```

Expected: nothing. If files appear and any is one this plan modifies (`GrammarPoint.swift`, `VerbDetailView.swift`, `update_data.py`, `test_update_data.py`, `grammar.json`, `furigana.json`, `manifest.json`, `RealPotentialDataTests.swift`), read that diff before applying the matching diff below and adapt instead of overwriting.

---

## Task 1: The mutual-`related` guard

**Files:**
- Modify: `scripts/update_data.py`
- Test: `scripts/test_update_data.py`

**Interfaces:**
- Produces: `validate_grammar(doc)` additionally reports, for every lesson A that lists B in `related` where B exists and B does not list A, one error naming both ids and the words "related links must be mutual". Dangling ids are still reported by the existing check, and a lesson listing itself is ignored. Used by Task 3.

- [ ] **Step 1: Write the failing tests**

Apply this diff to `scripts/test_update_data.py`. It adds a `_two_lessons` helper and two tests (a one-sided link is reported once, naming both lessons; a mutual link passes):

```diff
diff --git a/scripts/test_update_data.py b/scripts/test_update_data.py
index b2f7ff3..c2cafdf 100644
--- a/scripts/test_update_data.py
+++ b/scripts/test_update_data.py
@@ -375,6 +375,26 @@ class ValidateGrammarTests(unittest.TestCase):
         doc["grammar"][0]["related"] = ["nope"]
         self.assertTrue(any("related" in e for e in ud.validate_grammar(doc)))
 
+    def _two_lessons(self, a_related, b_related):
+        doc = valid_grammar()
+        second = copy.deepcopy(doc["grammar"][0])
+        second["id"] = "other"
+        doc["grammar"][0]["related"] = a_related
+        second["related"] = b_related
+        doc["grammar"].append(second)
+        return doc
+
+    def test_related_links_must_be_mutual(self):
+        doc = self._two_lessons(["other"], [])
+        errors = ud.validate_grammar(doc)
+        self.assertEqual(len(errors), 1)
+        self.assertIn("n-desu", errors[0])
+        self.assertIn("other", errors[0])
+        self.assertIn("mutual", errors[0])
+
+    def test_mutual_related_links_pass(self):
+        self.assertEqual(ud.validate_grammar(self._two_lessons(["other"], ["n-desu"])), [])
+
     def test_pitfall_without_explanation(self):
         doc = valid_grammar()
         doc["grammar"][0]["pitfalls"][0]["explanation"] = ""
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
python3 -m unittest discover -s scripts -p "test_*.py" 2>&1 | tail -4
```

Expected: `FAILED` with `test_related_links_must_be_mutual` failing (the guard does not exist yet).

- [ ] **Step 3: Implement**

Apply this diff to `scripts/update_data.py`:

```diff
diff --git a/scripts/update_data.py b/scripts/update_data.py
index e7e95b9..8c598c6 100755
--- a/scripts/update_data.py
+++ b/scripts/update_data.py
@@ -326,6 +326,21 @@ def validate_grammar(doc):
         if not isinstance(p.get("related"), list):
             errors.append(f"{pid}: related must be a list")
 
+    by_id = {p.get("id"): p for p in points}
+    for p in points:
+        related = p.get("related")
+        if not isinstance(related, list):
+            continue
+        for other_id in related:
+            other = by_id.get(other_id)
+            if other is None or other_id == p.get("id"):
+                continue  # dangling ids are reported above
+            if p.get("id") not in (other.get("related") or []):
+                errors.append(
+                    f"{p.get('id')}: related '{other_id}', but '{other_id}' does not list "
+                    f"'{p.get('id')}' back (related links must be mutual)"
+                )
+
         usages = p.get("usages")
         if not isinstance(usages, list) or not usages:
             errors.append(f"{pid}: usages must be a non-empty list")
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
python3 -m unittest discover -s scripts -p "test_*.py" 2>&1 | tail -2
python3 scripts/update_data.py --check
```

Expected: `Ran 72 tests ... OK` (70 baseline plus 2 new) and `data is up to date` (the existing んです and 可能形 lessons already link to each other).

- [ ] **Step 5: Commit**

```bash
git add scripts
git commit -m "$(cat <<'EOF'
Require every related link between lessons to be mutual

A one-sided link would leave a lesson that nothing leads back from, so the
data script now reports each one, naming both lessons.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `GrammarPoint.attachesToVerbs`

**Files:**
- Modify: `Packages/VerbKit/Sources/VerbKit/Models/GrammarPoint.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/GrammarVerbLessonsTests.swift`

**Interfaces:**
- Produces: `GrammarPoint.attachesToVerbs: Bool` (true when any attachment rule has `wordClass == .verb`) and `extension Sequence where Element == GrammarPoint { var attachingToVerbs: [GrammarPoint] }` (the verb lessons in the order given; empty when none). Used by Tasks 3 and 4.

- [ ] **Step 1: Write the failing test**

`Packages/VerbKit/Tests/VerbKitTests/GrammarVerbLessonsTests.swift`:

```swift
import XCTest
@testable import VerbKit

final class GrammarVerbLessonsTests: XCTestCase {
    private func point(_ id: String, classes: [WordClass]) -> GrammarPoint {
        GrammarPoint(
            id: id,
            title: id,
            summary: "s",
            level: .intermediate,
            usages: [],
            attachment: classes.map { AttachmentRule(wordClass: $0, pattern: "p", example: "e") },
            conjugations: [],
            pitfalls: [],
            related: []
        )
    }

    func testALessonWithAVerbRuleAttachesToVerbs() {
        XCTAssertTrue(point("a", classes: [.noun, .verb]).attachesToVerbs)
    }

    func testALessonWithoutAVerbRuleDoesNot() {
        XCTAssertFalse(point("a", classes: [.noun, .naAdjective]).attachesToVerbs)
        XCTAssertFalse(point("a", classes: []).attachesToVerbs)
    }

    func testFilteringKeepsTheGivenOrder() {
        let points = [
            point("first", classes: [.verb]),
            point("noun-only", classes: [.noun]),
            point("second", classes: [.iAdjective, .verb]),
        ]
        XCTAssertEqual(points.attachingToVerbs.map(\.id), ["first", "second"])
    }

    func testNoLessonsMeansNothingToList() {
        XCTAssertTrue([GrammarPoint]().attachingToVerbs.isEmpty)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd Packages/VerbKit && swift test --filter GrammarVerbLessonsTests 2>&1 | grep -E "error:" | head -2
```

Expected: `value of type 'GrammarPoint' has no member 'attachesToVerbs'`.

- [ ] **Step 3: Implement**

Apply this diff to `Packages/VerbKit/Sources/VerbKit/Models/GrammarPoint.swift`. It is purely additive:

```diff
diff --git a/Packages/VerbKit/Sources/VerbKit/Models/GrammarPoint.swift b/Packages/VerbKit/Sources/VerbKit/Models/GrammarPoint.swift
index 0b0d85f..83fdb04 100644
--- a/Packages/VerbKit/Sources/VerbKit/Models/GrammarPoint.swift
+++ b/Packages/VerbKit/Sources/VerbKit/Models/GrammarPoint.swift
@@ -122,6 +122,12 @@ public struct GrammarPoint: Codable, Hashable, Identifiable, Sendable {
     /// The id verb detail pages link to for the potential-form lesson.
     public static let potentialID = "potential"
 
+    /// True when the lesson has an attachment rule for verbs. The verb page's
+    /// Grammar section lists exactly these lessons.
+    public var attachesToVerbs: Bool {
+        attachment.contains { $0.wordClass == .verb }
+    }
+
     public init(
         id: String,
         title: String,
@@ -156,3 +162,11 @@ public struct GrammarDataFile: Codable, Sendable {
         self.grammar = grammar
     }
 }
+
+public extension Sequence where Element == GrammarPoint {
+    /// The lessons that attach to verbs, in the order given (the Grammar tab's
+    /// order). Empty until grammar has synced, so callers can hide on empty.
+    var attachingToVerbs: [GrammarPoint] {
+        filter(\.attachesToVerbs)
+    }
+}
```

- [ ] **Step 4: Run the whole suite to verify it passes**

```bash
cd Packages/VerbKit && swift test 2>&1 | grep -E "error:|failed|Executed .* tests" | tail -1
```

Expected: `Executed 178 tests, with 0 failures` (174 baseline plus 4 new).

- [ ] **Step 5: Commit**

```bash
git add Packages/VerbKit
git commit -m "$(cat <<'EOF'
Add GrammarPoint.attachesToVerbs and the verb-lesson filter

Picks the lessons the verb page's Grammar section will list: those with an
attachment rule for verbs, in the order given.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: The four lessons, their readings and the real-data tests

**Files:**
- Modify: `data/grammar.json`, `data/furigana.json`, `data/manifest.json` (by the script)
- Modify: `Packages/VerbKit/Tests/VerbKitTests/RealPotentialDataTests.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/RealNuanceDataTests.swift`

**Interfaces:**
- Consumes: the mutual-`related` guard (Task 1) and `attachingToVerbs` (Task 2).
- Produces: lessons `certainty`, `obligation`, `appearance` and `ppoi` in `grammar.json` (all `intermediate`), `n-desu.related` gaining `certainty`, 71 new readings in `furigana.json`, and the manifest at grammar `1.2.0` and furigana `1.1.0`.

- [ ] **Step 1: Write the failing tests**

`Packages/VerbKit/Tests/VerbKitTests/RealNuanceDataTests.swift`. It checks the four lessons exist as intermediate with usages and pitfalls, that each has attachment rules for the right word classes, that every related link in the file is mutual, and that the six verb lessons come out in file order:

```swift
import XCTest
@testable import VerbKit

/// Tests against the nuance-ending lessons in the real `data/grammar.json`
/// (`RealGrammarDataTests` guards the file against its manifest hash). They read
/// the file straight from the repo checkout.
final class RealNuanceDataTests: XCTestCase {
    private func loadGrammar() throws -> [GrammarPoint] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // VerbKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // VerbKit
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("data")
            .appendingPathComponent("grammar.json")
        return try JSONDecoder().decode(GrammarDataFile.self, from: Data(contentsOf: url)).grammar
    }

    private let nuanceIDs = ["certainty", "obligation", "appearance", "ppoi"]

    func testTheFourLessonsExistAsIntermediate() throws {
        let points = try loadGrammar()
        for id in nuanceIDs {
            let lesson = try XCTUnwrap(points.first { $0.id == id }, id)
            XCTAssertEqual(lesson.level, .intermediate, id)
            XCTAssertFalse(lesson.usages.isEmpty, id)
            XCTAssertFalse(lesson.pitfalls.isEmpty, id)
        }
    }

    func testEachLessonHasAttachmentRulesForTheClassesItShould() throws {
        let points = try loadGrammar()
        func classes(_ id: String) throws -> Set<WordClass> {
            Set(try XCTUnwrap(points.first { $0.id == id }, id).attachment.map(\.wordClass))
        }
        XCTAssertEqual(try classes("certainty"), [.verb, .iAdjective, .naAdjective, .noun])
        XCTAssertEqual(try classes("obligation"), [.verb, .iAdjective, .naAdjective])
        XCTAssertEqual(try classes("appearance"), [.verb, .iAdjective, .naAdjective, .noun])
        XCTAssertEqual(try classes("ppoi"), [.noun, .verb, .iAdjective])
    }

    func testSiblingLessonsLinkBothWays() throws {
        let points = try loadGrammar()
        let byID = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0) })
        for lesson in points {
            for other in lesson.related {
                XCTAssertTrue(byID[other]?.related.contains(lesson.id) ?? false,
                              "\(lesson.id) relates to \(other), which does not relate back")
            }
        }
    }

    func testEveryLessonAttachingToVerbsShowsInTheVerbPageList() throws {
        // All six lessons have a verb rule; the list keeps the file's order.
        XCTAssertEqual(
            try loadGrammar().attachingToVerbs.map(\.id),
            ["n-desu", "potential", "certainty", "obligation", "appearance", "ppoi"]
        )
    }
}
```

Also loosen one existing assertion, because んです now has two related lessons. Apply this diff to `Packages/VerbKit/Tests/VerbKitTests/RealPotentialDataTests.swift`:

```diff
diff --git a/Packages/VerbKit/Tests/VerbKitTests/RealPotentialDataTests.swift b/Packages/VerbKit/Tests/VerbKitTests/RealPotentialDataTests.swift
index ba59f42..b283094 100644
--- a/Packages/VerbKit/Tests/VerbKitTests/RealPotentialDataTests.swift
+++ b/Packages/VerbKit/Tests/VerbKitTests/RealPotentialDataTests.swift
@@ -127,7 +127,7 @@ final class RealPotentialDataTests: XCTestCase {
         let potential = try XCTUnwrap(points.first { $0.id == GrammarPoint.potentialID })
         let nDesu = try XCTUnwrap(points.first { $0.id == GrammarPoint.nDesuID })
         XCTAssertEqual(potential.related, [GrammarPoint.nDesuID])
-        XCTAssertEqual(nDesu.related, [GrammarPoint.potentialID])
+        XCTAssertTrue(nDesu.related.contains(GrammarPoint.potentialID))
     }
 
     func testLessonIsFoundBySearchingItsJapaneseAndEnglish() throws {
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd Packages/VerbKit && swift test --filter RealNuanceDataTests 2>&1 | grep -E "error:|failed" | head -3
```

Expected: failures, because the lessons do not exist yet.

- [ ] **Step 3: Add the lessons**

Apply this diff to `data/grammar.json`. It appends the four lessons and adds `certainty` to the んです lesson's `related`. **This is the content the maintainer must review**: the Japanese examples, the attachment rules for each word class (the most error-prone part), and the explanations.

```diff
diff --git a/data/grammar.json b/data/grammar.json
index 9cb5900..8ece377 100644
--- a/data/grammar.json
+++ b/data/grammar.json
@@ -146,7 +146,7 @@
           ]
         }
       ],
-      "related": ["potential"]
+      "related": ["potential", "certainty"]
     },
     {
       "id": "potential",
@@ -276,6 +276,479 @@
         }
       ],
       "related": ["n-desu"]
+    },
+    {
+      "id": "certainty",
+      "title": "はず・かもしれない・わけ",
+      "summary": "Three ways to say how things stand: はず (I expect so, because it makes sense), かもしれない (maybe), and わけ (that is how it works out). All three come after a plain form.",
+      "level": "intermediate",
+      "usages": [
+        {
+          "heading": "はず: what you expect",
+          "explanation": "はず says that, going by what you know, something should be the case. It is a judgement from reasons, not a hunch, so it is stronger than かもしれない.",
+          "examples": [
+            { "jp": "田中さんはもう家に着いたはずです。", "en": "Mr. Tanaka should have arrived home by now." },
+            { "jp": "この道を行けば、駅に出るはずだ。", "en": "If you go this way, you should come out at the station." }
+          ]
+        },
+        {
+          "heading": "はず: what was supposed to happen",
+          "explanation": "はずだった says that something was expected or planned and did not turn out that way. はずがない (or はずはない) says there is no way it can be true.",
+          "examples": [
+            { "jp": "会議は三時のはずでしたが、まだ始まりません。", "en": "The meeting was supposed to be at three, but it hasn't started." },
+            { "jp": "あの人が知らないはずがない。", "en": "There's no way that person doesn't know." }
+          ]
+        },
+        {
+          "heading": "かもしれない: maybe",
+          "explanation": "かもしれない says that something is possible, with no claim about how likely. Polite speech uses かもしれません, and in casual speech it often shrinks to かも.",
+          "examples": [
+            { "jp": "明日は雨が降るかもしれない。", "en": "It might rain tomorrow." },
+            { "jp": "山田さんは来ないかもしれません。", "en": "Mr. Yamada may not come." },
+            { "jp": "これ、ちょっと高いかも。", "en": "This might be a bit expensive." }
+          ]
+        },
+        {
+          "heading": "わけ: that is how it works out",
+          "explanation": "わけ (訳) means a reason or a line of reasoning. 〜わけだ says that something follows naturally from what you already know, like \"no wonder\" or \"so that's why\".",
+          "examples": [
+            { "jp": "毎日練習しているから、上手なわけだ。", "en": "He practises every day, so no wonder he's good." },
+            { "jp": "なるほど、だから眠いわけですね。", "en": "I see, so that's why you're sleepy." }
+          ]
+        },
+        {
+          "heading": "わけがない and わけではない",
+          "explanation": "わけがない says that something cannot be so. わけではない does not deny the whole sentence but one conclusion that someone might draw, and so it means \"it's not that...\".",
+          "examples": [
+            { "jp": "そんなに早く終わるわけがない。", "en": "There's no way it'll be over that quickly." },
+            { "jp": "嫌いなわけではありません。ただ、時間がないんです。", "en": "It's not that I dislike it. I just don't have the time." },
+            { "jp": "お酒が飲めないわけじゃないよ。", "en": "It's not that I can't drink." }
+          ]
+        },
+        {
+          "heading": "How sure are you?",
+          "explanation": "In order of confidence: かもしれない is a possibility, はず is an expectation backed by reasons, and 〜に違いない is close to certain. わけ is different: it does not guess at all but shows that a result follows from what you know.",
+          "examples": [
+            { "jp": "雨が降るかもしれない。", "en": "It might rain. (possible)" },
+            { "jp": "雨が降るはずだ。天気予報でそう言っていた。", "en": "It should rain. The forecast said so. (expected)" }
+          ]
+        }
+      ],
+      "attachment": [
+        {
+          "word_class": "verb",
+          "pattern": "plain form + はず / かもしれない / わけ",
+          "example": "行くはず / 行かないはず / 行ったはず / 行かなかったはず",
+          "note": "The same plain forms (present and past, positive and negative) come before all three. The polite ます form never does."
+        },
+        {
+          "word_class": "i-adjective",
+          "pattern": "plain form + はず / かもしれない / わけ",
+          "example": "高いはず / 高くないはず / 高かったはず"
+        },
+        {
+          "word_class": "na-adjective",
+          "pattern": "stem + な + はず / わけ; stem + かもしれない",
+          "example": "静かなはず / 静かなわけ / 静かかもしれない",
+          "note": "かもしれない takes the bare stem. はず and わけ take な, as before any noun."
+        },
+        {
+          "word_class": "noun",
+          "pattern": "noun + の + はず; noun + かもしれない; noun + な + わけ",
+          "example": "学生のはず / 学生かもしれない / 学生なわけがない",
+          "note": "かもしれない takes the bare noun. In the present, だ is dropped: 学生だかもしれない is wrong."
+        }
+      ],
+      "conjugations": [
+        { "form": "〜はずです", "register": "polite", "note": "Polite present. 〜はずでした for the past (\"was supposed to\")." },
+        { "form": "〜はずがありません", "register": "polite", "note": "\"There is no way.\" 〜はずはありません is the same." },
+        { "form": "〜かもしれません", "register": "polite", "note": "Polite maybe." },
+        { "form": "〜わけです", "register": "polite", "note": "\"It follows that...\"" },
+        { "form": "〜わけではありません", "register": "polite", "note": "\"It's not that...\"" },
+        { "form": "〜はずだ", "register": "casual", "note": "Plain present. 〜はずだった for the past." },
+        { "form": "〜はずがない", "register": "casual" },
+        { "form": "〜かもしれない", "register": "casual", "note": "Often shortened to かも, or かもね when talking with a friend." },
+        { "form": "〜わけだ", "register": "casual" },
+        { "form": "〜わけがない", "register": "casual", "note": "\"No way.\"" },
+        { "form": "〜わけじゃない", "register": "casual", "note": "The spoken form of わけではない." }
+      ],
+      "pitfalls": [
+        {
+          "heading": "かもしれない takes no だ",
+          "explanation": "Before かもしれない, a noun or na-adjective stays bare. 学生だかもしれない and 静かだかもしれない are wrong; say 学生かもしれない and 静かかもしれない.",
+          "examples": [
+            { "jp": "あの人は先生かもしれません。", "en": "That person might be a teacher." }
+          ]
+        },
+        {
+          "heading": "わけ and んです both explain, in different ways",
+          "explanation": "んです offers or asks for a reason for a situation in front of you. わけだ concludes from what you already know that the result is only natural. And わけではない trims a false inference, where んじゃない would deny the whole thing.",
+          "examples": [
+            { "jp": "遅れたのは、電車が止まったんです。", "en": "I was late because the train stopped. (giving a reason)" },
+            { "jp": "電車が止まったから、遅れたわけだ。", "en": "The train stopped, so that's why they were late. (drawing a conclusion)" }
+          ]
+        },
+        {
+          "heading": "わけにはいかない",
+          "explanation": "This is a fixed phrase meaning \"I cannot, for some reason\", often a duty or a social rule. 行かないわけにはいかない means \"I can't not go\", that is, \"I have to go\".",
+          "examples": [
+            { "jp": "明日は大事な会議だから、休むわけにはいかない。", "en": "Tomorrow is an important meeting, so I can't take the day off." },
+            { "jp": "友達の結婚式だから、行かないわけにはいかない。", "en": "It's a friend's wedding, so I can't not go." }
+          ]
+        }
+      ],
+      "related": ["appearance", "obligation", "n-desu"]
+    },
+    {
+      "id": "obligation",
+      "title": "べき・ものだ",
+      "summary": "べき says what someone should do, as advice or a moral judgement. ものだ states how things are in general, or remembers how things used to be.",
+      "level": "intermediate",
+      "usages": [
+        {
+          "heading": "べき: what someone should do",
+          "explanation": "Put べき after the dictionary form of a verb, then だ or です. It is a judgement about right and wrong, so it can sound strong.",
+          "examples": [
+            { "jp": "もっと野菜を食べるべきだ。", "en": "You should eat more vegetables." },
+            { "jp": "約束は守るべきです。", "en": "Promises should be kept." }
+          ]
+        },
+        {
+          "heading": "べきではない: what someone should not do",
+          "explanation": "べきではない (or べきじゃない in speech) says that something should not be done.",
+          "examples": [
+            { "jp": "ここで大きな声を出すべきではありません。", "en": "You shouldn't raise your voice here." },
+            { "jp": "人の悪口を言うべきじゃない。", "en": "You shouldn't speak ill of others." }
+          ]
+        },
+        {
+          "heading": "べきだった: should have",
+          "explanation": "In the past, べきだった says that something should have been done and wasn't. It carries regret or blame.",
+          "examples": [
+            { "jp": "もっと早く言うべきだった。", "en": "I should have said so sooner." },
+            { "jp": "昨日、休むべきでした。", "en": "I should have rested yesterday." }
+          ]
+        },
+        {
+          "heading": "ものだ: how things are",
+          "explanation": "ものだ presents something as a general truth or as human nature. The sentence is about people or things in general, not about one case.",
+          "examples": [
+            { "jp": "人は誰でも間違えるものです。", "en": "Everyone makes mistakes." },
+            { "jp": "子供は遊ぶものだ。", "en": "Children play. (that's what they do)" }
+          ]
+        },
+        {
+          "heading": "ものだ: remembering",
+          "explanation": "With the past plain form and a word like よく, ものだ looks back on something that used to happen again and again.",
+          "examples": [
+            { "jp": "子供のころ、よくこの川で泳いだものだ。", "en": "When I was little, I used to swim in this river all the time." },
+            { "jp": "学生のころは、毎日友達と遊んだものです。", "en": "When I was a student, I would play with my friends every day." }
+          ]
+        },
+        {
+          "heading": "ものだ: feeling",
+          "explanation": "After an adjective, ものだ turns the sentence into an exclamation, often with ね.",
+          "examples": [
+            { "jp": "時間がたつのは早いものですね。", "en": "Time really does fly, doesn't it." },
+            { "jp": "人の気持ちとは不思議なものだ。", "en": "How strange people's feelings are." }
+          ]
+        },
+        {
+          "heading": "ものではない: it isn't done",
+          "explanation": "ものではない after a verb says that something is not the done thing. It is common when scolding or advising.",
+          "examples": [
+            { "jp": "人の悪口を言うものではありません。", "en": "One shouldn't speak ill of others." },
+            { "jp": "夜遅くに電話をかけるものではない。", "en": "You shouldn't phone people late at night." }
+          ]
+        }
+      ],
+      "attachment": [
+        {
+          "word_class": "verb",
+          "pattern": "dictionary form + べき",
+          "example": "食べるべき / 行くべき / 守るべき",
+          "note": "する has two forms: するべき and すべき, which mean the same. The negative uses べきではない and does not change the verb: 食べるべきではない."
+        },
+        {
+          "word_class": "verb",
+          "condition": "General statements and memories",
+          "pattern": "plain form + ものだ",
+          "example": "忘れるものだ / 忘れたものだ",
+          "note": "The present form states a general truth. The past た-form recalls how things used to be."
+        },
+        {
+          "word_class": "i-adjective",
+          "pattern": "plain form + ものだ",
+          "example": "早いものだ / 難しいものだ",
+          "note": "Used as an exclamation."
+        },
+        {
+          "word_class": "na-adjective",
+          "pattern": "stem + な + ものだ",
+          "example": "不思議なものだ / 大変なものだ"
+        }
+      ],
+      "conjugations": [
+        { "form": "〜べきです", "register": "polite", "note": "\"Should.\" 〜べきでした is \"should have\"." },
+        { "form": "〜べきではありません", "register": "polite", "note": "\"Should not.\"" },
+        { "form": "〜ものです", "register": "polite", "note": "Polite ものだ. 〜ものでした for memories." },
+        { "form": "〜ものではありません", "register": "polite", "note": "\"It isn't done.\"" },
+        { "form": "〜べきだ", "register": "casual", "note": "Plain \"should\". 〜べきだった is \"should have\"." },
+        { "form": "〜べきじゃない", "register": "casual", "note": "The spoken form of べきではない." },
+        { "form": "〜ものだ", "register": "casual" },
+        { "form": "〜ものではない", "register": "casual", "note": "Also 〜ものじゃない in speech." }
+      ],
+      "pitfalls": [
+        {
+          "heading": "べき can sound bossy",
+          "explanation": "べき is a judgement, and it is not a gentle suggestion. To an equal or a superior, use ほうがいい instead (see below), or turn the advice into a question.",
+          "examples": [
+            { "jp": "もっと寝たほうがいいですよ。", "en": "You should get more sleep. (softer than 寝るべきです)" }
+          ]
+        },
+        {
+          "heading": "べき needs the dictionary form",
+          "explanation": "The ます form and the past form do not come before べき. To say \"should have\", move the tense onto だ: 行くべきだった, not 行ったべき.",
+          "examples": [
+            { "jp": "もっと勉強するべきだった。", "en": "I should have studied more." }
+          ]
+        },
+        {
+          "heading": "ものだ is not the same as もの",
+          "explanation": "もの on its own is a noun for a thing. ものだ is a fixed ending that turns the sentence into a statement of how things are or were, so it never refers to a particular object.",
+          "examples": [
+            { "jp": "この本は面白いものです。", "en": "This book is an interesting one. (a thing)" },
+            { "jp": "本は面白いものだ。", "en": "Books are interesting, as a rule. (a general truth)" }
+          ]
+        }
+      ],
+      "related": ["certainty"]
+    },
+    {
+      "id": "appearance",
+      "title": "よう・みたい・そう・らしい",
+      "summary": "Four ways to talk about what you see, hear or infer: ようだ and みたいだ (it seems, like), そうだ (it looks like, or I hear), and らしい (apparently, or typical of).",
+      "level": "intermediate",
+      "usages": [
+        {
+          "heading": "ようだ and みたいだ: it seems",
+          "explanation": "Use ようだ when you judge from what you can see, hear or feel yourself. みたいだ means the same and is more casual.",
+          "examples": [
+            { "jp": "誰かいるようです。", "en": "It seems someone is there." },
+            { "jp": "外は寒いみたいだ。", "en": "It seems cold outside." }
+          ]
+        },
+        {
+          "heading": "Like something else",
+          "explanation": "The same words also mean \"like\". The adverb is ように, and before a noun it is ような or みたいな.",
+          "examples": [
+            { "jp": "あの人は子供のように笑う。", "en": "He laughs like a child." },
+            { "jp": "夢みたいな話ですね。", "en": "It sounds like a dream." }
+          ]
+        },
+        {
+          "heading": "そう: it looks like",
+          "explanation": "After a stem, そう says how something looks or that it is about to happen. It is your impression, and not something you were told.",
+          "examples": [
+            { "jp": "このケーキはおいしそうです。", "en": "This cake looks delicious." },
+            { "jp": "今にも雨が降りそうだ。", "en": "It looks like it's going to rain at any moment." }
+          ]
+        },
+        {
+          "heading": "そう: I hear",
+          "explanation": "After a plain form, そうだ passes on something you heard. It is hearsay and does not mean you can see it yourself.",
+          "examples": [
+            { "jp": "明日は雨が降るそうです。", "en": "I hear it's going to rain tomorrow." },
+            { "jp": "田中さんは来ないそうだ。", "en": "I hear Mr. Tanaka isn't coming." }
+          ]
+        },
+        {
+          "heading": "らしい: apparently",
+          "explanation": "らしい also reports what you have heard or worked out, and often implies some evidence. It is less direct than ようだ.",
+          "examples": [
+            { "jp": "山田さんは風邪をひいたらしい。", "en": "Apparently Mr. Yamada caught a cold." },
+            { "jp": "駅の前に新しい店ができるらしいです。", "en": "I hear a new shop is opening in front of the station." }
+          ]
+        },
+        {
+          "heading": "らしい: typical of",
+          "explanation": "After a noun, らしい can instead describe what is typical of it. It is a compliment: it fits what it should be.",
+          "examples": [
+            { "jp": "今日は春らしい天気ですね。", "en": "It's spring-like weather today." },
+            { "jp": "学生らしい服を着なさい。", "en": "Wear clothes that suit a student." }
+          ]
+        }
+      ],
+      "attachment": [
+        {
+          "word_class": "verb",
+          "condition": "Seems, hearsay",
+          "pattern": "plain form + ようだ / みたいだ / らしい / そうだ (hearsay)",
+          "example": "行くようだ / 行ったみたいだ / 行かないらしい / 行くそうだ",
+          "note": "These four all take the plain form. The polite ます form never comes before them."
+        },
+        {
+          "word_class": "verb",
+          "condition": "Looks like",
+          "pattern": "ます stem + そうだ",
+          "example": "食べ + そうだ → 食べそうだ / 降り + そうだ → 降りそうだ",
+          "note": "This is the \"it looks like\" そう. Compare 食べるそうだ (I hear he eats)."
+        },
+        {
+          "word_class": "i-adjective",
+          "condition": "Seems, hearsay",
+          "pattern": "plain form + ようだ / みたいだ / らしい / そうだ (hearsay)",
+          "example": "高いようだ / 高いみたいだ / 高いらしい / 高いそうだ"
+        },
+        {
+          "word_class": "i-adjective",
+          "condition": "Looks like",
+          "pattern": "stem (drop い) + そうだ",
+          "example": "おいしい → おいしそう / 高い → 高そう",
+          "note": "いい becomes よさそう and ない becomes なさそう."
+        },
+        {
+          "word_class": "na-adjective",
+          "pattern": "stem + な + よう; stem + みたい; stem + らしい; stem + だそうだ",
+          "example": "静かなようだ / 静かみたいだ / 静からしい / 静かだそうだ",
+          "note": "ようだ takes な, みたいだ and らしい take the bare stem, and the hearsay そうだ keeps だ."
+        },
+        {
+          "word_class": "na-adjective",
+          "condition": "Looks like",
+          "pattern": "stem + そうだ",
+          "example": "元気 → 元気そう / 好き → 好きそう",
+          "note": "\"Looks like\"."
+        },
+        {
+          "word_class": "noun",
+          "pattern": "noun + の + よう; noun + みたい; noun + らしい; noun + だそうだ",
+          "example": "子供のようだ / 子供みたいだ / 子供らしい / 子供だそうだ",
+          "note": "ようだ takes の, みたいだ and らしい take the bare noun, and the hearsay そうだ keeps だ. 子供らしい can also mean \"childlike\"."
+        }
+      ],
+      "conjugations": [
+        { "form": "〜ようです", "register": "polite", "note": "Before a noun: 〜ような. As an adverb: 〜ように." },
+        { "form": "〜そうです", "register": "polite", "note": "Looks like, or I hear. Before a noun, the \"looks like\" one is 〜そうな: おいしそうなケーキ." },
+        { "form": "〜らしいです", "register": "polite", "note": "Apparently." },
+        { "form": "〜みたいだ", "register": "casual", "note": "Before a noun: 〜みたいな. As an adverb: 〜みたいに." },
+        { "form": "〜そうだ", "register": "casual", "note": "Looks like, or I hear." },
+        { "form": "〜らしい", "register": "casual", "note": "Apparently. 〜らしくない means \"not like oneself\"." }
+      ],
+      "pitfalls": [
+        {
+          "heading": "Two meanings of そう",
+          "explanation": "The same two syllables mean different things depending on what they attach to. On a stem they describe how it looks to you, and on a plain form they report hearsay.",
+          "examples": [
+            { "jp": "あの店のラーメンはおいしそうです。", "en": "That shop's ramen looks delicious. (you can see it)" },
+            { "jp": "あの店のラーメンはおいしいそうです。", "en": "I hear that shop's ramen is delicious. (somebody told you)" }
+          ]
+        },
+        {
+          "heading": "いい and ない before そう",
+          "explanation": "With そう (\"looks like\"), いい becomes よさそう and ない becomes なさそう, and neither is attached as it is. This is a very common mistake.",
+          "examples": [
+            { "jp": "今日は天気がよさそうです。", "en": "The weather looks good today." },
+            { "jp": "時間がなさそうですね。", "en": "You don't look like you have time." }
+          ]
+        },
+        {
+          "heading": "ようだ and らしい are not the same",
+          "explanation": "ようだ or みたいだ is your own impression, from something you have observed. らしい is for something you have heard or worked out from signs, and so you did not see it yourself.",
+          "examples": [
+            { "jp": "窓が開いているようだ。", "en": "The window seems to be open. (you can see it)" },
+            { "jp": "窓が開いているらしい。", "en": "Apparently the window is open. (you were told)" }
+          ]
+        }
+      ],
+      "related": ["certainty", "ppoi"]
+    },
+    {
+      "id": "ppoi",
+      "title": "っぽい",
+      "summary": "っぽい adds the feel of something: -ish, like, or prone to. It attaches to nouns, verb stems and い-adjective stems, and the result is an い-adjective.",
+      "level": "intermediate",
+      "usages": [
+        {
+          "heading": "-ish: it has the look or feel of",
+          "explanation": "After a noun, っぽい says that something is like it or looks like it. After a colour, it means a bit of that colour.",
+          "examples": [
+            { "jp": "このスープは水っぽい。", "en": "This soup is watery." },
+            { "jp": "黒っぽい服を着ています。", "en": "I'm wearing blackish clothes." },
+            { "jp": "今日はちょっと熱っぽいです。", "en": "I feel a bit feverish today." }
+          ]
+        },
+        {
+          "heading": "Prone to",
+          "explanation": "After the ます stem of a verb, っぽい says that someone does something easily or often. It is mostly used with a handful of verbs.",
+          "examples": [
+            { "jp": "父は忘れっぽいです。", "en": "My father is forgetful." },
+            { "jp": "弟は飽きっぽい。", "en": "My little brother gets bored easily." }
+          ]
+        },
+        {
+          "heading": "Slightly, and not in a good way",
+          "explanation": "After an い-adjective stem, っぽい often gives a slightly negative impression, such as cheap-looking.",
+          "examples": [
+            { "jp": "この時計は安っぽく見える。", "en": "This watch looks cheap." },
+            { "jp": "安っぽいおもちゃを買ってしまった。", "en": "I ended up buying a cheap-looking toy." }
+          ]
+        },
+        {
+          "heading": "っぽい and らしい",
+          "explanation": "Both come after a noun. らしい is a praise: it fits what it should be. っぽい only says that it looks like it, and is often a mild criticism.",
+          "examples": [
+            { "jp": "子供っぽい考えだ。", "en": "That's a childish idea." },
+            { "jp": "子供らしい笑顔ですね。", "en": "What a childlike smile." }
+          ]
+        }
+      ],
+      "attachment": [
+        {
+          "word_class": "noun",
+          "pattern": "noun + っぽい",
+          "example": "水っぽい / 子供っぽい / 白っぽい",
+          "note": "Colours and states are common: 黒っぽい, 赤っぽい, 熱っぽい."
+        },
+        {
+          "word_class": "verb",
+          "pattern": "ます stem + っぽい",
+          "example": "忘れ + っぽい → 忘れっぽい / 飽き + っぽい → 飽きっぽい / 怒り + っぽい → 怒りっぽい",
+          "note": "Only some verbs take it, so learn the common ones as vocabulary."
+        },
+        {
+          "word_class": "i-adjective",
+          "pattern": "stem (drop い) + っぽい",
+          "example": "安い → 安っぽい",
+          "note": "Only a few adjectives take it."
+        }
+      ],
+      "conjugations": [
+        { "form": "〜っぽいです", "register": "polite", "note": "Polite present." },
+        { "form": "〜っぽくないです", "register": "polite", "note": "Negative. Also 〜っぽくありません." },
+        { "form": "〜っぽい", "register": "casual", "note": "It is an い-adjective, so it conjugates as one." },
+        { "form": "〜っぽくない", "register": "casual", "note": "Negative." },
+        { "form": "〜っぽかった", "register": "casual", "note": "Past." },
+        { "form": "〜っぽくて", "register": "casual", "note": "て-form, for joining sentences." },
+        { "form": "〜っぽく", "register": "casual", "note": "Adverb: 子供っぽく話す." }
+      ],
+      "pitfalls": [
+        {
+          "heading": "It is casual",
+          "explanation": "っぽい belongs to spoken, everyday Japanese. In formal writing, use ような or らしい.",
+          "examples": [
+            { "jp": "彼の話し方は少し子供っぽい。", "en": "The way he talks is a little childish." }
+          ]
+        },
+        {
+          "heading": "It is an い-adjective",
+          "explanation": "After you add っぽい, the whole word conjugates like any い-adjective: 子供っぽくない, 子供っぽかった, 子供っぽくて.",
+          "examples": [
+            { "jp": "そのドレスはあまり安っぽくないですね。", "en": "That dress doesn't look very cheap." }
+          ]
+        }
+      ],
+      "related": ["appearance"]
     }
   ]
 }
```

- [ ] **Step 4: Add the readings**

```bash
python3 scripts/update_data.py 2>&1 | head -5
```

Expected: the coverage check fails with `kanji without a reading in furigana.json:` and lists runs such as `田中`, `家`, `駅` (output is capped at 20 lines). Now apply this diff to `data/furigana.json`. It adds 71 entries, kept in sorted order:

```diff
diff --git a/data/furigana.json b/data/furigana.json
index f9aa438..94f9405 100644
--- a/data/furigana.json
+++ b/data/furigana.json
@@ -3,46 +3,85 @@
   "description": "Readings for the kanji used in the app's data. A key is a run of kanji, optionally followed by up to three hiragana that select the reading (来ら -> こ); the value is the hiragana reading of the kanji part only. Hand-authored; run scripts/update_data.py after editing.",
   "readings": {
     "三": "さん",
+    "三時": "さんじ",
     "上手": "じょうず",
+    "不思議": "ふしぎ",
     "京都": "きょうと",
+    "人": "ひと",
     "今": "いま",
     "今夜": "こんや",
     "今日": "きょう",
+    "休": "やす",
     "会": "あ",
+    "会議": "かいぎ",
     "住": "す",
     "何": "なに",
     "何時": "なんじ",
     "使": "つか",
     "借": "か",
+    "元気": "げんき",
     "兄": "あに",
+    "先生": "せんせい",
     "写真": "しゃしん",
+    "出": "で",
+    "前": "まえ",
     "勉強": "べんきょう",
     "十一時": "じゅういちじ",
+    "友達": "ともだち",
     "取": "と",
     "可能形": "かのうけい",
     "声": "こえ",
     "外": "そと",
+    "夜": "よる",
+    "夢": "ゆめ",
+    "大": "おお",
+    "大事": "だいじ",
+    "大変": "たいへん",
+    "天気": "てんき",
+    "天気予報": "てんきよほう",
+    "好": "す",
     "妹": "いもうと",
+    "始": "はじ",
+    "嫌": "きら",
+    "子供": "こども",
     "学校": "がっこう",
     "学生": "がくせい",
+    "守": "まも",
+    "安": "やす",
     "実": "じつ",
+    "家": "いえ",
     "富士山": "ふじさん",
+    "寒": "さむ",
     "寝": "ね",
+    "少": "すこ",
+    "山田": "やまだ",
+    "川": "かわ",
     "店": "みせ",
     "引": "ひ",
+    "弟": "おとうと",
+    "彼": "かれ",
     "待": "ま",
+    "忘": "わす",
+    "怒": "おこ",
     "急": "いそ",
+    "悪口": "わるぐち",
     "手伝": "てつだ",
     "抜": "ぬ",
     "持": "も",
     "撮": "と",
+    "新": "あたら",
+    "方": "かた",
     "日本": "にほん",
     "日本語": "にほんご",
     "早": "はや",
     "明日": "あした",
+    "春": "はる",
     "昨日": "きのう",
+    "時計": "とけい",
+    "時間": "じかん",
     "曲": "きょく",
     "書": "か",
+    "服": "ふく",
     "朝": "あさ",
     "本": "ほん",
     "来": "く",
@@ -57,21 +96,42 @@
     "止": "と",
     "死": "し",
     "毎日": "まいにち",
+    "気持": "きも",
+    "水": "みず",
     "泳": "およ",
     "漢字": "かんじ",
     "無料": "むりょう",
+    "熱": "ねつ",
+    "父": "ちち",
     "犬": "いぬ",
+    "田中": "たなか",
     "疲": "つか",
     "痛": "いた",
+    "白": "しろ",
+    "眠": "ねむ",
+    "着": "つ",
+    "知": "し",
     "私": "わたし",
+    "窓": "まど",
+    "笑": "わら",
+    "笑顔": "えがお",
+    "約束": "やくそく",
     "納豆": "なっとう",
+    "終": "お",
+    "結婚式": "けっこんしき",
+    "練習": "れんしゅう",
+    "考": "かんが",
     "聞": "き",
     "行": "い",
     "見": "み",
+    "言": "い",
     "言葉": "ことば",
+    "訳": "わけ",
     "話": "はな",
     "読": "よ",
+    "誰": "だれ",
     "買": "か",
+    "赤": "あか",
     "起": "お",
     "越": "こ",
     "返": "かえ",
@@ -80,15 +140,26 @@
     "遅れ": "おく",
     "遊": "あそ",
     "道": "みち",
+    "違": "ちが",
     "酒": "さけ",
+    "野菜": "やさい",
+    "開": "あ",
+    "間違": "まちが",
     "降": "ふ",
+    "難": "むずか",
     "雨": "あめ",
+    "電話": "でんわ",
     "電車": "でんしゃ",
     "静": "しず",
+    "面白": "おもしろ",
     "頭": "あたま",
+    "風邪": "かぜ",
     "食": "た",
     "飲": "の",
+    "飽": "あ",
+    "駅": "えき",
     "高": "たか",
-    "鳥": "とり"
+    "鳥": "とり",
+    "黒": "くろ"
   }
 }
```

- [ ] **Step 5: Generate the manifest and run every guard**

```bash
python3 scripts/update_data.py
git diff --stat data | cat
python3 scripts/update_data.py --check
```

Expected: the script reports `updated data/manifest.json (verbs 1.2.0, grammar 1.2.0, furigana 1.1.0)`; `git diff --stat` shows `grammar.json`, `furigana.json` and `manifest.json` changed and `verbs.json` not; `--check` prints `data is up to date`.

- [ ] **Step 6: Run the whole suite to verify it passes**

```bash
cd Packages/VerbKit && swift test 2>&1 | grep -E "error:|failed|Executed .* tests" | tail -1
cd ../.. && python3 -m unittest discover -s scripts -p "test_*.py" 2>&1 | tail -2
```

Expected: `Executed 182 tests, with 0 failures` (178 plus 4 new); `Ran 72 tests ... OK`.

- [ ] **Step 7: Commit**

```bash
git add data Packages/VerbKit
git commit -m "$(cat <<'EOF'
Add the four nuance-ending lessons

はず・かもしれない・わけ, べき・ものだ, よう・みたい・そう・らしい and
っぽい, as intermediate lessons in the existing shape, with their readings
and the manifest versions bumped by the script. んです links to the new
certainty lesson, and every related link in the file is mutual.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: The Grammar section on the verb page

**Files:**
- Create: `App/VerbGrammarSection.swift`
- Modify: `App/VerbDetailView.swift`

**Interfaces:**
- Consumes: `attachingToVerbs` (Task 2), `VerbStore.grammarPoints`, `Route`, `openRoute` (`App/OpenRouteAction.swift`) and `JapaneseText` (furigana work).
- Produces: `VerbGrammarSection()`, which reads `VerbStore` and `openRoute` from the environment, so `VerbDetailView` needs no new parameters.

- [ ] **Step 1: Create the section**

`App/VerbGrammarSection.swift`. Its rows copy `PotentialFormsSection`'s glass tile style; titles and summaries go through `JapaneseText`, so they get furigana:

```swift
import SwiftUI
import VerbKit

/// Every lesson that attaches to verbs, as links, at the bottom of a verb's
/// page. Driven by the lesson data, so lessons added later appear on their own;
/// hidden until grammar has synced.
struct VerbGrammarSection: View {
    @Environment(VerbStore.self) private var verbStore
    @Environment(\.openRoute) private var openRoute
    @State private var isExpanded = false

    private var lessons: [GrammarPoint] {
        verbStore.grammarPoints.attachingToVerbs
    }

    var body: some View {
        if !lessons.isEmpty {
            DisclosureGroup("Grammar", isExpanded: $isExpanded) {
                VStack(spacing: 8) {
                    ForEach(lessons) { lesson in
                        Button {
                            openRoute(.grammar(lesson.id))
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                JapaneseText(lesson.title)
                                    .font(.headline)
                                JapaneseText(lesson.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .glassEffect(in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }
            .font(.subheadline.weight(.semibold))
        }
    }
}
```

- [ ] **Step 2: Show it last on verb detail**

Apply this diff to `App/VerbDetailView.swift`:

```diff
diff --git a/App/VerbDetailView.swift b/App/VerbDetailView.swift
index 0bcaf91..5b2259c 100644
--- a/App/VerbDetailView.swift
+++ b/App/VerbDetailView.swift
@@ -128,6 +128,8 @@ struct VerbDetailView: View {
             if verb.forms.hasNdForms {
                 NdesuFormsSection(forms: verb.forms)
             }
+
+            VerbGrammarSection()
         }
     }
 }
```

- [ ] **Step 3: Build both platforms**

```bash
./scripts/generate-project.sh
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_macOS -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
```

Expected: `** BUILD SUCCEEDED **` twice.

- [ ] **Step 4: Run the app in the iOS Simulator against the local data**

The app reads its data from GitHub `main`, which does not have these lessons yet, so point it at a local copy for this check only:

1. **Check the port is free** (another session may share the machine): `lsof -i :8769`. If taken, pick another and use it below.
2. Serve the data: `(cd data && python3 -m http.server 8769 --bind 127.0.0.1) &` and remember its process id.
3. **Temporary edit, reverted in Step 5:** in `Packages/VerbKit/Sources/VerbKit/Data/GitHubVerbFetcher.swift`, change `githubMain`'s `base` to `"http://127.0.0.1:8769/"`.
4. **Use a unique bundle id**, so your install and its saved sync state cannot collide with another session's build of the same app (a collision shows up as a bogus "Something Went Wrong" screen):
   ```bash
   xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/nuancecheck CODE_SIGNING_ALLOWED=NO PRODUCT_BUNDLE_IDENTIFIER=dev.martinloeseth.jpverbconjugation.nuancecheck build 2>&1 | tail -3
   xcrun simctl uninstall booted dev.martinloeseth.jpverbconjugation.nuancecheck
   ```
   Then install and launch `/tmp/nuancecheck/Build/Products/Debug-iphonesimulator/JP Verb Conjugation.app` with the iOS Simulator tool, passing that bundle id.
5. Uninstall between runs (the same command as above): with no App Group the store is in memory but sync state persists, so a relaunch would report "up to date" with no data.

Expected, in the app:
- Open **Verbs → たべる**, scroll to the bottom. After Potential and んです there is a collapsed **Grammar** section. Expanding it shows six glass rows, in this order: **んです**, **可能形** (with かのうけい above it), **はず・かもしれない・わけ**, **べき・ものだ**, **よう・みたい・そう・らしい**, **っぽい**, each with a one-line summary.
- Tapping a row switches to the Grammar tab and lands on that lesson. This must work on a fresh install where the Grammar tab was never opened.
- In **はず・かもしれない・わけ**: "How it attaches" shows four cards (Verb, い-adjective, na-adjective, noun); the example sentences show readings (田中 たなか, 会議 かいぎ, 三時 さんじ, 山田 やまだ …); a fast scroll through the whole page stays smooth.
- Spot-check the other three lessons: **べき・ものだ** (seven usages), **よう・みたい・そう・らしい** (the two そう, よさそう / なさそう under "Watch out") and **っぽい**. Check light and dark appearance.
- Open the **んです** lesson: its "Related" section now links to the はず・かもしれない・わけ lesson, and that lesson links back.

> Not exercised in the verification run: iPad and macOS layout, and the offline path (a verb page with no grammar synced simply shows no Grammar section; the filter's empty case is covered by `GrammarVerbLessonsTests`).

- [ ] **Step 5: Undo the temporary edit and clean up**

```bash
git checkout Packages/VerbKit/Sources/VerbKit/Data/GitHubVerbFetcher.swift
kill <the http.server process id>        # only the server you started
xcrun simctl uninstall booted dev.martinloeseth.jpverbconjugation.nuancecheck
git status --short                       # only the App/ files of this task
```

- [ ] **Step 6: Commit**

```bash
git add App
git commit -m "$(cat <<'EOF'
Add a Grammar section to every verb page

A collapsed list, last on the page, of every lesson that attaches to verbs,
filled from the lesson data so later lessons appear on their own. Each row
opens its lesson through Route, and the section is hidden until grammar has
synced.

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

Expected: `Executed 182 tests, with 0 failures`; `Ran 72 tests ... OK`; `data is up to date`.

- [ ] **Step 2: Build both app targets from a clean generate**

```bash
./scripts/generate-project.sh
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_macOS -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)"
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)"
```

Expected: `** BUILD SUCCEEDED **` twice.

- [ ] **Step 3: Confirm no temporary changes are left**

```bash
grep -n "raw.githubusercontent.com" Packages/VerbKit/Sources/VerbKit/Data/GitHubVerbFetcher.swift
grep -rn "127.0.0.1" Packages App scripts | grep -v "/.build/"
grep -rln "accessibility" App | grep -E "VerbGrammarSection"
git status --short
```

Expected: the first command shows the `raw.githubusercontent.com/.../main/data/` line; the next two print nothing; the last shows a clean tree.

- [ ] **Step 4: Merge gracefully**

```bash
git log --oneline main..HEAD | cat                      # only this work's commits
git diff --name-only HEAD...main -- . ':!docs' | cat    # what main changed since we branched
```

If the second command prints nothing, the merge is a fast-forward: from the main checkout, `git merge --ff-only feature/nuance-endings-impl`. If `main` has moved (including from another session's pushes), do **not** force anything: fetch, merge `origin/main` into the branch (or rebase), keep `main`'s side of any conflict and re-apply only this plan's edits to that file, then re-run Steps 1–3. Get the user's go-ahead before merging into `main`.

- [ ] **Step 5: Publish (needs the user's explicit go-ahead)**

The app reads its data from GitHub `main`, so the lessons reach users only after the commits are pushed. **Do not push without asking the user first.** An app build from before this work shows the new lessons in its Grammar tab as ordinary lessons and simply lacks the verb-page section. After they approve and the push lands, compare the served bytes with the manifest (GitHub's CDN caches for about five minutes, so retry before worrying):

```bash
B=https://raw.githubusercontent.com/martinloesethjensen/jp-verb-conjugation-app/main/data
for f in manifest verbs grammar furigana; do curl -s -o /tmp/pub-$f.json $B/$f.json; done
python3 - <<'PY'
import hashlib, json
m = json.load(open("/tmp/pub-manifest.json"))
def h(n): return hashlib.sha256(open(f"/tmp/pub-{n}.json","rb").read()).hexdigest()
print("verbs    ", h("verbs") == m["sha256"])
print("grammar  ", h("grammar") == m["grammar"]["sha256"])
print("furigana ", h("furigana") == m["furigana"]["sha256"])
PY
```

Expected: three `True` lines.
