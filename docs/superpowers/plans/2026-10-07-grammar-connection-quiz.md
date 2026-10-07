# Grammar Connection Quiz (milestone 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A connection quiz: the learner sees a word and a pattern's ending (しずか + ので) and picks the joined form (しずかなので). A wrong answer names the building block that was needed.

**Architecture:** VerbKit builds `ConnectionQuestion`s from grammar rules that have slots and an ending (`then`). It uses the existing `AttachmentRule.build` for the answer and the word's other blocks and classic traps for distractors. A small `ConnectionQuizModel` runs the quiz and records each answer in quiz history under a new `QuizQuestionKind.connect`. The app shows it on its own screen, which shares the answer button with the verb quiz. It starts from a lesson card ("Practise this pattern") or from the quiz topic sheet ("Connections").

**Tech Stack:** Swift 6, SwiftUI (iOS 26, Liquid Glass), XCTest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-06-grammar-building-blocks-design.md` (section "Connection quiz (milestone 2)" and VerbKit "Milestone 2").

## Global Constraints

- Commit only after `cd Packages/VerbKit && swift test` exits 0. App changes must also build: `xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination "generic/platform=iOS Simulator" build -quiet`.
- After adding a file under `App/`, run `./scripts/generate-project.sh` so XcodeGen includes it.
- No `data/` changes in this plan, so no re-signing is needed.
- iPad and macOS checks stay parked. The macOS branch must still compile, so use `#if os(iOS)` fullScreenCover / `#else` sheet as `RootView` does.
- Commit trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Deviation from the spec, on purpose: the learner **picks** from up to four choices and does not type. The spec allows "types or picks", and picking matches the existing quiz. So no kana normalisation is needed.

## File map

- Create `Packages/VerbKit/Sources/VerbKit/Grammar/ConnectionQuestion.swift`: `ConnectionCue`, `ConnectionQuestion`, `GrammarPoint.hasConnections` and `buildConnectionQuestions`.
- Create `Packages/VerbKit/Sources/VerbKit/Quiz/ConnectionQuizModel.swift`: runs a connection quiz and records attempts.
- Modify `Packages/VerbKit/Sources/VerbKit/Quiz/QuizQuestion.swift`: add `QuizQuestionKind.connect`.
- Modify `Packages/VerbKit/Sources/VerbKit/Quiz/QuizGenerator.swift`: never build `.connect` verb questions.
- Modify `Packages/VerbKit/Sources/VerbKit/Quiz/QuizProgress.swift`: connection attempts count toward totals and streaks, but not toward weak spots.
- Tests: create `ConnectionQuestionTests.swift` and `ConnectionQuizModelTests.swift`; modify `RealGrammarDataTests.swift`, `QuizProgressTests.swift` and `QuizGeneratorTests.swift`.
- Create `App/QuizChoiceButton.swift`: the answer button, extracted from `QuizQuestionView`.
- Modify `App/QuizQuestionView.swift` to use it.
- Create `App/Grammar/ConnectionQuizView.swift`: the question screen and results.
- Modify `App/GrammarDetailView.swift` (the "Practise this pattern" button), `App/QuizTopicSheet.swift` (the "Connections" row) and `App/RootView.swift` (wiring).
- Modify the spec's "As built" notes.

---

### Task 1: Connection questions (VerbKit)

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Grammar/ConnectionQuestion.swift`
- Create: `Packages/VerbKit/Tests/VerbKitTests/ConnectionQuestionTests.swift`
- Modify: `Packages/VerbKit/Tests/VerbKitTests/RealGrammarDataTests.swift` (append one test)

**Interfaces:**
- Consumes: `AttachmentRule.build(_:slot:)`, `SlotSource.form(for:daToNa:)`, `GrammarSlot`, `WordClass`, `Verb`, `Word`, `GrammarPoint`.
- Produces:
  - `public struct ConnectionCue: Equatable, Sendable`, with `past: Bool?`, `negative: Bool?`, `init(past:negative:)`, `init(for: GrammarSlot, among: Set<GrammarSlot>)` and `label: String?`.
  - `public struct ConnectionQuestion: Equatable, Sendable`, with fields `grammarID`, `grammarTitle`, `wordClass`, `word`, `kanji`, `meaning`, `ending`, `slot`, `daToNa`, `cue`, `correct` and `choices: [String]` (var). It also has `explanation: String` and `attemptFormID: String`, plus a public memberwise init in that field order.
  - `GrammarPoint.hasConnections: Bool`.
  - `public func buildConnectionQuestions(points: [GrammarPoint], verbs: [Verb], words: [Word], count: Int) -> [ConnectionQuestion]`.

- [ ] **Step 1: Write the failing tests**

`Packages/VerbKit/Tests/VerbKitTests/ConnectionQuestionTests.swift`:

```swift
import XCTest
@testable import VerbKit

final class ConnectionQuestionTests: XCTestCase {
    private func word(_ cls: WordClass, _ dict: String, _ forms: [FormID: String]) -> Word {
        Word(wordClass: cls, dict: dict, meaning: "m", description: "", forms: Conjugations(forms))
    }

    private var shizuka: Word {
        word(.naAdjective, "しずか", [
            "short_pos": "しずかだ", "short_neg": "しずかじゃない", "short_past": "しずかだった",
            "short_past_neg": "しずかじゃなかった", "stem": "しずか", "te": "しずかで",
        ])
    }

    private var takai: Word {
        word(.iAdjective, "たかい", [
            "short_pos": "たかい", "short_neg": "たかくない", "short_past": "たかかった",
            "short_past_neg": "たかくなかった", "stem": "たか", "te": "たかくて",
        ])
    }

    private func verb(_ dict: String, _ stem: String, te: String, neg: String, past: String, pastNeg: String) -> Verb {
        let forms = VerbForms(
            masuPos: stem + "ます", masuNeg: stem + "ません", masuPast: stem + "ました", masuPastNeg: stem + "ませんでした",
            te: te, shortPos: dict, shortNeg: neg, shortPast: past, shortPastNeg: pastNeg
        )
        return Verb(type: .ru, label: "Ru-verb", dict: dict, kanji: nil, meaning: "m",
                    description: "", forms: forms, examples: [])
    }

