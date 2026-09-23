import XCTest
@testable import VerbKit

final class QuizViewModelTests: XCTestCase {
    private func makeQuestion(correct: String, choices: [String], dict: String = "たべる") -> QuizQuestion {
        let verb = Verb(
            type: .ru, label: "Ru-verb", dict: dict, kanji: nil, meaning: "to eat", description: "d",
            forms: VerbForms(masuPos: correct, masuNeg: "x", masuPast: "x", masuPastNeg: "x", te: "x", shortPos: "x", shortNeg: "x", shortPast: "x", shortPastNeg: "x"),
            examples: []
        )
        return QuizQuestion(verb: verb, form: .masuPos, correct: correct, choices: choices)
    }

    func testChoosingCorrectAnswerIncrementsScore() {
        let vm = QuizViewModel(questions: [makeQuestion(correct: "たべます", choices: ["たべます", "のみます"])])
        vm.choose("たべます")
        XCTAssertEqual(vm.score, 1)
        XCTAssertEqual(vm.results.count, 1)
        XCTAssertTrue(vm.results[0].ok)
    }

    func testChoosingWrongAnswerDoesNotIncrementScore() {
        let vm = QuizViewModel(questions: [makeQuestion(correct: "たべます", choices: ["たべます", "のみます"])])
        vm.choose("のみます")
        XCTAssertEqual(vm.score, 0)
        XCTAssertFalse(vm.results[0].ok)
        XCTAssertEqual(vm.results[0].chosen, "のみます")
    }

    func testChoosingTwiceIsIgnored() {
        let vm = QuizViewModel(questions: [makeQuestion(correct: "たべます", choices: ["たべます", "のみます"])])
        vm.choose("たべます")
        vm.choose("のみます")
        XCTAssertEqual(vm.score, 1)
        XCTAssertEqual(vm.results.count, 1)
    }

    func testTimeoutMarksAnsweredWithoutRecordingResult() {
        // Matches the web app: a timeout does not append to `results`,
        // it only flips the answered/timedOut flags.
        let vm = QuizViewModel(questions: [makeQuestion(correct: "たべます", choices: ["たべます", "のみます"])])
        vm.markTimedOut()
        XCTAssertTrue(vm.timedOut)
        XCTAssertTrue(vm.isAnswered)
        XCTAssertTrue(vm.results.isEmpty)
    }

    func testAdvanceMovesToNextQuestionAndResetsState() {
        let vm = QuizViewModel(questions: [
            makeQuestion(correct: "A", choices: ["A", "B"], dict: "1"),
            makeQuestion(correct: "C", choices: ["C", "D"], dict: "2"),
        ])
        vm.choose("A")
        vm.advance()
        XCTAssertEqual(vm.index, 1)
        XCTAssertNil(vm.selected)
        XCTAssertFalse(vm.timedOut)
        XCTAssertEqual(vm.timeLeft, 20)
        XCTAssertFalse(vm.finished)
    }

    func testAdvanceOnLastQuestionFinishesQuiz() {
        let vm = QuizViewModel(questions: [makeQuestion(correct: "A", choices: ["A", "B"])])
        vm.choose("A")
        vm.advance()
        XCTAssertTrue(vm.finished)
    }

    func testTickTimerCountsDownAndTimesOutAtZero() {
        let vm = QuizViewModel(questions: [makeQuestion(correct: "A", choices: ["A", "B"])])
        XCTAssertEqual(vm.timeLeft, 20)
        for _ in 0..<19 { vm.tickTimer() }
        XCTAssertEqual(vm.timeLeft, 1)
        XCTAssertFalse(vm.timedOut)
        vm.tickTimer()
        XCTAssertEqual(vm.timeLeft, 0)
        XCTAssertTrue(vm.timedOut)
    }

    func testTickTimerStopsOnceAnswered() {
        let vm = QuizViewModel(questions: [makeQuestion(correct: "A", choices: ["A", "B"])])
        vm.choose("A")
        vm.tickTimer()
        XCTAssertEqual(vm.timeLeft, 20)
    }
}
