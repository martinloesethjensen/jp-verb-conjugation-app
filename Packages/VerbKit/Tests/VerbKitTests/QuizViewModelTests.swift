import XCTest
@testable import VerbKit

final class QuizViewModelTests: XCTestCase {
    private func makeQuestion(correct: String, choices: [String], dict: String = "たべる") -> QuizQuestion {
        let verb = Verb(
            type: .ru, label: "Ru-verb", dict: dict, kanji: nil, meaning: "to eat", description: "d",
            forms: VerbForms(masuPos: correct, masuNeg: "x", masuPast: "x", masuPastNeg: "x", te: "x", shortPos: "x", shortNeg: "x", shortPast: "x", shortPastNeg: "x"),
            examples: []
        )
        let form = QuizForm.all.first { $0.id == "masu_pos" }!
        return QuizQuestion(verb: verb, form: form, kind: .conjugate, formString: correct, correct: correct, choices: choices)
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

    func testTimeoutIsRecordedAsAMiss() {
        let vm = QuizViewModel(questions: [makeQuestion(correct: "たべます", choices: ["たべます", "のみます"])])
        vm.markTimedOut()
        XCTAssertTrue(vm.timedOut)
        XCTAssertTrue(vm.isAnswered)
        XCTAssertEqual(vm.results.count, 1)
        XCTAssertTrue(vm.results[0].timedOut)
        XCTAssertFalse(vm.results[0].ok)
        XCTAssertEqual(vm.results[0].chosen, "")
        XCTAssertEqual(vm.score, 0)
    }

    func testTimingOutTwiceOrAfterAnsweringRecordsOnce() {
        let vm = QuizViewModel(questions: [makeQuestion(correct: "A", choices: ["A", "B"])])
        vm.markTimedOut()
        vm.markTimedOut()
        XCTAssertEqual(vm.results.count, 1)
        let other = QuizViewModel(questions: [makeQuestion(correct: "A", choices: ["A", "B"])])
        other.choose("A")
        other.markTimedOut()
        XCTAssertEqual(other.results.count, 1)
        XCTAssertFalse(other.results[0].timedOut)
    }

    func testMissedQuestionsAreTheWrongAndTimedOutOnes() {
        let vm = QuizViewModel(questions: [
            makeQuestion(correct: "A", choices: ["A", "B", "C"], dict: "1"),
            makeQuestion(correct: "C", choices: ["C", "D", "E"], dict: "2"),
            makeQuestion(correct: "F", choices: ["F", "G", "H"], dict: "3"),
        ])
        vm.choose("A"); vm.advance()      // right
        vm.choose("D"); vm.advance()      // wrong
        vm.markTimedOut(); vm.advance()   // timed out
        XCTAssertTrue(vm.finished)
        let missed = vm.missedQuestions
        XCTAssertEqual(missed.map(\.verb.dict), ["2", "3"])
        XCTAssertEqual(missed.map { Set($0.choices) }, [["C", "D", "E"], ["F", "G", "H"]])
        XCTAssertEqual(missed.map(\.correct), ["C", "F"])
    }

    func testNothingMissedWhenAllCorrect() {
        let vm = QuizViewModel(questions: [makeQuestion(correct: "A", choices: ["A", "B"])])
        vm.choose("A"); vm.advance()
        XCTAssertTrue(vm.missedQuestions.isEmpty)
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

    func testResultsCarryTheFormLabelAndString() {
        let vm = QuizViewModel(questions: [makeQuestion(correct: "たべます", choices: ["たべます", "のみます"])])
        vm.choose("たべます")
        XCTAssertEqual(vm.results[0].formLabel, "Polite")
        XCTAssertEqual(vm.results[0].formString, "たべます")
        XCTAssertEqual(vm.results[0].kind, .conjugate)
    }
}
