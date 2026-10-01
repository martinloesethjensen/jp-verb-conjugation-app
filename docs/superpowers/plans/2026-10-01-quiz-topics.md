# Quiz Topics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the quiz ask about every generated form (potential, んです, auxiliaries) through a topic sheet, with two question kinds: conjugate and identify the form.

**Architecture:** A pure catalogue (`QuizForm`, 48 entries, built from label parts) in VerbKit says what is quizzable and how each form reads from a verb. `buildQuestions(verbs:topics:count:kinds:)` builds conjugate and identify questions from it. The app gets a `QuizTopicSheet` shown before every quiz and the existing question and results screens learn the new types.

**Tech Stack:** Swift 5 package `VerbKit` (XCTest), SwiftUI for iOS 26 / macOS 26, XcodeGen project (`project.yml`, regenerate with `xcodegen generate` after adding or deleting app files).

**Spec:** `docs/superpowers/specs/2026-10-01-quiz-topics-design.md`

## Global Constraints

- No data, script or schema change. `data/*.json` and `scripts/` are not touched.
- `FormKey` and `VerbForms` stay exactly as they are; the catalogue only reads from `VerbForms`.
- The quiz keeps its 20-second timer, question-count setting, feedback and results flow.
- Labels use the pattern `name · register · past · negative` with `·` (U+00B7) separators; name is omitted for Basic, `past` only for past, `negative` only for negative. `て-form` is a register word.
- Visual direction: standard controls, `.glassEffect` for custom surfaces, no accessibility-specific modifiers (no `.accessibilityLabel` etc.) in new code.
- `Text + Text` is deprecated on iOS 26: use string interpolation of styled `Text`s.
- Tests: `cd Packages/VerbKit && swift test`. All 228 existing tests must still pass at the end, apart from the quiz tests this plan rewrites.
- Commit messages end with: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

---

### Task 1: The forms catalogue

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Quiz/QuizTopic.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Quiz/QuizForm.swift`
- Create: `Packages/VerbKit/Tests/VerbKitTests/RealVerbs.swift`
- Create: `Packages/VerbKit/Tests/VerbKitTests/QuizFormTests.swift`

**Interfaces:**
- Consumes: `VerbForms` (all fields named as in `Models/VerbForms.swift`), `Verb`, `VerbDataFile` (decodes `data/verbs.json`).
- Produces (used by Tasks 2 and 3):
  - `public enum QuizTopic: String, CaseIterable, Sendable { case basic, potential, nDesu, auxiliaries; public var title: String }` where titles are `Basic forms`, `Potential`, `んです`, `Auxiliaries`.
  - `public struct QuizForm: Hashable, Sendable` with `public let id: String`, `public let topic: QuizTopic`, `public let label: String`, `public func value(in forms: VerbForms) -> String?` (nil when the field is nil or empty), `public static let all: [QuizForm]` (48 entries, in display order), `public static func available(in forms: VerbForms, topics: Set<QuizTopic>) -> [(form: QuizForm, value: String)]`.
  - `public struct QuizTopicChoice: Equatable, Sendable { public let topic: QuizTopic; public let count: Int }` and `public static func QuizTopic.choices(for verbs: [Verb]) -> [QuizTopicChoice]` (only topics with `count > 0`, in `allCases` order; `count` is the total number of forms the verbs have in that topic).
  - Test helper `RealVerbs.load() throws -> [Verb]` (reads `data/verbs.json`).

- [ ] **Step 1: Write the test helper and the failing tests**

`Packages/VerbKit/Tests/VerbKitTests/RealVerbs.swift`:

```swift
import Foundation
@testable import VerbKit

/// The 25 verbs in the real `data/verbs.json`, for tests that run over real data.
enum RealVerbs {
    static func load() throws -> [Verb] {
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
}
```

`Packages/VerbKit/Tests/VerbKitTests/QuizFormTests.swift`:

```swift
import XCTest
@testable import VerbKit

final class QuizFormTests: XCTestCase {
    private func verb(_ dict: String) throws -> Verb {
        try XCTUnwrap(try RealVerbs.load().first { $0.dict == dict }, dict)
    }

    func testCatalogueHasFortyEightFormsWithUniqueIds() {
        XCTAssertEqual(QuizForm.all.count, 48)
        XCTAssertEqual(Set(QuizForm.all.map(\.id)).count, 48)
        XCTAssertEqual(Set(QuizForm.all.map(\.label)).count, 48, "labels must be unique so identify has one answer")
    }