    private var taberu: Verb { verb("たべる", "たべ", te: "たべて", neg: "たべない", past: "たべた", pastNeg: "たべなかった") }
    private var neru: Verb { verb("ねる", "ね", te: "ねて", neg: "ねない", past: "ねた", pastNeg: "ねなかった") }

    private func point(_ id: String, _ rules: [AttachmentRule]) -> GrammarPoint {
        GrammarPoint(id: id, title: id, summary: "", usages: [], attachment: rules,
                     conjugations: [], pitfalls: [], related: [])
    }

    private let allPlain: [GrammarSlot] = [.plain, .plainNeg, .plainPast, .plainPastNeg]

    private var node: GrammarPoint {
        point("node", [
            AttachmentRule(wordClass: .naAdjective, pattern: "p", example: "e", slots: allPlain, daToNa: true, then: "ので"),
            AttachmentRule(wordClass: .iAdjective, pattern: "p", example: "e", slots: allPlain, then: "ので"),
        ])
    }

    private var hou: GrammarPoint {
        point("hou-ga-ii", [
            AttachmentRule(wordClass: .verb, pattern: "p", example: "e", slots: [.plainPast], then: "ほうがいいです"),
            AttachmentRule(wordClass: .verb, pattern: "p", example: "e", slots: [.plainNeg], then: "ほうがいいです"),
        ])
    }

    func testTheCueNamesOnlyWhatTellsTheFormsApart() {
        let four = Set(allPlain)
        XCTAssertEqual(ConnectionCue(for: .plain, among: four).label, "positive · present")
        XCTAssertEqual(ConnectionCue(for: .plainPastNeg, among: four).label, "negative · past")
        XCTAssertEqual(ConnectionCue(for: .plainPast, among: [.plainPast, .plainNeg]).label, "positive",
                       "ほうがいい: which tense to use is the lesson, so the cue leaves it out")
        XCTAssertNil(ConnectionCue(for: .stem, among: [.stem]).label)
        XCTAssertNil(ConnectionCue(for: .plain, among: [.plain]).label)
    }

    func testEachSlotOfAPatternIsAskedWithItsAnswerAmongTheChoices() throws {
        let questions = buildConnectionQuestions(points: [node], verbs: [], words: [shizuka], count: 4)
        XCTAssertEqual(Set(questions.map(\.slot)), Set(allPlain))
        let wrongPool: Set<String> = [
            "しずかなので", "しずかだので", "しずかじゃないので", "しずかだったので",
            "しずかじゃなかったので", "しずかので", "しずかでので",
        ]
        for question in questions {
            XCTAssertTrue(question.choices.contains(question.correct))
            XCTAssertEqual(Set(question.choices).count, question.choices.count, "no duplicate choices")
            XCTAssertTrue((2...4).contains(question.choices.count))
            XCTAssertTrue(Set(question.choices).isSubset(of: wrongPool), "\(question.choices)")
        }
        let plain = try XCTUnwrap(questions.first { $0.slot == .plain })
        XCTAssertEqual(plain.correct, "しずかなので")
        XCTAssertEqual(plain.cue.label, "positive · present")
        XCTAssertEqual(plain.explanation, "な-adjectives take the plain form with だ → な before ので: しずかなので")
        XCTAssertEqual(plain.attemptFormID, "connect:node:plain")
        XCTAssertEqual(plain.grammarTitle, "node")
        let past = try XCTUnwrap(questions.first { $0.slot == .plainPast })
        XCTAssertEqual(past.correct, "しずかだったので", "the な switch touches only the plain slot")
    }

    func testAPatternWithFewSlotsFillsTheQuizWithOtherWordsButNeverRepeatsAnAnswer() throws {
        let questions = buildConnectionQuestions(points: [hou], verbs: [taberu, neru], words: [], count: 10)
        XCTAssertEqual(Set(questions.map(\.correct)),
                       ["たべたほうがいいです", "たべないほうがいいです", "ねたほうがいいです", "ねないほうがいいです"])
        XCTAssertEqual(questions.count, 4)
        let past = try XCTUnwrap(questions.first { $0.correct == "たべたほうがいいです" })
        XCTAssertEqual(past.cue.label, "positive")
        XCTAssertEqual(past.explanation, "Verbs take the plain past (た) form before ほうがいいです: たべたほうがいいです")
        XCTAssertTrue(Set(past.choices).isSubset(of: [
            "たべたほうがいいです", "たべないほうがいいです", "たべるほうがいいです",
            "たべなかったほうがいいです", "たべてほうがいいです", "たべほうがいいです",
        ]), "\(past.choices)")
    }

    func testAStemPatternHasNoCueAndUsesTheWordsOtherBlocksAsTraps() throws {
        let sugiru = point("sugiru", [
            AttachmentRule(wordClass: .iAdjective, pattern: "p", example: "e", slots: [.stem], then: "すぎる"),
        ])
        let question = try XCTUnwrap(buildConnectionQuestions(points: [sugiru], verbs: [], words: [takai], count: 1).first)
        XCTAssertEqual(question.correct, "たかすぎる")
        XCTAssertNil(question.cue.label)
        XCTAssertEqual(question.choices.count, 4)
        XCTAssertTrue(Set(question.choices).isSubset(of: [
            "たかすぎる", "たかいすぎる", "たかくないすぎる", "たかかったすぎる", "たかくなかったすぎる", "たかくてすぎる",
        ]))
        XCTAssertEqual(question.explanation, "い-adjectives take the stem before すぎる: たかすぎる")
    }

