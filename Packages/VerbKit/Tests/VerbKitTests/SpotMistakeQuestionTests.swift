import XCTest
@testable import VerbKit

final class SpotMistakeQuestionTests: XCTestCase {
    private func mistake(
        _ id: String, wrong: String?, examples: [String] = [], source: Route = .grammar("node"),
        jlpt: JLPTLevel? = .n5, heading: String = "Heading"
    ) -> CommonMistake {
        CommonMistake(
            id: id, theme: .joining, heading: heading, explanation: "Why \(id) is wrong.",
            examples: examples.map { GrammarExample(jp: $0, en: "en") }, wrong: wrong,
            source: source, sourceTitle: "Title", jlpt: jlpt)
    }

    private func counter(_ id: String, _ written: String, _ reading: String, readings: [String: String] = [:]) -> Counter {
        var all: [String: [String]] = [:]
        for (number, base) in zip(CounterNumber.allCases, ["いち", "に", "さん", "よ", "ご", "ろく", "なな", "はち", "きゅう", "じゅう", "なん"]) {
            all[number.key] = [base + reading]
        }
        all.merge(readings.mapValues { [$0] }) { _, new in new }
        return Counter(
            id: id, counter: written, reading: reading, meaning: "m", jlpt: .n5, sound: "plain", symbol: "circle",
            readings: all, changed: [], distractors: [:], countsObjects: true, things: [], askings: [])
    }

    // MARK: Only pitfalls with a wrong form

    func testOnlyPitfallsWithAWrongFormMakeQuestions() {
        let mistakes = [
            mistake("a#0", wrong: "静かだので", examples: ["静かなので、寝ます。"]),
            mistake("b#0", wrong: nil, examples: ["いい文です。"]),
            mistake("c#0", wrong: "   ", examples: ["いい文です。"]),
            mistake("d#0", wrong: "", examples: ["いい文です。"]),
        ]
        let questions = buildSpotMistakeQuestions(mistakes: mistakes, counters: [], count: 10)
        XCTAssertEqual(questions.map(\.mistakeID), ["a#0"])
    }

    func testQuestionCarriesTheWrongFormTheExplanationAndTheLink() throws {
        let m = mistake("a#0", wrong: "静かだので", examples: ["静かなので、寝ます。"], source: .grammar("node"), heading: "な, not だ")
        let question = try XCTUnwrap(buildSpotMistakeQuestions(mistakes: [m], counters: [], count: 5).first)
        XCTAssertEqual(question.wrong, "静かだので")
        XCTAssertEqual(question.explanation, "Why a#0 is wrong.")
        XCTAssertEqual(question.heading, "な, not だ")
        XCTAssertEqual(question.source, .grammar("node"))
        XCTAssertEqual(question.sourceTitle, "Title")
    }

    // MARK: Level filtering

    func testHiddenLevelsMakeNoQuestions() {
        let mistakes = [
            mistake("a#0", wrong: "x1", examples: ["ok1。"], jlpt: .n5),
            mistake("b#0", wrong: "x2", examples: ["ok2。"], jlpt: .n3),
            mistake("c#0", wrong: "x3", examples: ["ok3。"], jlpt: nil),
        ]
        let hidden = buildSpotMistakeQuestions(
            mistakes: mistakes, counters: [], levels: LevelSettings(hidden: [.n3]), count: 10)
        XCTAssertEqual(Set(hidden.map(\.mistakeID)), ["a#0", "c#0"])
        let all = buildSpotMistakeQuestions(mistakes: mistakes, counters: [], levels: LevelSettings(), count: 10)
        XCTAssertEqual(all.count, 3)
        let none = buildSpotMistakeQuestions(
            mistakes: mistakes, counters: [], levels: LevelSettings(hidden: [.n5, .n3]), count: 10)
        XCTAssertEqual(none.map(\.mistakeID), ["c#0"], "an item without a level is always visible")
    }

    // MARK: Choices

    func testWrongAndCorrectNeverEqualAndChoicesAreUnique() {
        let m = mistake("a#0", wrong: "静かだので", examples: ["静かだので。", "静かなので。", "静かなので。", "雨なので。"])
        for _ in 0..<50 {
            guard let q = buildSpotMistakeQuestions(mistakes: [m], counters: [], count: 1).first else {
                return XCTFail("no question")
            }
            XCTAssertEqual(q.choices.filter { $0 == q.wrong }.count, 1)
            XCTAssertEqual(Set(q.choices).count, q.choices.count)
            XCTAssertTrue(q.choices.contains(q.wrong))
            XCTAssertTrue(q.corrects.allSatisfy { $0 != q.wrong })
            XCTAssertEqual(Set(q.corrects + [q.wrong]), Set(q.choices))
            XCTAssertTrue((2...3).contains(q.choices.count))
        }
    }