    func testTopicSizes() {
        func count(_ topic: QuizTopic) -> Int { QuizForm.all.filter { $0.topic == topic }.count }
        XCTAssertEqual(count(.basic), 9)
        XCTAssertEqual(count(.potential), 9)
        XCTAssertEqual(count(.nDesu), 8)
        XCTAssertEqual(count(.auxiliaries), 22)
    }

    func testLabelsFollowTheParts() {
        func label(_ id: String) -> String? { QuizForm.all.first { $0.id == id }?.label }
        XCTAssertEqual(label("te"), "て-form")
        XCTAssertEqual(label("short_pos"), "Plain")
        XCTAssertEqual(label("short_neg"), "Plain · negative")
        XCTAssertEqual(label("masu_past_neg"), "Polite · past · negative")
        XCTAssertEqual(label("potential"), "Potential · plain")
        XCTAssertEqual(label("pot_masu_past"), "Potential · polite · past")
        XCTAssertEqual(label("pot_te"), "Potential · て-form")
        XCTAssertEqual(label("nd_casual_past"), "んです · casual · past")
        XCTAssertEqual(label("nd_past_neg"), "んです · polite · past · negative")
        XCTAssertEqual(label("teiru_masu_neg"), "ている · polite · negative")
        XCTAssertEqual(label("teiru_te"), "ている · て-form")
        XCTAssertEqual(label("teshimau_polite"), "てしまう · polite")
        XCTAssertEqual(label("teoku"), "ておく · plain")
        XCTAssertEqual(label("nagara"), "ながら")
    }

    func testValueReadsTheRightField() throws {
        let taberu = try verb("たべる")
        let byId = Dictionary(uniqueKeysWithValues: QuizForm.all.map { ($0.id, $0) })
        XCTAssertEqual(byId["masu_pos"]?.value(in: taberu.forms), "たべます")
        XCTAssertEqual(byId["pot_masu_past"]?.value(in: taberu.forms), "たべられました")
        XCTAssertEqual(byId["nd_casual_neg"]?.value(in: taberu.forms), "たべないんだ")
        XCTAssertEqual(byId["teiru_masu_past_neg"]?.value(in: taberu.forms), "たべていませんでした")
        XCTAssertEqual(byId["nagara"]?.value(in: taberu.forms), "たべながら")
    }

    func testEveryFormTheDataPopulatesIsInTheCatalogueExactlyOnce() throws {
        var populated = Set<String>()
        for verb in try RealVerbs.load() {
            let data = try JSONEncoder().encode(verb.forms)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            populated.formUnion(object.keys)
        }
        XCTAssertEqual(populated, Set(QuizForm.all.map(\.id)))
    }

    func testAvailableSkipsFormsAVerbLacks() throws {
        let aru = try verb("ある")
        let all = QuizForm.available(in: aru.forms, topics: Set(QuizTopic.allCases))
        XCTAssertEqual(all.count, 24)
        XCTAssertTrue(all.allSatisfy { !$0.value.isEmpty })
        XCTAssertFalse(all.contains { $0.form.topic == .potential })
        let taberu = try verb("たべる")
        XCTAssertEqual(QuizForm.available(in: taberu.forms, topics: Set(QuizTopic.allCases)).count, 48)
        XCTAssertEqual(QuizForm.available(in: taberu.forms, topics: [.nDesu]).count, 8)
    }

