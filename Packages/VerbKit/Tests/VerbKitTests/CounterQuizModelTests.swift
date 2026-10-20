import XCTest
@testable import VerbKit

final class CounterQuizModelTests: XCTestCase {
    private func reading(
        counter: String = "hon", form: String = "3", correct: String = "さんぼん",
        accepted: Set<String>? = nil, choices: [String] = ["さんぼん", "さんほん", "さんぽん", "さっぽん"]
    ) -> CounterQuestion {
        CounterQuestion(
            kind: .counterReading, counterID: counter, formID: form, prompt: "三本", detail: "long, thin things",
            correct: correct, accepted: accepted ?? [correct], choices: choices, explanation: "本 changes at 3: さんぼん"
        )
    }

    private func choice() -> CounterQuestion {
        CounterQuestion(
            kind: .counterChoice, counterID: "hon", formID: "傘", prompt: "傘", detail: "umbrella", symbol: "umbrella",
            correct: "本", accepted: ["本"], choices: ["本", "杯", "匹", "人"], explanation: "傘 is counted with 本"
        )
    }

    private func model(
        _ questions: [CounterQuestion], recorded: @escaping (QuizAttempt) -> Void = { _ in }
    ) -> CounterQuizModel {
        CounterQuizModel(
            questions: questions, recorder: recorded, now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }

    func testARightAnswerScoresAndRecordsACorrectReadingAttempt() {
        var recorded: [QuizAttempt] = []
        let quiz = model([reading()]) { recorded.append($0) }
        quiz.choose("さんぼん")
        XCTAssertEqual(quiz.score, 1)
        XCTAssertTrue(quiz.isAnswered)
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.subject, "hon")
        XCTAssertEqual(recorded.first?.formID, "3")
        XCTAssertEqual(recorded.first?.kind, .counterReading)
        XCTAssertEqual(recorded.first?.outcome, .correct)
        XCTAssertEqual(recorded.first?.date, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testAWrongAnswerRecordsAWrongAttemptAndDoesNotScore() {
        var recorded: [QuizAttempt] = []
        let quiz = model([reading()]) { recorded.append($0) }
        quiz.choose("さんほん")
        XCTAssertEqual(quiz.score, 0)
        XCTAssertEqual(recorded.map(\.outcome), [.wrong])
        XCTAssertEqual(recorded.first?.subject, "hon")
        XCTAssertEqual(recorded.first?.formID, "3")
        XCTAssertEqual(recorded.first?.kind, .counterReading)
    }

    func testAnyAcceptedReadingCountsAsRight() {
        let eight = reading(
            form: "8", correct: "はっぽん", accepted: ["はっぽん", "はちほん"],
            choices: ["はっぽん", "はちほん", "はっぼん", "はちぽん"]
        )
        let quiz = model([eight])
        quiz.choose("はちほん")
        XCTAssertEqual(quiz.score, 1)
    }

    func testAWhichCounterAnswerRecordsTheThingAsTheForm() {
        var recorded: [QuizAttempt] = []
        let quiz = model([choice()]) { recorded.append($0) }
        quiz.choose("杯")
        XCTAssertEqual(recorded.first?.kind, .counterChoice)
        XCTAssertEqual(recorded.first?.formID, "傘")
        XCTAssertEqual(recorded.first?.subject, "hon")
        XCTAssertEqual(recorded.first?.outcome, .wrong)
    }

    func testASecondChoiceInTheSameQuestionIsIgnored() {
        var recorded: [QuizAttempt] = []
        let quiz = model([reading(), reading(form: "6")]) { recorded.append($0) }
        quiz.choose("さんほん")
        quiz.choose("さんぼん")
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(quiz.score, 0)
        XCTAssertEqual(quiz.selected, "さんほん")
    }

    func testAdvancingOnTheLastQuestionFinishesAndNeverGoesPastIt() {
        let quiz = model([reading(), reading(form: "6")])
        quiz.advance()
        XCTAssertEqual(quiz.index, 0, "advancing before answering does nothing")
        quiz.choose("さんぼん")
        quiz.advance()
        XCTAssertEqual(quiz.index, 1)
        XCTAssertNil(quiz.selected)
        XCTAssertFalse(quiz.finished)
        quiz.choose("さんぼん")
        quiz.advance()
        XCTAssertTrue(quiz.finished)
        XCTAssertEqual(quiz.index, 1)
    }

    func testMissedQuestionsAreOnlyTheWrongOnesWithTheirChoicesKept() {
        let quiz = model([reading(form: "1"), reading(form: "3"), reading(form: "6")])
        quiz.choose("さんぼん"); quiz.advance()
        quiz.choose("さんほん"); quiz.advance()
        quiz.choose("さっぽん"); quiz.advance()
        let missed = quiz.missedQuestions
        XCTAssertEqual(missed.map(\.formID), ["3", "6"])
        XCTAssertTrue(missed.allSatisfy { Set($0.choices) == ["さんぼん", "さんほん", "さんぽん", "さっぽん"] })
    }

    func testNoQuestionsMeansNothingToAnswer() {
        let quiz = model([])
        XCTAssertNil(quiz.currentQuestion)
        quiz.choose("x")
        XCTAssertFalse(quiz.isAnswered)
    }
}
