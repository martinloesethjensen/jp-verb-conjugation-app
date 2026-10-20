import XCTest
@testable import VerbKit

/// Counter quiz attempts share the quiz history with verb attempts. Verb code (the verb quiz
/// builder, weak spots, the widget's weak-verb pick) must never see them, while streaks and
/// totals still count them.
final class CounterKindIsolationTests: XCTestCase {
    func testVerbQuizBuilderNeverMakesACounterQuestion() throws {
        let verbs = try RealVerbs.load()
        let questions = buildQuestions(
            verbs: verbs, topics: Set(QuizTopic.allCases), count: 200, kinds: QuizQuestionKind.allCases
        )
        XCTAssertFalse(questions.isEmpty)
        XCTAssertTrue(questions.allSatisfy { !$0.kind.isCounter })
        XCTAssertTrue(QuizQuestionKind.verbKinds.allSatisfy { !$0.isCounter && $0 != .connect })
        XCTAssertTrue(QuizQuestionKind.counterChoice.isCounter)
        XCTAssertTrue(QuizQuestionKind.counterReading.isCounter)
    }

    func testCounterMissesAreNotWeakVerbPairs() {
        let now = Date()
        let attempts = (0..<10).map { offset in
            QuizAttempt(
                subject: "hon", formID: "3", kind: .counterReading, outcome: .wrong,
                date: now.addingTimeInterval(Double(offset))
            )
        }
        let progress = QuizProgress(attempts: attempts, now: now)
        XCTAssertTrue(progress.weakPairs.isEmpty)
        XCTAssertTrue(progress.weakestVerbs.isEmpty)
        XCTAssertTrue(progress.weakestForms.isEmpty)
        XCTAssertTrue(progress.weakPairs(among: ["hon"]).isEmpty)
    }

    func testCounterAttemptsStillCountTowardStreakAndTotals() {
        let now = Date()
        let attempt = QuizAttempt(subject: "hon", formID: "しゃしん", kind: .counterChoice, outcome: .correct, date: now)
        let progress = QuizProgress(attempts: [attempt], now: now)
        XCTAssertEqual(progress.totalAnswered, 1)
        XCTAssertEqual(progress.currentStreak, 1)
        XCTAssertTrue(progress.hasHistory)
    }
}