    func testTopicChoicesCountFormsAndHideEmptyTopics() throws {
        let aru = try verb("ある")
        let choices = QuizTopic.choices(for: [aru])
        XCTAssertFalse(choices.contains { $0.topic == .potential })
        XCTAssertEqual(choices.first { $0.topic == .basic }?.count, 9)
        let all = QuizTopic.choices(for: try RealVerbs.load())
        XCTAssertEqual(all.map(\.topic), QuizTopic.allCases)
        XCTAssertEqual(all.first { $0.topic == .basic }?.count, 25 * 9)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd Packages/VerbKit && swift test --filter QuizFormTests`
Expected: FAIL to compile ("cannot find 'QuizForm' in scope").

- [ ] **Step 3: Implement**

`Packages/VerbKit/Sources/VerbKit/Quiz/QuizTopic.swift`:

```swift
/// What a quiz can practise. "Everything" is not a topic: it is all of them at once.
public enum QuizTopic: String, CaseIterable, Sendable {
    case basic, potential, nDesu, auxiliaries

    public var title: String {
        switch self {
        case .basic: return "Basic forms"
        case .potential: return "Potential"
        case .nDesu: return "んです"
        case .auxiliaries: return "Auxiliaries"
        }
    }
}

/// One row of the topic sheet: a topic and how many forms the verbs in play have in it.
public struct QuizTopicChoice: Equatable, Sendable {
    public let topic: QuizTopic
    public let count: Int
}

extension QuizTopic {
    /// The topics worth offering for these verbs, in display order, skipping any
    /// the verbs have no forms in (ある has no Potential).
    public static func choices(for verbs: [Verb]) -> [QuizTopicChoice] {
        allCases.compactMap { topic in
            let count = verbs.reduce(0) { $0 + QuizForm.available(in: $1.forms, topics: [topic]).count }
            return count > 0 ? QuizTopicChoice(topic: topic, count: count) : nil
        }
    }
}
```

`Packages/VerbKit/Sources/VerbKit/Quiz/QuizForm.swift`:

```swift
/// One thing the quiz can ask about: a form of a verb, with the label the quiz
/// shows for it and the way to read it from a verb's `VerbForms`.
public struct QuizForm: Hashable, Sendable {
    /// The form's JSON key, e.g. "pot_masu_past".
    public let id: String
    public let topic: QuizTopic
    /// Built from parts: "Potential · polite · past".
    public let label: String
    private let read: @Sendable (VerbForms) -> String?

    /// The form's string for a verb, or nil when the verb has none (nil or empty).
    public func value(in forms: VerbForms) -> String? {
        guard let value = read(forms), !value.isEmpty else { return nil }
        return value
    }

    public static func == (a: QuizForm, b: QuizForm) -> Bool { a.id == b.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// The forms of these topics that `forms` actually has, in catalogue order.
    public static func available(
        in forms: VerbForms, topics: Set<QuizTopic>
    ) -> [(form: QuizForm, value: String)] {
        all.compactMap { form in
            guard topics.contains(form.topic), let value = form.value(in: forms) else { return nil }
            return (form, value)
        }
    }

    private static func make(
        _ id: String, _ topic: QuizTopic, name: String?, register: String?,
        past: Bool = false, negative: Bool = false,
        _ read: @escaping @Sendable (VerbForms) -> String?
    ) -> QuizForm {
        let label = [name, register, past ? "past" : nil, negative ? "negative" : nil]
            .compactMap { $0 }
            .joined(separator: " · ")
        return QuizForm(id: id, topic: topic, label: label, read: read)
    }

    public static let all: [QuizForm] = [
        // Basic: the name is left out, so the labels read "Polite · past".
        make("masu_pos", .basic, name: nil, register: "Polite") { $0.masuPos },
        make("masu_neg", .basic, name: nil, register: "Polite", negative: true) { $0.masuNeg },
        make("masu_past", .basic, name: nil, register: "Polite", past: true) { $0.masuPast },
        make("masu_past_neg", .basic, name: nil, register: "Polite", past: true, negative: true) { $0.masuPastNeg },
        make("te", .basic, name: nil, register: "て-form") { $0.te },
        make("short_pos", .basic, name: nil, register: "Plain") { $0.shortPos },
        make("short_neg", .basic, name: nil, register: "Plain", negative: true) { $0.shortNeg },
        make("short_past", .basic, name: nil, register: "Plain", past: true) { $0.shortPast },
        make("short_past_neg", .basic, name: nil, register: "Plain", past: true, negative: true) { $0.shortPastNeg },

        // Potential
        make("potential", .potential, name: "Potential", register: "plain") { $0.potential },
        make("pot_masu_pos", .potential, name: "Potential", register: "polite") { $0.potMasuPos },
        make("pot_masu_neg", .potential, name: "Potential", register: "polite", negative: true) { $0.potMasuNeg },
        make("pot_masu_past", .potential, name: "Potential", register: "polite", past: true) { $0.potMasuPast },
        make("pot_masu_past_neg", .potential, name: "Potential", register: "polite", past: true, negative: true) { $0.potMasuPastNeg },
        make("pot_te", .potential, name: "Potential", register: "て-form") { $0.potTe },
        make("pot_short_neg", .potential, name: "Potential", register: "plain", negative: true) { $0.potShortNeg },
        make("pot_short_past", .potential, name: "Potential", register: "plain", past: true) { $0.potShortPast },
        make("pot_short_past_neg", .potential, name: "Potential", register: "plain", past: true, negative: true) { $0.potShortPastNeg },

        // んです
        make("nd_pos", .nDesu, name: "んです", register: "polite") { $0.ndPos },
        make("nd_neg", .nDesu, name: "んです", register: "polite", negative: true) { $0.ndNeg },
        make("nd_past", .nDesu, name: "んです", register: "polite", past: true) { $0.ndPast },
        make("nd_past_neg", .nDesu, name: "んです", register: "polite", past: true, negative: true) { $0.ndPastNeg },
        make("nd_casual_pos", .nDesu, name: "んです", register: "casual") { $0.ndCasualPos },
        make("nd_casual_neg", .nDesu, name: "んです", register: "casual", negative: true) { $0.ndCasualNeg },
        make("nd_casual_past", .nDesu, name: "んです", register: "casual", past: true) { $0.ndCasualPast },
        make("nd_casual_past_neg", .nDesu, name: "んです", register: "casual", past: true, negative: true) { $0.ndCasualPastNeg },

        // Auxiliaries: ている in full, then a plain and a polite form for most, ながら alone.
        make("teiru", .auxiliaries, name: "ている", register: "plain") { $0.teiru },
        make("teiru_neg", .auxiliaries, name: "ている", register: "plain", negative: true) { $0.teiruNeg },
        make("teiru_past", .auxiliaries, name: "ている", register: "plain", past: true) { $0.teiruPast },
        make("teiru_past_neg", .auxiliaries, name: "ている", register: "plain", past: true, negative: true) { $0.teiruPastNeg },
        make("teiru_masu_pos", .auxiliaries, name: "ている", register: "polite") { $0.teiruMasuPos },
        make("teiru_masu_neg", .auxiliaries, name: "ている", register: "polite", negative: true) { $0.teiruMasuNeg },
        make("teiru_masu_past", .auxiliaries, name: "ている", register: "polite", past: true) { $0.teiruMasuPast },
        make("teiru_masu_past_neg", .auxiliaries, name: "ている", register: "polite", past: true, negative: true) { $0.teiruMasuPastNeg },
        make("teiru_te", .auxiliaries, name: "ている", register: "て-form") { $0.teiruTe },
        make("teshimau", .auxiliaries, name: "てしまう", register: "plain") { $0.teshimau },
        make("teshimau_polite", .auxiliaries, name: "てしまう", register: "polite") { $0.teshimauPolite },
        make("teoku", .auxiliaries, name: "ておく", register: "plain") { $0.teoku },
        make("teoku_polite", .auxiliaries, name: "ておく", register: "polite") { $0.teokuPolite },
        make("temiru", .auxiliaries, name: "てみる", register: "plain") { $0.temiru },
        make("temiru_polite", .auxiliaries, name: "てみる", register: "polite") { $0.temiruPolite },
        make("sugiru", .auxiliaries, name: "すぎる", register: "plain") { $0.sugiru },
        make("sugiru_polite", .auxiliaries, name: "すぎる", register: "polite") { $0.sugiruPolite },
        make("yasui", .auxiliaries, name: "やすい", register: "plain") { $0.yasui },
        make("yasui_polite", .auxiliaries, name: "やすい", register: "polite") { $0.yasuiPolite },
        make("nikui", .auxiliaries, name: "にくい", register: "plain") { $0.nikui },
        make("nikui_polite", .auxiliaries, name: "にくい", register: "polite") { $0.nikuiPolite },
        make("nagara", .auxiliaries, name: "ながら", register: nil) { $0.nagara },
    ]
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd Packages/VerbKit && swift test --filter QuizFormTests`
Expected: PASS (7 tests). Then `swift test` for the whole package: all pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/VerbKit/Sources/VerbKit/Quiz/QuizTopic.swift Packages/VerbKit/Sources/VerbKit/Quiz/QuizForm.swift Packages/VerbKit/Tests/VerbKitTests/RealVerbs.swift Packages/VerbKit/Tests/VerbKitTests/QuizFormTests.swift
git commit -m "Add the quiz forms catalogue and topics"
```

---

### Task 2: Question model, generator and results

**Files:**
- Modify: `Packages/VerbKit/Sources/VerbKit/Quiz/QuizQuestion.swift`
- Modify: `Packages/VerbKit/Sources/VerbKit/Quiz/QuizResult.swift`
- Modify: `Packages/VerbKit/Sources/VerbKit/Quiz/QuizGenerator.swift` (replace the whole file)
- Modify: `Packages/VerbKit/Sources/VerbKit/Quiz/QuizViewModel.swift` (the `choose` method only)
- Modify (rewrite): `Packages/VerbKit/Tests/VerbKitTests/QuizGeneratorTests.swift`
- Modify: `Packages/VerbKit/Tests/VerbKitTests/QuizViewModelTests.swift` (the `makeQuestion` helper only)

**Interfaces:**
- Consumes (Task 1): `QuizTopic`, `QuizForm` (`id`, `topic`, `label`, `value(in:)`, `all`, `available(in:topics:)`), `RealVerbs.load()`.
- Produces (used by Task 3):
  - `public enum QuizQuestionKind: Sendable { case conjugate, identify }`.
  - `public struct QuizQuestion: Equatable, Sendable` with `verb: Verb`, `form: QuizForm`, `kind: QuizQuestionKind`, `formString: String`, `correct: String` (the string for `.conjugate`, the label for `.identify`), `choices: [String]`; memberwise `public init(verb:form:kind:formString:correct:choices:)`.
  - `public struct QuizResult: Equatable, Sendable` with `verb: String`, `formLabel: String`, `formString: String`, `kind: QuizQuestionKind`, `correct: String`, `chosen: String`, `ok: Bool`; memberwise `public init(verb:formLabel:formString:kind:correct:chosen:ok:)`.
  - `public func buildQuestions(verbs: [Verb], topics: Set<QuizTopic>, count: Int, kinds: [QuizQuestionKind] = [.conjugate, .identify]) -> [QuizQuestion]`.

- [ ] **Step 1: Write the failing tests**

Replace `Packages/VerbKit/Tests/VerbKitTests/QuizGeneratorTests.swift` with:

```swift
import XCTest
@testable import VerbKit

final class QuizGeneratorTests: XCTestCase {
    private let all = Set(QuizTopic.allCases)

    private func verbs() throws -> [Verb] { try RealVerbs.load() }

    func testReturnsTheRequestedCount() throws {
        XCTAssertEqual(buildQuestions(verbs: try verbs(), topics: all, count: 12).count, 12)
    }

    func testCapsAtThePoolSize() throws {
        let taberu = try XCTUnwrap(try verbs().first { $0.dict == "たべる" })
        XCTAssertEqual(buildQuestions(verbs: [taberu], topics: [.basic], count: 100).count, 9)
        XCTAssertEqual(buildQuestions(verbs: [taberu], topics: all, count: 100).count, 48)
    }

    func testOnlyTheChosenTopicsAreAsked() throws {
        for question in buildQuestions(verbs: try verbs(), topics: [.potential, .nDesu], count: 60) {
            XCTAssertTrue([QuizTopic.potential, .nDesu].contains(question.form.topic))
        }
    }

    func testAruHasNoPotentialQuestions() throws {
        let aru = try XCTUnwrap(try verbs().first { $0.dict == "ある" })
        XCTAssertTrue(buildQuestions(verbs: [aru], topics: [.potential], count: 10).isEmpty)
        let questions = buildQuestions(verbs: [aru], topics: all, count: 100)
        XCTAssertEqual(questions.count, 24)
        XCTAssertFalse(questions.contains { $0.form.topic == .potential })
    }

    func testConjugateQuestionsAskForTheFormsString() throws {
        for question in buildQuestions(verbs: try verbs(), topics: all, count: 60, kinds: [.conjugate]) {
            XCTAssertEqual(question.kind, .conjugate)
            XCTAssertEqual(question.correct, question.form.value(in: question.verb.forms))
            XCTAssertEqual(question.formString, question.correct)
            XCTAssertTrue(question.choices.contains(question.correct))
        }
    }

    func testIdentifyQuestionsAskForTheFormsLabel() throws {
        let sameVerbLabels: (Verb, Set<QuizTopic>) -> Set<String> = { verb, topics in
            Set(QuizForm.available(in: verb.forms, topics: topics).map(\.form.label))
        }
        for question in buildQuestions(verbs: try verbs(), topics: all, count: 60, kinds: [.identify]) {
            XCTAssertEqual(question.kind, .identify)
            XCTAssertEqual(question.correct, question.form.label)
            XCTAssertEqual(question.formString, question.form.value(in: question.verb.forms))
            // every choice is a label of this verb's own forms
            XCTAssertTrue(Set(question.choices).isSubset(of: sameVerbLabels(question.verb, all)))
        }
    }

    func testChoicesAreDistinctContainTheAnswerOnceAndAreTwoToFour() throws {
        for kinds in [[QuizQuestionKind.conjugate], [.identify]] {
            for question in buildQuestions(verbs: try verbs(), topics: all, count: 200, kinds: kinds) {
                XCTAssertEqual(Set(question.choices).count, question.choices.count)
                XCTAssertEqual(question.choices.filter { $0 == question.correct }.count, 1)
                XCTAssertTrue((2...4).contains(question.choices.count), "\(question.choices)")
            }
        }
    }

    func testIdentifyHasExactlyOneRightAnswerPerString() throws {
        for verb in try verbs() {
            let strings = QuizForm.available(in: verb.forms, topics: all).map(\.value)
            XCTAssertEqual(Set(strings).count, strings.count, "\(verb.dict) has two forms with the same string")
        }
    }

    func testBothKindsAppearByDefault() throws {
        let kinds = Set(buildQuestions(verbs: try verbs(), topics: all, count: 100).map(\.kind))
        XCTAssertEqual(kinds, [.conjugate, .identify])
    }

    func testBasicConjugateKeepsTheOldBehaviour() throws {
        // Distractors are the verb's other basic forms first, never the answer itself.
        let questions = buildQuestions(verbs: try verbs(), topics: [.basic], count: 100, kinds: [.conjugate])
        XCTAssertEqual(questions.count, 25 * 9)
        for question in questions {
            XCTAssertEqual(question.choices.count, 4)
            XCTAssertEqual(question.form.topic, .basic)
        }
    }
}
```

In `Packages/VerbKit/Tests/VerbKitTests/QuizViewModelTests.swift`, change only the last line of the `makeQuestion` helper from
`return QuizQuestion(verb: verb, form: .masuPos, correct: correct, choices: choices)` to:

```swift
        let form = QuizForm.all.first { $0.id == "masu_pos" }!
        return QuizQuestion(verb: verb, form: form, kind: .conjugate, formString: correct, correct: correct, choices: choices)
```

And add this test to the same file (inside the class):

```swift
    func testResultsCarryTheFormLabelAndString() {
        let vm = QuizViewModel(questions: [makeQuestion(correct: "たべます", choices: ["たべます", "のみます"])])
        vm.choose("たべます")
        XCTAssertEqual(vm.results[0].formLabel, "Polite")
        XCTAssertEqual(vm.results[0].formString, "たべます")
        XCTAssertEqual(vm.results[0].kind, .conjugate)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd Packages/VerbKit && swift test --filter Quiz`
Expected: FAIL to compile (new `buildQuestions` signature, `QuizQuestion` init).

- [ ] **Step 3: Implement**

`QuizQuestion.swift`:

```swift
public enum QuizQuestionKind: Sendable {
    /// Given a verb and a form's name, pick the conjugated string.
    case conjugate
    /// Given a conjugated string, pick the name of its form.
    case identify
}

public struct QuizQuestion: Equatable, Sendable {
    public var verb: Verb
    public var form: QuizForm
    public var kind: QuizQuestionKind
    /// The form's string for this verb, e.g. たべられました.
    public var formString: String
    /// The right choice: the string for `.conjugate`, the label for `.identify`.
    public var correct: String
    public var choices: [String]

    public init(
        verb: Verb, form: QuizForm, kind: QuizQuestionKind,
        formString: String, correct: String, choices: [String]
    ) {
        self.verb = verb
        self.form = form
        self.kind = kind
        self.formString = formString
        self.correct = correct
        self.choices = choices
    }
}
```

`QuizResult.swift`:

```swift
public struct QuizResult: Equatable, Sendable {
    public var verb: String
    public var formLabel: String
    public var formString: String
    public var kind: QuizQuestionKind
    public var correct: String
    public var chosen: String
    public var ok: Bool

    public init(
        verb: String, formLabel: String, formString: String, kind: QuizQuestionKind,
        correct: String, chosen: String, ok: Bool
    ) {
        self.verb = verb
        self.formLabel = formLabel
        self.formString = formString
        self.kind = kind
        self.correct = correct
        self.chosen = chosen
        self.ok = ok
    }
}
```

`QuizViewModel.swift`: replace the `results.append(...)` line in `choose` with:

```swift
        results.append(QuizResult(
            verb: question.verb.dict, formLabel: question.form.label, formString: question.formString,
            kind: question.kind, correct: question.correct, chosen: choice, ok: ok
        ))
```

`QuizGenerator.swift` (whole file):

```swift
/// Builds up to `count` questions from the (verb, form) pairs the verbs have in
/// `topics`. Each is a conjugate or an identify question, drawn from `kinds`.
///
/// - Conjugate: the choices are conjugated strings. Distractors are the same verb's
///   other forms in the topics first, then the same form of other verbs.
/// - Identify: the choices are form labels. Distractors are labels of the same
///   verb's other forms in the topics.
///
/// A pool entry is skipped when its string equals another form's string for the same
/// verb (it would have two right answers), and a question that cannot get at least
/// two choices is skipped rather than shown with one button.
public func buildQuestions(
    verbs: [Verb],
    topics: Set<QuizTopic>,
    count: Int,
    kinds: [QuizQuestionKind] = [.conjugate, .identify]
) -> [QuizQuestion] {
    guard count > 0, !kinds.isEmpty else { return [] }

    struct PoolEntry {
        let verb: Verb
        let form: QuizForm
        let value: String
    }

    var pool: [PoolEntry] = []
    for verb in verbs {
        let everyString = QuizForm.available(in: verb.forms, topics: Set(QuizTopic.allCases)).map(\.value)
        for (form, value) in QuizForm.available(in: verb.forms, topics: topics)
        where everyString.filter({ $0 == value }).count == 1 {
            pool.append(PoolEntry(verb: verb, form: form, value: value))
        }
    }

    func pick(_ candidates: [String]) -> [String] {
        var seen = Set<String>()
        return Array(candidates.shuffled().filter { seen.insert($0).inserted }.prefix(3))
    }

    var questions: [QuizQuestion] = []
    for entry in pool.shuffled() {
        guard questions.count < count else { break }
        let sameVerb = QuizForm.available(in: entry.verb.forms, topics: topics)
            .filter { $0.form != entry.form }
        let kind = kinds.randomElement()!

        let correct: String
        let distractors: [String]
        switch kind {
        case .conjugate:
            correct = entry.value
            let sameVerbStrings = sameVerb.map(\.value).filter { $0 != correct }
            let otherVerbStrings = verbs
                .filter { $0.dict != entry.verb.dict }
                .compactMap { entry.form.value(in: $0.forms) }
                .filter { $0 != correct }
            // Same verb's forms first, as before; shuffle within each group.
            var seen = Set<String>()
            distractors = Array(
                (sameVerbStrings.shuffled() + otherVerbStrings.shuffled())
                    .filter { seen.insert($0).inserted }
                    .prefix(3)
            )
        case .identify:
            correct = entry.form.label
            distractors = pick(sameVerb.map(\.form.label).filter { $0 != correct })
        }

        guard !distractors.isEmpty else { continue }
        questions.append(QuizQuestion(
            verb: entry.verb, form: entry.form, kind: kind, formString: entry.value,
            correct: correct, choices: ([correct] + distractors).shuffled()
        ))
    }
    return questions
}
```

(`pick` is used by the identify branch only; leave it as written.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd Packages/VerbKit && swift test`
Expected: all tests pass. If `testBasicConjugateKeepsTheOldBehaviour` shows a verb with fewer than four choices, the data changed; investigate rather than weakening the test.

- [ ] **Step 5: Commit**

```bash
git add Packages/VerbKit
git commit -m "Build quiz questions from the forms catalogue: conjugate and identify"
```

---

### Task 3: The app

**Files:**
- Create: `App/QuizTopicSheet.swift`
- Modify: `App/RootView.swift`
- Modify: `App/QuizQuestionView.swift`
- Modify: `App/QuizResultsView.swift`
- Delete: `App/FormLabels.swift`

**Interfaces:**
- Consumes (Tasks 1 and 2): `QuizTopic`, `QuizTopic.choices(for:)`, `QuizTopicChoice`, `QuizQuestion` (`kind`, `form.label`, `formString`, `correct`, `choices`), `QuizResult` (`formLabel`, `formString`, `kind`, `correct`, `chosen`, `ok`), `buildQuestions(verbs:topics:count:kinds:)`.
- Produces: the finished feature.

- [ ] **Step 1: Delete the old labels and write the topic sheet**

```bash
git rm App/FormLabels.swift
```

`App/QuizTopicSheet.swift`:

```swift
import SwiftUI
import VerbKit

/// Asks what to practise before a quiz starts. Rows are the topics the verbs in
/// play have forms in, plus Everything.
struct QuizTopicSheet: View {
    let verbs: [Verb]
    var onStart: ([Verb], Set<QuizTopic>) -> Void
    var onCancel: () -> Void

    private enum Choice: Hashable {
        case everything
        case topic(QuizTopic)
    }

    @State private var choice: Choice = .everything

    private var choices: [QuizTopicChoice] { QuizTopic.choices(for: verbs) }

    private var selectedTopics: Set<QuizTopic> {
        switch choice {
        case .everything: return Set(choices.map(\.topic))
        case .topic(let topic): return [topic]
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Practise") {
                    ForEach(choices, id: \.topic) { item in
                        row(title: item.topic.title, count: item.count, choice: .topic(item.topic))
                    }
                    row(title: "Everything", count: choices.reduce(0) { $0 + $1.count }, choice: .everything)
                }
            }
            .navigationTitle("Quiz")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { onStart(verbs, selectedTopics) }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func row(title: String, count: Int, choice value: Choice) -> some View {
        Button {
            choice = value
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text("\(count) forms").foregroundStyle(.secondary)
                Image(systemName: choice == value ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(choice == value ? Color.accentColor : Color.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Wire the sheet into `RootView`**

In `App/RootView.swift`:

Add state next to `quizQuestions`:

```swift
    @State private var topicSheetVerbs: [Verb]?
    @State private var pendingQuestions: [QuizQuestion]?
```

Change the two quiz entry points:

```swift
                onRandomQuiz: { topicSheetVerbs = verbStore.verbs },
```
```swift
                    onQuiz: { topicSheetVerbs = [selection] }
```

Add this sheet right after the `.sheet(isPresented: $showingSettings) { ... }` block. The quiz is presented from `onDismiss`, so the full-screen cover never races the sheet that is closing:

```swift
        .sheet(isPresented: topicSheetBinding, onDismiss: {
            if let pendingQuestions {
                quizQuestions = pendingQuestions
                self.pendingQuestions = nil
            }
        }) {
            if let topicSheetVerbs {
                QuizTopicSheet(
                    verbs: topicSheetVerbs,
                    onStart: { verbs, topics in
                        let questions = buildQuestions(verbs: verbs, topics: topics, count: quizQuestionCount)
                        pendingQuestions = questions.isEmpty ? nil : questions
                        self.topicSheetVerbs = nil
                    },
                    onCancel: { topicSheetVerbs = nil }
                )
            }
        }
```

And add next to `quizPresentationBinding`:

```swift
    private var topicSheetBinding: Binding<Bool> {
        Binding(
            get: { topicSheetVerbs != nil },
            set: { isPresented in if !isPresented { topicSheetVerbs = nil } }
        )
    }
```

- [ ] **Step 3: Teach the question screen the two kinds**

In `App/QuizQuestionView.swift` replace `promptCard` with:

```swift
    private var promptCard: some View {
        VStack(spacing: 8) {
            switch question.kind {
            case .conjugate:
                Text(.init("What is the **\(question.form.label)** form of…"))
                    .font(.caption)
                    .multilineTextAlignment(.center)
                verbBlock
            case .identify:
                Text("Which form is")
                    .font(.caption)
                Text(question.formString)
                    .font(.system(size: 34, weight: .heavy))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("\(question.verb.dict) · \(question.verb.meaning)")
                    .italic()
                    .foregroundStyle(.secondary)
            }
            Text("⏱ \(viewModel.timeLeft)s")
                .font(.headline)
                .foregroundStyle(timerColor)
        }
        .padding()
        .glassEffect(in: RoundedRectangle(cornerRadius: 20))
    }

    private var verbBlock: some View {
        VStack(spacing: 8) {
            Text(question.verb.dict)
                .font(.system(size: 36, weight: .heavy))
            if let kanji = question.verb.kanji {
                JapaneseText(kanji).font(.title3).foregroundStyle(.secondary)
            }
            Text(question.verb.meaning)
                .italic()
                .foregroundStyle(.secondary)
        }
    }
```

In `choiceButton`, make long labels wrap: replace `Text(choice)` with

```swift
                Text(choice)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                    .lineLimit(3)
```

- [ ] **Step 4: Results rows use the label and string**

In `App/QuizResultsView.swift` replace the first `Text` of `resultRow`'s `VStack` (the one using `formLabels`) with:

```swift
                Text("\(result.verb) — \(result.formLabel)")
                    .font(.subheadline.weight(.semibold))
                if result.kind == .identify {
                    Text(result.formString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
```

- [ ] **Step 5: Build, test, and check on screen**

```bash
xcodegen generate
cd Packages/VerbKit && swift test && cd ../..
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error|BUILD"
```

Expected: tests pass, `** BUILD SUCCEEDED **`. Then in the iOS Simulator (use a unique bundle id for the check build so a stale install cannot mask the result): from Random Quiz and from Test this verb on たべる and on ある, run each topic and Everything, and confirm: the sheet lists only topics the verb has with their form counts (ある has no Potential); both question kinds appear; long labels (`Potential · polite · past · negative`, `ている · polite · past · negative`) wrap without clipping; the wrong-answer feedback and the results screen show the label, and the string for identify questions; Cancel closes the sheet without starting a quiz; Start opens the quiz without a flicker.

- [ ] **Step 6: Commit**

```bash
git add App JPVerbConjugation.xcodeproj project.yml
git commit -m "Add the quiz topic sheet and the two question kinds to the app"
```
