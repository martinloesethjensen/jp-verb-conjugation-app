import XCTest
@testable import VerbKit

final class QuizGeneratorTests: XCTestCase {
    private func makeVerb(dict: String, masuPos: String) -> Verb {
        Verb(
            type: .u, label: "U-verb", dict: dict, kanji: nil,
            meaning: "to \(dict)", description: "d",
            forms: VerbForms(
                masuPos: masuPos, masuNeg: "\(dict)-neg", masuPast: "\(dict)-past",
                masuPastNeg: "\(dict)-pastneg", te: "\(dict)-te", shortPos: dict,
                shortNeg: "\(dict)-sneg", shortPast: "\(dict)-spast", shortPastNeg: "\(dict)-spastneg"
            ),
            examples: []
        )
    }

    private var verbs: [Verb] {
        [
            makeVerb(dict: "のむ", masuPos: "のみます"),
            makeVerb(dict: "よむ", masuPos: "よみます"),
            makeVerb(dict: "かく", masuPos: "かきます"),
        ]
    }

    func testReturnsRequestedCount() {
        let questions = buildQuestions(verbs: verbs, count: 5)
        XCTAssertEqual(questions.count, 5)
    }

    func testCapsAtAvailablePoolSize() {
        let questions = buildQuestions(verbs: verbs, count: 100)
        XCTAssertEqual(questions.count, verbs.count * FormKey.allCases.count)
    }

    func testCorrectAnswerMatchesVerbForm() {
        let questions = buildQuestions(verbs: verbs, count: 27)
        for question in questions {
            XCTAssertEqual(question.correct, question.verb.forms[question.form])
        }
    }

    func testChoicesContainCorrectAnswer() {
        let questions = buildQuestions(verbs: verbs, count: 10)
        for question in questions {
            XCTAssertTrue(question.choices.contains(question.correct))
        }
    }

    func testChoicesHaveNoDuplicates() {
        let questions = buildQuestions(verbs: verbs, count: 27)
        for question in questions {
            XCTAssertEqual(Set(question.choices).count, question.choices.count)
        }
    }

    func testChoicesCapAtFour() {
        let questions = buildQuestions(verbs: verbs, count: 27)
        for question in questions {
            XCTAssertLessThanOrEqual(question.choices.count, 4)
        }
    }
}