    func testTrailingPunctuationIsStrippedFromCorrectChoices() throws {
        let m = mistake("a#0", wrong: "静かだので", examples: ["静かなので、寝ます。", "本当ですか？"])
        let q = try XCTUnwrap(buildSpotMistakeQuestions(mistakes: [m], counters: [], count: 1).first)
        XCTAssertEqual(Set(q.corrects), ["静かなので、寝ます", "本当ですか"])
    }

    func testMultiSentenceExamplesAreNotUsedAsChoices() throws {
        let m = mistake("a#0", wrong: "x", examples: ["どうして？電車です。", "電車です。"])
        let q = try XCTUnwrap(buildSpotMistakeQuestions(mistakes: [m], counters: [], count: 1).first)
        XCTAssertEqual(q.corrects, ["電車です"])
    }

    func testAnExampleContainingTheWrongFormIsNeverShownAsCorrect() throws {
        let m = mistake("a#0", wrong: "静かだので", examples: ["静かだので、は誤りです。", "静かなので。"])
        let q = try XCTUnwrap(buildSpotMistakeQuestions(mistakes: [m], counters: [], count: 1).first)
        XCTAssertEqual(q.corrects, ["静かなので"])
    }

    func testAPitfallWithoutExamplesBorrowsFromTheSameSource() throws {
        let bare = mistake("node#0", wrong: "x", examples: [], source: .grammar("node"))
        let sibling = mistake("node#1", wrong: nil, examples: ["静かなので。"], source: .grammar("node"))
        let other = mistake("tai#0", wrong: nil, examples: ["食べたい。"], source: .grammar("tai"))
        let q = try XCTUnwrap(buildSpotMistakeQuestions(mistakes: [bare, sibling, other], counters: [], count: 5).first)
        XCTAssertEqual(q.corrects, ["静かなので"])
    }

    func testNoCorrectFormToShowMeansNoQuestion() {
        let bare = mistake("node#0", wrong: "x", examples: [], source: .grammar("node"))
        let elsewhere = mistake("tai#0", wrong: nil, examples: ["食べたい。"], source: .grammar("tai"))
        XCTAssertTrue(buildSpotMistakeQuestions(mistakes: [bare, elsewhere], counters: [], count: 5).isEmpty)
    }

    // MARK: Counters

    func testCounterReadingsAreOffsetByOtherNumbersOfTheSameCounter() throws {
        let nin = counter("nin", "人", "にん", readings: ["4": "よにん"])
        let m = mistake("counter:nin#0", wrong: "四人 よんにん", source: .counter("nin"))
        for _ in 0..<30 {
            let q = try XCTUnwrap(buildSpotMistakeQuestions(mistakes: [m], counters: [nin], count: 1).first)
            XCTAssertEqual(q.corrects.count, 2)
            XCTAssertTrue(q.corrects.allSatisfy { $0.contains("人 ") && !$0.hasPrefix("四人") && !$0.hasSuffix("なんにん") })
            XCTAssertEqual(Set(q.choices).count, 3)
        }
    }

    func testACounterPitfallOfAnUnknownCounterMakesNoQuestion() {
        let m = mistake("counter:zzz#0", wrong: "四人 よんにん", source: .counter("zzz"))
        XCTAssertTrue(buildSpotMistakeQuestions(mistakes: [m], counters: [], count: 5).isEmpty)
    }

    // MARK: Count and emptiness

    func testNothingQualifyingGivesAnEmptyResult() {
        XCTAssertTrue(buildSpotMistakeQuestions(mistakes: [], counters: [], count: 10).isEmpty)
        XCTAssertTrue(buildSpotMistakeQuestions(mistakes: [mistake("a#0", wrong: nil, examples: ["x。"])], counters: [], count: 10).isEmpty)
        XCTAssertTrue(buildSpotMistakeQuestions(mistakes: [mistake("a#0", wrong: "x", examples: ["y。"])], counters: [], count: 0).isEmpty)
    }

    func testCountCapsAndNeverRepeatsAPitfall() {
        let mistakes = (0..<8).map { mistake("a#\($0)", wrong: "w\($0)", examples: ["e\($0)。"]) }
        let questions = buildSpotMistakeQuestions(mistakes: mistakes, counters: [], count: 5)
        XCTAssertEqual(questions.count, 5)
        XCTAssertEqual(Set(questions.map(\.mistakeID)).count, 5)
        XCTAssertEqual(buildSpotMistakeQuestions(mistakes: mistakes, counters: [], count: 50).count, 8)
    }