    func testNothingIsAskedWithoutAnEndingOrWordsOfTheRulesClass() {
        let tagOnly = point("teiru", [AttachmentRule(wordClass: .verb, pattern: "p", example: "e", slots: [.te])])
        XCTAssertFalse(tagOnly.hasConnections)
        XCTAssertTrue(node.hasConnections)
        XCTAssertTrue(buildConnectionQuestions(points: [tagOnly], verbs: [taberu], words: [], count: 5).isEmpty)
        XCTAssertTrue(buildConnectionQuestions(points: [node], verbs: [taberu], words: [], count: 5).isEmpty,
                      "no adjectives to ask about")
        XCTAssertTrue(buildConnectionQuestions(points: [node], verbs: [], words: [takai], count: 0).isEmpty)
    }
}
```

Append this test to `RealGrammarDataTests` (it has `loadGrammar()`, `loadVerbs()` and `loadWords()`):

```swift
    /// Every lesson with an ending yields a full connection quiz from the real verbs and
    /// words, each question with its answer among distinct choices.
    func testConnectionQuestionsBuildFromTheRealData() throws {
        let points = try loadGrammar().filter(\.hasConnections)
        XCTAssertEqual(Set(points.map(\.id)), ["n-desu", "sugiru", "node", "hou-ga-ii"])
        let verbs = try loadVerbs()
        let words = try loadWords()
        for point in points {
            let questions = buildConnectionQuestions(points: [point], verbs: verbs, words: words, count: 20)
            XCTAssertEqual(questions.count, 20, point.id)
            for question in questions {
                XCTAssertTrue(question.choices.contains(question.correct), "\(point.id) \(question.correct)")
                XCTAssertGreaterThanOrEqual(question.choices.count, 2)
                XCTAssertEqual(Set(question.choices).count, question.choices.count)
            }
        }
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd Packages/VerbKit && swift test --filter "ConnectionQuestionTests|RealGrammarDataTests" 2>&1 | grep -E "error:|Executed" | head`
Expected: compile errors: `cannot find 'buildConnectionQuestions' in scope`, `cannot find 'ConnectionCue' in scope`.

- [ ] **Step 3: Implement**

`Packages/VerbKit/Sources/VerbKit/Grammar/ConnectionQuestion.swift`:

```swift
import Foundation

/// Which plain form a connection prompt wants, when the pattern takes more than one:
/// "negative · past". It names only what tells the forms apart, so 〜ほうがいいです asks
/// for "positive" and leaves the た-form to the learner.
public struct ConnectionCue: Equatable, Sendable {
    /// Nil when the tense doesn't tell the candidate forms apart.
    public var past: Bool?
    /// Nil when the polarity doesn't tell the candidate forms apart.
    public var negative: Bool?

    public init(past: Bool? = nil, negative: Bool? = nil) {
        self.past = past
        self.negative = negative
    }

    /// The cue for `slot` among every slot the pattern takes for this word class and ending.
    public init(for slot: GrammarSlot, among candidates: Set<GrammarSlot>) {
        guard let shape = slot.plainShape else {
            self.init()
            return
        }
        let others = candidates.subtracting([slot]).compactMap(\.plainShape)
        let polarityDiffers = others.contains { $0.negative != shape.negative }
        let tenseDiffers = others.contains { $0.negative == shape.negative && $0.past != shape.past }
        self.init(past: tenseDiffers ? shape.past : nil, negative: polarityDiffers ? shape.negative : nil)
    }

    /// "negative · past", "positive", or nil when there is nothing to tell apart.
    public var label: String? {
        let parts = [negative.map { $0 ? "negative" : "positive" }, past.map { $0 ? "past" : "present" }]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

extension GrammarSlot {
    /// Tense and polarity of a plain slot; nil for the stem and the て-form.
    var plainShape: (past: Bool, negative: Bool)? {
        switch self {
        case .plain: (false, false)
        case .plainNeg: (false, true)
        case .plainPast: (true, false)
        case .plainPastNeg: (true, true)
        case .stem, .te: nil
        }
    }
}

/// One connection question: a word and a pattern's ending, and the joined form to pick.
public struct ConnectionQuestion: Equatable, Sendable {
    public var grammarID: String
    public var grammarTitle: String
    public var wordClass: WordClass
    /// The word as the prompt shows it: its citation form (たべる, しずか).
    public var word: String
    public var kanji: String?
    public var meaning: String
    /// What follows the block (ので, すぎる).
    public var ending: String
    public var slot: GrammarSlot
    public var daToNa: Bool
    public var cue: ConnectionCue
    public var correct: String
    public var choices: [String]

    public init(
        grammarID: String, grammarTitle: String, wordClass: WordClass, word: String, kanji: String?,
        meaning: String, ending: String, slot: GrammarSlot, daToNa: Bool, cue: ConnectionCue,
        correct: String, choices: [String]
    ) {
        self.grammarID = grammarID
        self.grammarTitle = grammarTitle
        self.wordClass = wordClass
        self.word = word
        self.kanji = kanji
        self.meaning = meaning
        self.ending = ending
        self.slot = slot
        self.daToNa = daToNa
        self.cue = cue
        self.correct = correct
        self.choices = choices
    }

    /// The block the pattern needed, for the feedback after an answer:
    /// "な-adjectives take the plain form with だ → な before ので: しずかなので".
    public var explanation: String {
        let who = switch wordClass {
        case .verb: "Verbs"
        case .iAdjective: "い-adjectives"
        case .naAdjective: "な-adjectives"
        case .noun: "Nouns"
        }
        let block = switch slot {
        case .plain: daToNa ? "the plain form with だ → な" : "the plain form"
        case .plainNeg: "the plain negative (ない) form"
        case .plainPast: "the plain past (た) form"
        case .plainPastNeg: "the plain past negative (なかった) form"
        case .stem: "the stem"
        case .te: "the て-form"
        }
        return "\(who) take \(block) before \(ending): \(correct)"
    }

    /// The form id quiz history records the answer under: one per pattern and slot.
    public var attemptFormID: String { "connect:\(grammarID):\(slot.rawValue)" }
}

public extension GrammarPoint {
    /// True when some rule names its slots and an ending, so the lesson can be practised.
    var hasConnections: Bool {
        attachment.contains { $0.then != nil && !$0.slots.isEmpty }
    }
}

/// Up to `count` connection questions for the rules of `points` that have slots and an
/// ending. Each (rule, slot) is paired with the next verb or word of the rule's class from
/// a shuffled deck, cycling through the pairs so a lesson with two slots still fills a quiz
/// with other words.
/// No answer is asked twice. The distractors are the word's other blocks with the same
/// ending, the な form, and the dictionary form plus the ending (たかいすぎる, しずかので).
public func buildConnectionQuestions(
    points: [GrammarPoint], verbs: [Verb], words: [Word], count: Int
) -> [ConnectionQuestion] {
    guard count > 0 else { return [] }
    let sources = verbs.map(ConnectionSource.init) + words.map(ConnectionSource.init)
    let byClass = Dictionary(grouping: sources, by: \.wordClass)

    var entries: [ConnectionEntry] = []
    for point in points {
        let rules = point.attachment.filter { $0.then != nil }
        for rule in rules where byClass[rule.wordClass] != nil {
            let candidates = Set(rules.filter { $0.wordClass == rule.wordClass && $0.then == rule.then }.flatMap(\.slots))
            for slot in rule.slots {
                entries.append(ConnectionEntry(point: point, rule: rule, slot: slot, candidates: candidates))
            }
        }
    }
    guard !entries.isEmpty else { return [] }

    var questions: [ConnectionQuestion] = []
    var asked = Set<String>()
    var round: [ConnectionEntry] = []
    // Words are dealt from a shuffled deck per class, so every word comes up before any repeats.
    var decks: [WordClass: [ConnectionSource]] = [:]
    // Bounded: a small pool of words can run out of new answers before `count`.
    for _ in 0..<(count * 4 + entries.count) {
        guard questions.count < count else { break }
        if round.isEmpty { round = entries.shuffled() }
        let entry = round.removeLast()
        let wordClass = entry.rule.wordClass
        if decks[wordClass, default: []].isEmpty { decks[wordClass] = byClass[wordClass]?.shuffled() ?? [] }
        guard let source = decks[wordClass]?.popLast(),
              let question = makeConnectionQuestion(entry, source),
              asked.insert(question.correct).inserted else { continue }
        questions.append(question)
    }
    return questions
}

private struct ConnectionEntry {
    let point: GrammarPoint
    let rule: AttachmentRule
    let slot: GrammarSlot
    /// Every slot the lesson takes for this class and ending, for the cue.
    let candidates: Set<GrammarSlot>
}

/// A verb or a word, with what the prompt shows.
private struct ConnectionSource {
    let slots: SlotSource
    let wordClass: WordClass
    let kanji: String?
    let meaning: String

    init(_ verb: Verb) {
        slots = verb
        wordClass = .verb
        kanji = verb.kanji
        meaning = verb.meaning
    }

    init(_ word: Word) {
        slots = word
        wordClass = word.wordClass
        kanji = word.kanji
        meaning = word.meaning
    }
}

private func makeConnectionQuestion(_ entry: ConnectionEntry, _ source: ConnectionSource) -> ConnectionQuestion? {
    guard let then = entry.rule.then, let correct = entry.rule.build(source.slots, slot: entry.slot) else { return nil }
    var wrong = GrammarSlot.allCases.compactMap { source.slots.form(for: $0) }.map { $0 + then }
    if let na = source.slots.form(for: .plain, daToNa: true) { wrong.append(na + then) }
    wrong.append(source.slots.dict + then)
    var seen: Set<String> = [correct]
    let distractors = Array(wrong.shuffled().filter { seen.insert($0).inserted }.prefix(3))
    guard !distractors.isEmpty else { return nil }
    return ConnectionQuestion(
        grammarID: entry.point.id, grammarTitle: entry.point.title, wordClass: source.wordClass,
        word: source.slots.dict, kanji: source.kanji, meaning: source.meaning, ending: then,
        slot: entry.slot, daToNa: entry.rule.daToNa,
        cue: ConnectionCue(for: entry.slot, among: entry.candidates),
        correct: correct, choices: ([correct] + distractors).shuffled()
    )
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd Packages/VerbKit && swift test 2>&1 | grep -E "error:|failed|Executed .* tests" | tail -3`
Expected: `Executed N tests, with 0 failures`. N is the previous 657 plus 6.

- [ ] **Step 5: Commit**

```bash
git add Packages/VerbKit/Sources/VerbKit/Grammar/ConnectionQuestion.swift Packages/VerbKit/Tests/VerbKitTests/ConnectionQuestionTests.swift Packages/VerbKit/Tests/VerbKitTests/RealGrammarDataTests.swift
git commit -m "Grammar: build connection questions from slot rules

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Connection quiz model and history (VerbKit)

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Quiz/ConnectionQuizModel.swift`
- Create: `Packages/VerbKit/Tests/VerbKitTests/ConnectionQuizModelTests.swift`
- Modify: `Packages/VerbKit/Sources/VerbKit/Quiz/QuizQuestion.swift` (the enum at the top)
- Modify: `Packages/VerbKit/Sources/VerbKit/Quiz/QuizGenerator.swift` (`makeQuestion`, the `usable` filter and the `switch kind`)
- Modify: `Packages/VerbKit/Sources/VerbKit/Quiz/QuizProgress.swift` (the weakness loop at the start of `init`)
- Modify: `App/QuizQuestionView.swift` (`promptCard`'s `switch question.kind`, which must stay exhaustive)
- Test: `QuizProgressTests.swift` and `QuizGeneratorTests.swift`, appending one test each

**Interfaces:**
- Consumes: `ConnectionQuestion` (`word` and `attemptFormID`, from Task 1); `QuizAttempt`.
- Produces:
  - `QuizQuestionKind.connect`.
  - `public final class ConnectionQuizModel` (`@Observable`), with `init(questions:recorder:now:)`, `questions`, `index`, `selected`, `score`, `finished`, `currentQuestion`, `isAnswered`, `choose(_:)`, `advance()` and `missedQuestions`.

- [ ] **Step 1: Write the failing tests**

`Packages/VerbKit/Tests/VerbKitTests/ConnectionQuizModelTests.swift`:

```swift
import XCTest
@testable import VerbKit

final class ConnectionQuizModelTests: XCTestCase {
    private func question(_ word: String, _ correct: String) -> ConnectionQuestion {
        ConnectionQuestion(
            grammarID: "node", grammarTitle: "〜ので", wordClass: .naAdjective, word: word, kanji: nil,
            meaning: "m", ending: "ので", slot: .plain, daToNa: true, cue: ConnectionCue(),
            correct: correct, choices: [correct, "x"]
        )
    }

    func testAnswersScoreAreRecordedAndTheQuizFinishes() {
        var recorded: [QuizAttempt] = []
        let date = Date(timeIntervalSince1970: 0)
        let model = ConnectionQuizModel(
            questions: [question("しずか", "しずかなので"), question("あめ", "あめなので")],
            recorder: { recorded.append($0) }, now: { date }
        )
        model.choose("しずかなので")
        model.choose("x")   // ignored: already answered
        XCTAssertEqual(model.score, 1)
        model.advance()
        XCTAssertEqual(model.currentQuestion?.word, "あめ")
        model.choose("x")
        model.advance()
        XCTAssertTrue(model.finished)
        XCTAssertEqual(recorded.map(\.outcome), [.correct, .wrong])
        XCTAssertEqual(recorded.map(\.kind), [.connect, .connect])
        XCTAssertEqual(recorded.first?.verb, "しずか")
        XCTAssertEqual(recorded.first?.formID, "connect:node:plain")
        XCTAssertEqual(recorded.first?.date, date)
        XCTAssertEqual(model.missedQuestions.map(\.word), ["あめ"])
    }

    func testAdvanceWaitsForAnAnswer() {
        let model = ConnectionQuizModel(questions: [question("しずか", "しずかなので")])
        model.advance()
        XCTAssertEqual(model.index, 0)
        XCTAssertFalse(model.finished)
    }
}
```

Append to `QuizProgressTests` (it has `now` and `progress(_:)`):

```swift
    /// Connection answers keep the streak and totals but are not verb weak spots.
    func testConnectionAnswersCountTowardTotalsButNotWeakSpots() {
        let connect = QuizAttempt(verb: "しずか", formID: "connect:node:plain", kind: .connect, outcome: .wrong, date: now)
        let p = progress([connect])
        XCTAssertEqual(p.totalAnswered, 1)
        XCTAssertEqual(p.currentStreak, 1)
        XCTAssertTrue(p.weakPairs.isEmpty)
        XCTAssertTrue(p.weakestVerbs.isEmpty)
        XCTAssertTrue(p.weakestForms.isEmpty)
    }
```

Append to `QuizGeneratorTests` (it has `verbs()`):

```swift
    func testConnectIsNeverAVerbQuestion() throws {
        let all = Set(QuizTopic.allCases)
        XCTAssertTrue(buildQuestions(verbs: try verbs(), topics: all, count: 10, kinds: [.connect]).isEmpty)
        let mixed = buildQuestions(verbs: try verbs(), topics: all, count: 30, kinds: QuizQuestionKind.allCases)
        XCTAssertFalse(mixed.isEmpty)
        XCTAssertFalse(mixed.contains { $0.kind == .connect })
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd Packages/VerbKit && swift test 2>&1 | grep -E "error:" | head -5`
Expected: `type 'QuizQuestionKind' has no member 'connect'`, and `cannot find 'ConnectionQuizModel'`.

- [ ] **Step 3: Implement**

In `QuizQuestion.swift`, add the case after `fillIn`:

```swift
    /// A connection question (しずか + ので → しずかなので). Only recorded in quiz history:
    /// connection questions have their own screen, and `buildQuestions` never makes one.
    case connect
```

In `QuizGenerator.swift` `makeQuestion`, extend the `usable` filter's switch:

```swift
        case .connect: return false
```

and the `switch kind` that sets `correct` and `distractors`, before `}`:

```swift
    case .connect:
        return nil
```

In `QuizProgress.swift`, change the weakness loop:

```swift
        // Connection answers count toward streaks and totals below, but weak spots are
        // verb and form pairs, which a connection (a word and a pattern) is not.
        for (i, a) in attempts.enumerated() where a.kind != .connect {
```

In `App/QuizQuestionView.swift` `promptCard`, add a case so the switch stays exhaustive:

```swift
            case .connect:
                // Never shown here: connection questions have their own screen.
                EmptyView()
```

`Packages/VerbKit/Sources/VerbKit/Quiz/ConnectionQuizModel.swift`:

```swift
import Foundation
import Observation

/// Runs a connection quiz one question at a time. It has no timer, because building the
/// form takes thought. Each answer goes into quiz history as a `.connect` attempt: the
/// word in `verb` and the pattern and slot in `formID`.
@Observable
public final class ConnectionQuizModel {
    public let questions: [ConnectionQuestion]
    public private(set) var index = 0
    public private(set) var selected: String?
    public private(set) var score = 0
    public private(set) var finished = false
    /// Whether each answered question was right, in order.
    private var outcomes: [Bool] = []

    private let recorder: ((QuizAttempt) -> Void)?
    private let now: () -> Date

    public init(
        questions: [ConnectionQuestion],
        recorder: ((QuizAttempt) -> Void)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.questions = questions
        self.recorder = recorder
        self.now = now
    }

    public var currentQuestion: ConnectionQuestion? {
        questions.indices.contains(index) ? questions[index] : nil
    }

    public var isAnswered: Bool { selected != nil }

    public func choose(_ choice: String) {
        guard !isAnswered, let question = currentQuestion else { return }
        selected = choice
        let ok = choice == question.correct
        if ok { score += 1 }
        outcomes.append(ok)
        recorder?(QuizAttempt(
            verb: question.word, formID: question.attemptFormID, kind: .connect,
            outcome: ok ? .correct : .wrong, date: now()
        ))
    }

    public func advance() {
        guard isAnswered else { return }
        if index + 1 >= questions.count {
            finished = true
        } else {
            index += 1
            selected = nil
        }
    }

    /// The questions answered wrongly, with the choices reshuffled, for "Practise missed".
    public var missedQuestions: [ConnectionQuestion] {
        zip(questions, outcomes).filter { !$0.1 }.map { question, _ in
            var again = question
            again.choices.shuffle()
            return again
        }
    }
}
```

- [ ] **Step 4: Run the tests and build the app**

Run: `cd Packages/VerbKit && swift test 2>&1 | grep -E "error:|failed|Executed .* tests" | tail -3`
Expected: 0 failures.
Run: `xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination "generic/platform=iOS Simulator" build -quiet 2>&1 | grep -E "error:" | head`
Expected: no `error:` lines. An `error: the following command failed with exit code 0 but produced no further output` line is a known false alarm from this project; check that the app bundle was built.

- [ ] **Step 5: Commit**

```bash
git add Packages/VerbKit App/QuizQuestionView.swift
git commit -m "Quiz: connection quiz model, recorded as connect attempts

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Connection quiz screen (App)

**Files:**
- Create: `App/QuizChoiceButton.swift`
- Create: `App/Grammar/ConnectionQuizView.swift`
- Modify: `App/QuizQuestionView.swift`: replace `choiceButton(_:index:)` and the colour and shape constants with `QuizChoiceButton`

**Interfaces:**
- Consumes: `ConnectionQuizModel` and `ConnectionQuestion` (Tasks 1–2), `WordClass.displayName` (from `App/GrammarDisplay.swift`) and `JapaneseText`.
- Produces:
  - `struct QuizChoiceButton: View`, with `init(choice:index:isCorrect:isSelected:isAnswered:action:)`, `static let correctColor` and `static let wrongColor`.
  - `struct ConnectionQuizView: View`, with `init(questions: [ConnectionQuestion], recorder: @escaping (QuizAttempt) -> Void, onDone: @escaping () -> Void)`.

- [ ] **Step 1: Extract the answer button**

`App/QuizChoiceButton.swift`. The body is `QuizQuestionView.choiceButton` moved as is:

```swift
import SwiftUI
import VerbKit

/// One answer of a quiz: a pastel button with a shape that turns green or red once
/// answered. Shared by the verb quiz and the connection quiz.
struct QuizChoiceButton: View {
    let choice: String
    let index: Int
    let isCorrect: Bool
    let isSelected: Bool
    let isAnswered: Bool
    let action: () -> Void

    static let correctColor = Color(red: 0.13, green: 0.55, blue: 0.32)
    static let wrongColor = Color(red: 0.78, green: 0.20, blue: 0.20)

    private static let shapeSymbols = ["triangle.fill", "diamond.fill", "circle.fill", "square.fill"]
    // Pastels from the app palette (labels are near-black, as on `accentPill`). The shapes carry
    // the identity; correct/wrong use deeper green and red so they stand out from every choice.
    private static let choiceColors: [Color] = [
        TeGroup.tte.accentColor,
        VerbType.ru.accentColor,
        VerbType.u.accentColor,
        TeGroup.ite.accentColor,
    ]

    var body: some View {
        var background = Self.choiceColors[index % Self.choiceColors.count]
        var labelColor = Color.black.opacity(0.85)
        if isAnswered {
            if isCorrect { background = Self.correctColor; labelColor = .white }
            else if isSelected { background = Self.wrongColor; labelColor = .white }
        }
        return Button(action: action) {
            HStack {
                Image(systemName: Self.shapeSymbols[index % Self.shapeSymbols.count])
                Text(choice)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                    .lineLimit(3)
                if isAnswered && isCorrect { Image(systemName: "checkmark") }
                if isAnswered && isSelected && !isCorrect { Image(systemName: "xmark") }
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .foregroundStyle(labelColor)
        }
        .buttonStyle(.glassProminent)
        .tint(background)
        .allowsHitTesting(!isAnswered)
        .opacity(isAnswered && !isCorrect && !isSelected ? 0.35 : 1)
    }
}
```

In `QuizQuestionView`:
- Delete `shapeSymbols`, `choiceColors`, `correctColor`, `wrongColor` and `choiceButton(_:index:)`.
- Replace the call in the grid with:

```swift
                        QuizChoiceButton(
                            choice: choice, index: index, isCorrect: choice == question.correct,
                            isSelected: choice == viewModel.selected, isAnswered: viewModel.isAnswered
                        ) {
                            viewModel.choose(choice)
                        }
```

- In `feedback`, replace `correctColor` and `wrongColor` with `QuizChoiceButton.correctColor` and `QuizChoiceButton.wrongColor`.

- [ ] **Step 2: Write the connection quiz screen**

`App/Grammar/ConnectionQuizView.swift`:

```swift
import SwiftUI
import VerbKit
import WidgetKit

/// The connection quiz: a word plus a pattern's ending; pick the joined form. Every answer
/// shows the building block the pattern needed. No timer: building the form takes thought.
struct ConnectionQuizView: View {
    @State private var model: ConnectionQuizModel
    @State private var confirmingQuit = false
    private let recorder: (QuizAttempt) -> Void
    var onDone: () -> Void

    init(questions: [ConnectionQuestion], recorder: @escaping (QuizAttempt) -> Void, onDone: @escaping () -> Void) {
        _model = State(initialValue: ConnectionQuizModel(questions: questions, recorder: recorder))
        self.recorder = recorder
        self.onDone = onDone
    }

    var body: some View {
        Group {
            if model.finished {
                results
            } else if let question = model.currentQuestion {
                questionScreen(question)
            }
        }
        // The widgets read quiz history, which these answers add to.
        .onDisappear { WidgetCenter.shared.reloadAllTimelines() }
        .confirmationDialog("Quit this quiz?", isPresented: $confirmingQuit, titleVisibility: .visible) {
            Button("Quit quiz", role: .destructive, action: onDone)
            Button("Keep going", role: .cancel) {}
        }
    }

    private func questionScreen(_ question: ConnectionQuestion) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                prompt(question)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(Array(question.choices.enumerated()), id: \.offset) { index, choice in
                        QuizChoiceButton(
                            choice: choice, index: index, isCorrect: choice == question.correct,
                            isSelected: choice == model.selected, isAnswered: model.isAnswered
                        ) {
                            model.choose(choice)
                        }
                    }
                }
                if model.isAnswered { feedback(question) }
            }
            .padding()
        }
        // Pinned so the button doesn't move below the fold as feedback appears.
        .safeAreaInset(edge: .bottom) {
            if model.isAnswered {
                Button(model.index + 1 >= model.questions.count ? "See Results" : "Next",
                       systemImage: "arrow.right") {
                    model.advance()
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
    }

    private var header: some View {
        HStack {
            Button {
                confirmingQuit = true
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Quit quiz")

            Text("\(model.index + 1) / \(model.questions.count)")
                .font(.headline)
            Spacer()
            Label("\(model.score)", systemImage: "star.fill")
                .accessibilityLabel("Score \(model.score)")
        }
    }

    private func prompt(_ question: ConnectionQuestion) -> some View {
        VStack(spacing: 8) {
            Text("Join them with the right building block")
                .font(.caption)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(question.word)
                Image(systemName: "plus").font(.title2).foregroundStyle(.secondary)
                Text(question.ending)
            }
            .font(.largeTitle.weight(.heavy))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            if let kanji = question.kanji {
                JapaneseText(kanji).font(.title3).foregroundStyle(.secondary)
            }
            Text("\(question.wordClass.displayName) · \(question.meaning)")
                .italic()
                .foregroundStyle(.secondary)
            if let cue = question.cue.label {
                Text(cue)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .glassEffect(in: RoundedRectangle(cornerRadius: 20))
    }

    private func feedback(_ question: ConnectionQuestion) -> some View {
        let right = model.selected == question.correct
        return VStack(alignment: .leading, spacing: 6) {
            Label(right ? "Correct!" : "Not quite", systemImage: right ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.headline)
            Text(question.explanation)
                .font(.subheadline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .glassEffect(
            .regular.tint(right ? QuizChoiceButton.correctColor : QuizChoiceButton.wrongColor),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private var results: some View {
        let missed = model.missedQuestions
        return ScrollView {
            VStack(spacing: 20) {
                Text("\(model.score) / \(model.questions.count)")
                    .font(.system(size: 56, weight: .heavy))
                Text(missed.isEmpty ? "Every block in the right place." : "Worth another look:")
                    .foregroundStyle(.secondary)
                ForEach(Array(missed.enumerated()), id: \.offset) { _, question in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(question.correct).font(.headline)
                        Text(question.explanation).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .glassEffect(in: RoundedRectangle(cornerRadius: 12))
                }
                if !missed.isEmpty {
                    Button("Practise missed", systemImage: "arrow.counterclockwise") {
                        model = ConnectionQuizModel(questions: missed, recorder: recorder)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }
                Button("Done", action: onDone)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
            }
            .padding()
        }
    }
}
```

- [ ] **Step 3: Regenerate the project and build**

Run: `./scripts/generate-project.sh && xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination "generic/platform=iOS Simulator" build -quiet 2>&1 | grep -E "error:" | head`
Expected: no real `error:` lines.
Run: `cd Packages/VerbKit && swift test 2>&1 | grep -E "Executed .* tests" | tail -1`
Expected: 0 failures.

- [ ] **Step 4: Commit**

```bash
git add App JPVerbConjugation.xcodeproj
git commit -m "Quiz: connection quiz screen, sharing the answer button

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

(If `JPVerbConjugation.xcodeproj` is git-ignored, `git add` skips it; that's fine.)

---

### Task 4: Entry points (lesson card and topic sheet) and simulator check

**Files:**
- Modify: `App/GrammarDetailView.swift`
- Modify: `App/QuizTopicSheet.swift`
- Modify: `App/RootView.swift`

**Interfaces:**
- Consumes: `buildConnectionQuestions`, `GrammarPoint.hasConnections` and `ConnectionQuizView`; the `WordsStore` and `QuizHistoryStore` environments (both injected at app level); `[Verb].visible(in: LevelSettings.load())`; the `quizQuestionCount` app-group setting.
- Produces: `QuizSelection.connections`; `QuizTopicSheet(verbs:connectionPatterns:weakSpotCount:onStart:onCancel:)`.

- [ ] **Step 1: "Practise this pattern" on the lesson card**

In `GrammarDetailView`, add the following:

```swift
    @Environment(WordsStore.self) private var wordsStore
    @Environment(QuizHistoryStore.self) private var quizHistory
    @AppStorage("quizQuestionCount", store: .appGroup) private var quizQuestionCount = 10
    @State private var connectionQuestions: [ConnectionQuestion]?
```

In `body`'s VStack, insert this between the pitfalls line and the related line:

```swift
                if point.hasConnections { practiseSection }
```

Add the section and the presentation:

```swift
    // MARK: Practise

    private var practiseSection: some View {
        Button {
            let verbs = verbStore.verbs.visible(in: LevelSettings.load())
            let questions = buildConnectionQuestions(points: [point], verbs: verbs, words: wordsStore.words, count: quizQuestionCount)
            if !questions.isEmpty { connectionQuestions = questions }
        } label: {
            Label("Practise this pattern", systemImage: "arrow.right")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
    }

    private var connectionBinding: Binding<Bool> {
        Binding(
            get: { connectionQuestions != nil },
            set: { if !$0 { connectionQuestions = nil } }
        )
    }
```

Attach this to the `ScrollView` (next to its other modifiers):

```swift
        #if os(iOS)
        .fullScreenCover(isPresented: connectionBinding) {
            if let connectionQuestions {
                ConnectionQuizView(questions: connectionQuestions, recorder: { quizHistory.record($0) },
                                   onDone: { self.connectionQuestions = nil })
            }
        }
        #else
        .sheet(isPresented: connectionBinding) {
            if let connectionQuestions {
                ConnectionQuizView(questions: connectionQuestions, recorder: { quizHistory.record($0) },
                                   onDone: { self.connectionQuestions = nil })
                    .frame(minWidth: 560, minHeight: 640)
            }
        }
        #endif
```

- [ ] **Step 2: The "Connections" row on the topic sheet**

In `QuizTopicSheet.swift`:

```swift
enum QuizSelection {
    case topics(Set<QuizTopic>)
    case weakSpots
    /// Grammar connections, built from the sheet's verbs and every word.
    case connections
}
```

Add `let connectionPatterns: Int` after `let verbs: [Verb]`. Add `case connections` to `Choice`. Then:
- `isAvailable`: `case .connections: return connectionPatterns > 0`
- `selection`: `case .connections: return .connections`

After the `Section("Practise") { … }` block, insert:

```swift
                Section {
                    row(
                        title: "Connections",
                        detail: connectionPatterns == 1 ? "1 pattern" : "\(connectionPatterns) patterns",
                        choice: .connections,
                        enabled: connectionPatterns > 0
                    )
                } footer: {
                    Text("Join verbs and adjectives to grammar patterns: しずか + ので.")
                }
```

- [ ] **Step 3: Wire RootView**

In `RootView`:
- Add `@Environment(WordsStore.self) private var wordsStore`, `@State private var connectionQuestions: [ConnectionQuestion]?` and `@State private var pendingConnections: [ConnectionQuestion]?`.
- In `open(_:)`, next to `quizQuestions = nil`, add `connectionQuestions = nil` and `pendingConnections = nil`.
- `QuizTopicSheet(...)`: pass `connectionPatterns: verbStore.grammarPoints.filter(\.hasConnections).count` after `verbs:`. Replace `onStart` with:

```swift
                    onStart: { verbs, selection in
                        if case .connections = selection {
                            let built = buildConnectionQuestions(
                                points: verbStore.grammarPoints, verbs: verbs,
                                words: wordsStore.words, count: quizQuestionCount
                            )
                            pendingConnections = built.isEmpty ? nil : built
                        } else {
                            let questions = questions(for: selection, verbs: verbs)
                            pendingQuestions = questions.isEmpty ? nil : questions
                        }
                        self.topicSheetVerbs = nil
                    },
```

- In the sheet's `onDismiss`, after the `pendingQuestions` block:

```swift
            if let pendingConnections {
                connectionQuestions = pendingConnections
                self.pendingConnections = nil
            }
```

- In `questions(for:verbs:)`, add `case .connections: return []  // started from onStart instead`.
- Add a binding next to `quizPresentationBinding`:

```swift
    private var connectionPresentationBinding: Binding<Bool> {
        Binding(
            get: { connectionQuestions != nil },
            set: { isPresented in if !isPresented { connectionQuestions = nil } }
        )
    }
```

- In both branches of the `#if os(iOS)` block that presents `QuizView`, chain a second presentation after the existing one:

```swift
        // iOS branch:
        .fullScreenCover(isPresented: connectionPresentationBinding) {
            if let connectionQuestions {
                ConnectionQuizView(questions: connectionQuestions, recorder: { quizHistory.record($0) },
                                   onDone: { self.connectionQuestions = nil })
            }
        }
        // macOS branch:
        .sheet(isPresented: connectionPresentationBinding) {
            if let connectionQuestions {
                ConnectionQuizView(questions: connectionQuestions, recorder: { quizHistory.record($0) },
                                   onDone: { self.connectionQuestions = nil })
                    .frame(minWidth: 560, minHeight: 640)
            }
        }
```

- [ ] **Step 4: Build and test**

Run: `cd Packages/VerbKit && swift test 2>&1 | grep -E "Executed .* tests" | tail -1`, then the iOS `xcodebuild` from the Global Constraints.
Expected: 0 failures, and no real `error:` lines.

- [ ] **Step 5: Check on the simulator (iPhone only)**

Install on the iPhone 17 simulator (`F8A1F047-9215-4C1F-8202-661A87975FB9`; always pass `device`) and check:
1. Grammar tab › 〜ので: a "Practise this pattern" button appears below "Watch out". Tap it: a question shows the word + ので and a cue such as "negative · past". Pick a wrong answer: it turns red and the feedback names the block ("な-adjectives take the plain form with だ → な before ので: …"). Finish: the results show the score, the missed answers and "Practise missed".
2. Grammar tab › ている: no practise button (no ending).
3. Verbs tab › Quiz: a "Connections" row shows "4 patterns". Choose it and Start: a connection quiz opens.
4. Progress (Verbs tab menu): the total grows; weak spots don't list words like しずか.

Take a screenshot of steps 1 and 3 for the PR.

- [ ] **Step 6: Commit**

```bash
git add App
git commit -m "Grammar: practise connections from a lesson or the quiz sheet

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Spec notes and PR

**Files:**
- Modify: `docs/superpowers/specs/2026-10-06-grammar-building-blocks-design.md` (section "Milestones")

- [ ] **Step 1: Mark milestone 2 done and record what was built**

Change `2. **Connection quiz.**` to `2. **Connection quiz (done 2026-10-07).**`. After the "As built (milestone 1)" list, add:

```markdown
**As built (milestone 2):**

- The learner picks from up to four choices rather than typing, matching the existing quiz.
  Distractors are the word's other blocks with the same ending, the な form, and the
  dictionary form plus the ending (しずかだので, たかいすぎる).
- When a pattern takes more than one plain form for a class, a cue says which: positive or
  negative, present or past. It names only what tells the forms apart, so 〜ほうがいいです
  asks for "positive" and the た-form stays the lesson.
- Its own screen, with no timer. Answers are recorded as `connect` attempts: they count
  toward streaks and totals but not toward weak spots, which are verb and form pairs.
- From the quiz sheet, "Connections" uses the sheet's verbs (one verb from a verb page,
  favourites when toggled) and every word. From a lesson card, it uses the visible verbs.
```

- [ ] **Step 2: Commit, push and open the PR**

```bash
git add docs/superpowers/specs/2026-10-06-grammar-building-blocks-design.md
git commit -m "Docs: grammar milestone 2 as built

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin claude/grammar-connection-quiz
gh pr create --base main --title "Grammar: connection quiz (building blocks milestone 2)" --body "<summary, the simulator screenshots, test count, and the footer: 🤖 Generated with [Claude Code](https://claude.com/claude-code)>"
```
