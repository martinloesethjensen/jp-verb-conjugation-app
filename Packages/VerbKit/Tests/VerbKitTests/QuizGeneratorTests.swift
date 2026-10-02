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
        let questions = buildQuestions(verbs: try verbs(), topics: [.potential, .nDesu], count: 60)
        XCTAssertEqual(questions.count, 60)
        for question in questions {
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
        let questions = buildQuestions(verbs: try verbs(), topics: all, count: 60, kinds: [.conjugate])
        XCTAssertEqual(questions.count, 60)
        for question in questions {
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
        let chosen: Set<QuizTopic> = [.potential]
        let questions = buildQuestions(verbs: try verbs(), topics: chosen, count: 60, kinds: [.identify])
        XCTAssertEqual(questions.count, 60)
        for question in questions {
            XCTAssertEqual(question.kind, .identify)
            XCTAssertEqual(question.correct, question.form.label)
            XCTAssertEqual(question.formString, question.form.value(in: question.verb.forms))
            // every choice is a label of this verb's own forms in the chosen topic only
            XCTAssertTrue(Set(question.choices).isSubset(of: sameVerbLabels(question.verb, chosen)))
        }
    }

    func testChoicesAreDistinctContainTheAnswerOnceAndAreTwoToFour() throws {
        for kinds in [[QuizQuestionKind.conjugate], [.identify]] {
            let questions = buildQuestions(verbs: try verbs(), topics: all, count: 200, kinds: kinds)
            XCTAssertEqual(questions.count, 200)
            for question in questions {
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
        let questions = buildQuestions(verbs: try verbs(), topics: [.basic], count: 1000, kinds: [.conjugate])
        XCTAssertEqual(questions.count, try verbs().count * 9)
        for question in questions {
            XCTAssertEqual(question.choices.count, 4)
            XCTAssertEqual(question.form.topic, .basic)
        }
    }

    func testAFormSharingItsStringWithAnotherIsNeverAsked() throws {
        var taberu = try XCTUnwrap(try verbs().first { $0.dict == "たべる" })
        taberu.forms.masuNeg = taberu.forms.masuPos // two forms, one string: two right answers
        let questions = buildQuestions(verbs: [taberu], topics: [.basic], count: 100)
        XCTAssertEqual(questions.count, 7)
        XCTAssertFalse(questions.contains { ["masu_pos", "masu_neg"].contains($0.form.id) })
    }

    func testEverythingDrawsOnAllFourTopics() throws {
        let questions = buildQuestions(verbs: try verbs(), topics: all, count: 2000)
        XCTAssertEqual(Set(questions.map(\.form.topic)), Set(QuizTopic.allCases))
    }

    func testNoQuestionsForAZeroCountOrNoKinds() throws {
        XCTAssertTrue(buildQuestions(verbs: try verbs(), topics: all, count: 0).isEmpty)
        XCTAssertTrue(buildQuestions(verbs: try verbs(), topics: all, count: 5, kinds: []).isEmpty)
        XCTAssertTrue(buildQuestions(verbs: try verbs(), topics: [], count: 5).isEmpty)
    }

    // MARK: pairs

    private func pairs(_ verb: Verb, _ ids: [String]) -> [(verb: Verb, form: QuizForm)] {
        ids.map { id in (verb, QuizForm.all.first { $0.id == id }!) }
    }

    func testPairsBuildExactlyTheGivenPairsInOrder() throws {
        let all = try verbs()
        let taberu = try XCTUnwrap(all.first { $0.dict == "たべる" })
        let nomu = try XCTUnwrap(all.first { $0.dict == "のむ" })
        let given = pairs(taberu, ["masu_pos", "te"]) + pairs(nomu, ["short_neg"])
        let questions = buildQuestions(pairs: given, among: all, count: 10)
        XCTAssertEqual(questions.map(\.verb.dict), ["たべる", "たべる", "のむ"])
        XCTAssertEqual(questions.map(\.form.id), ["masu_pos", "te", "short_neg"])
        XCTAssertEqual(buildQuestions(pairs: given, among: all, count: 2).count, 2)
        XCTAssertTrue(buildQuestions(pairs: given, among: all, count: 0).isEmpty)
    }

    func testPairsChoicesAreWellFormed() throws {
        let all = try verbs()
        let taberu = try XCTUnwrap(all.first { $0.dict == "たべる" })
        let ids = QuizForm.all.map(\.id)
        let given = pairs(taberu, ids)
        let sameVerbLabels = Set(QuizForm.available(in: taberu.forms, topics: Set(QuizTopic.allCases)).map(\.form.label))
        let sameVerbStrings = Set(QuizForm.available(in: taberu.forms, topics: Set(QuizTopic.allCases)).map(\.value))
        for kind in [QuizQuestionKind.conjugate, .identify] {
            let questions = buildQuestions(pairs: given, among: all, count: 100, kinds: [kind])
            XCTAssertFalse(questions.isEmpty)
            for q in questions {
                XCTAssertEqual(q.kind, kind)
                XCTAssertEqual(q.choices.filter { $0 == q.correct }.count, 1)
                XCTAssertGreaterThanOrEqual(q.choices.count, 2)
                XCTAssertEqual(Set(q.choices).count, q.choices.count)
                if kind == .identify {
                    XCTAssertEqual(q.correct, q.form.label)
                    XCTAssertTrue(Set(q.choices).isSubset(of: sameVerbLabels))
                } else {
                    XCTAssertEqual(q.correct, q.form.value(in: taberu.forms))
                    // same verb's other forms come first: with 47 of them there are always 3.
                    XCTAssertEqual(q.choices.count, 4)
                    XCTAssertTrue(Set(q.choices).isSubset(of: sameVerbStrings))
                }
            }
        }
    }

    func testPairsConjugateDistractorsFallBackToOtherVerbs() throws {
        let all = try verbs()
        let taberu = try XCTUnwrap(all.first { $0.dict == "たべる" })
        // A verb whose other forms all collide with each other has no same-verb distractor.
        let lone = Verb(
            type: .ru, label: "Ru-verb", dict: "lone", kanji: nil, meaning: "m", description: "d",
            forms: VerbForms(masuPos: "uniq", masuNeg: "dup", masuPast: "dup", masuPastNeg: "dup", te: "dup", shortPos: "dup", shortNeg: "dup", shortPast: "dup", shortPastNeg: "dup"),
            examples: []
        )
        let masuPos = try XCTUnwrap(QuizForm.all.first { $0.id == "masu_pos" })
        let questions = buildQuestions(
            pairs: [(lone, masuPos)], among: [lone, taberu], count: 5, kinds: [.conjugate]
        )
        XCTAssertEqual(questions.count, 1)
        XCTAssertTrue(questions[0].choices.contains("uniq"))
        XCTAssertTrue(questions[0].choices.contains(try XCTUnwrap(masuPos.value(in: taberu.forms))))
    }

    func testPairsSkipAStringCollision() throws {
        let verb = Verb(
            type: .ru, label: "Ru-verb", dict: "x", kanji: nil, meaning: "m", description: "d",
            forms: VerbForms(masuPos: "same", masuNeg: "n", masuPast: "same", masuPastNeg: "pn", te: "t", shortPos: "sp", shortNeg: "sn", shortPast: "spa", shortPastNeg: "spn"),
            examples: []
        )
        let questions = buildQuestions(
            pairs: pairs(verb, ["masu_pos", "masu_neg", "masu_past"]), among: [verb], count: 5, kinds: [.conjugate]
        )
        XCTAssertEqual(questions.map(\.form.id), ["masu_neg"])
    }

    // MARK: fill-in

    func testFillInBlanksTheFormInAnExampleSentence() throws {
        let questions = buildQuestions(verbs: try verbs(), topics: all, count: 1000, kinds: [.fillIn])
        XCTAssertFalse(questions.isEmpty)
        for question in questions {
            let sentence = try XCTUnwrap(question.sentence)
            XCTAssertTrue(sentence.contains(QuizQuestion.blank))
            XCTAssertEqual(question.correct, question.formString)
            XCTAssertNotNil(question.translation)
            XCTAssertTrue(question.choices.contains(question.correct))
            XCTAssertGreaterThanOrEqual(question.choices.count, 2)
            XCTAssertEqual(Set(question.choices).count, question.choices.count)
        }
    }

    func testFillInDistractorsAreTheSameVerbsForms() throws {
        let all = Set(QuizTopic.allCases)
        for question in buildQuestions(verbs: try verbs(), topics: all, count: 1000, kinds: [.fillIn]) {
            let own = Set(QuizForm.available(in: question.verb.forms, topics: all).map(\.value))
            XCTAssertTrue(Set(question.choices).isSubset(of: own))
        }
    }

    func testFillInIsSkippedWithoutAMatchingExample() throws {
        var taberu = try XCTUnwrap(try verbs().first { $0.dict == "たべる" })
        taberu.examples = []
        XCTAssertTrue(buildQuestions(verbs: [taberu], topics: all, count: 10, kinds: [.fillIn]).isEmpty)
        // With other kinds allowed it still gets questions.
        XCTAssertFalse(buildQuestions(verbs: [taberu], topics: all, count: 10, kinds: [.fillIn, .conjugate]).isEmpty)
    }
}
