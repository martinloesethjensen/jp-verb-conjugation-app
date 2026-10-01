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
        let questions = buildQuestions(verbs: try verbs(), topics: [.basic], count: 1000, kinds: [.conjugate])
        XCTAssertEqual(questions.count, 25 * 9)
        for question in questions {
            XCTAssertEqual(question.choices.count, 4)
            XCTAssertEqual(question.form.topic, .basic)
        }
    }
}