    // MARK: Real data

    private func dataURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("data").appendingPathComponent(name)
    }

    func testRealDataMakesAtLeastTwentyWellFormedQuestions() throws {
        let g = try JSONDecoder().decode(GrammarDataFile.self, from: Data(contentsOf: dataURL("grammar.json")))
        let c = try JSONDecoder().decode(CountersDataFile.self, from: Data(contentsOf: dataURL("counters.json")))
        let mistakes = CommonMistakes.build(grammar: g.grammar, counters: c.counters)
        let withWrong = mistakes.filter { $0.wrong != nil }
        XCTAssertGreaterThanOrEqual(withWrong.count, 20)
        let questions = buildSpotMistakeQuestions(mistakes: mistakes, counters: c.counters, count: 1000)
        XCTAssertEqual(questions.count, withWrong.count, "every pitfall with a wrong form has a correct form to set against it")
        for q in questions {
            XCTAssertTrue((2...3).contains(q.choices.count), q.mistakeID)
            XCTAssertEqual(Set(q.choices).count, q.choices.count, q.mistakeID)
            XCTAssertTrue(q.corrects.allSatisfy { $0 != q.wrong }, q.mistakeID)
        }
    }

    // MARK: Kind and history

    func testNewKindIsNotAVerbOrCounterKindAndRoundTrips() throws {
        XCTAssertFalse(QuizQuestionKind.verbKinds.contains(.spotMistake))
        XCTAssertFalse(QuizQuestionKind.spotMistake.isCounter)
        XCTAssertFalse(QuizQuestionKind.spotMistake.isVerbQuestion)
        XCTAssertTrue(QuizQuestionKind.conjugate.isVerbQuestion)
        XCTAssertEqual(QuizQuestionKind.spotMistake.rawValue, "spotMistake")
        let data = try JSONEncoder().encode(QuizQuestionKind.spotMistake)
        XCTAssertEqual(try JSONDecoder().decode(QuizQuestionKind.self, from: data), .spotMistake)
    }

    func testSpotAttemptsCountTowardTotalsButAreNotWeakVerbPairs() {
        let now = Date()
        let attempts = (0..<10).map {
            QuizAttempt(subject: "node#0", formID: "wrong", kind: .spotMistake, outcome: .wrong, date: now.addingTimeInterval(Double($0)))
        }
        let progress = QuizProgress(attempts: attempts, now: now)
        XCTAssertTrue(progress.weakPairs.isEmpty)
        XCTAssertTrue(progress.weakestVerbs.isEmpty)
        XCTAssertTrue(progress.weakestForms.isEmpty)
        XCTAssertEqual(progress.totalAnswered, 10)
        XCTAssertEqual(progress.currentStreak, 1)
    }

    func testVerbQuizBuilderNeverMakesASpotQuestion() throws {
        let verbs = try RealVerbs.load()
        let questions = buildQuestions(verbs: verbs, topics: Set(QuizTopic.allCases), count: 100, kinds: QuizQuestionKind.allCases)
        XCTAssertFalse(questions.isEmpty)
        XCTAssertTrue(questions.allSatisfy { $0.kind != .spotMistake })
    }

    // MARK: Model

    func testModelScoresRecordsAndOffersMissedQuestionsAgain() throws {
        let mistakes = [
            mistake("a#0", wrong: "w0", examples: ["e0。"]),
            mistake("b#0", wrong: "w1", examples: ["e1。"]),
        ]
        let questions = buildSpotMistakeQuestions(mistakes: mistakes, counters: [], count: 2)
        var recorded: [QuizAttempt] = []
        let model = SpotMistakeQuizModel(questions: questions, recorder: { recorded.append($0) })

        let first = try XCTUnwrap(model.currentQuestion)
        model.choose(first.wrong)
        XCTAssertEqual(model.score, 1)
        model.choose(first.corrects[0])  // ignored: already answered
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded[0].kind, .spotMistake)
        XCTAssertEqual(recorded[0].subject, first.mistakeID)
        XCTAssertEqual(recorded[0].outcome, .correct)
        model.advance()

        let second = try XCTUnwrap(model.currentQuestion)
        model.choose(second.corrects[0])
        XCTAssertEqual(recorded[1].outcome, .wrong)
        XCTAssertEqual(model.score, 1)
        model.advance()
        XCTAssertTrue(model.finished)
        XCTAssertEqual(model.missedQuestions.map(\.mistakeID), [second.mistakeID])
    }
}
