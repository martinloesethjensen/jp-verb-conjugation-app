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
