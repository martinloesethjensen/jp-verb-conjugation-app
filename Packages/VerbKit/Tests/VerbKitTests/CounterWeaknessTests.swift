import XCTest
@testable import VerbKit

/// Weak spots for counter readings: the same 5-attempt window and weights as verb pairs.
final class CounterWeaknessTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func attempt(
        _ subject: String, _ form: String, _ kind: QuizQuestionKind, _ outcome: QuizOutcome, at second: Int
    ) -> QuizAttempt {
        QuizAttempt(subject: subject, formID: form, kind: kind, outcome: outcome, date: t0.addingTimeInterval(Double(second)))
    }

    private func progress(_ attempts: [QuizAttempt]) -> QuizProgress {
        QuizProgress(attempts: attempts, now: t0.addingTimeInterval(10_000))
    }

    func testACounterReadingPairIsWeakedByTheSameWindowAndWeightsAsAVerbPair() {
        // Oldest first: miss, miss, right. Newest first the weights are 5, 4, 3: misses weigh 7 of 12.
        let history: [(QuizOutcome)] = [.wrong, .wrong, .correct]
        let counter = history.enumerated().map { attempt("hon", "3", .counterReading, $0.element, at: $0.offset) }
        let verb = history.enumerated().map { attempt("たべる", "te", .conjugate, $0.element, at: $0.offset) }
        let p = progress(counter + verb)
        XCTAssertEqual(p.weakCounterPairs, [WeakCounterPair(counterID: "hon", number: .n(3), weakness: 7.0 / 12.0)])
        XCTAssertEqual(p.weakCounterPairs.first?.weakness, p.weakPairs.first?.weakness)
    }

    func testChoiceMissesAreNotWeakCounterPairs() {
        let attempts = (0..<6).map { attempt("hon", "傘", .counterChoice, .wrong, at: $0) }
        let p = progress(attempts)
        XCTAssertTrue(p.weakCounterPairs.isEmpty)
        XCTAssertTrue(p.weakestCounters.isEmpty)
        XCTAssertEqual(p.totalAnswered, 6)
    }

    func testPairsCanBeLimitedToTheCountersInPlay() {
        let p = progress([
            attempt("hon", "3", .counterReading, .wrong, at: 0),
            attempt("hai", "3", .counterReading, .wrong, at: 1),
        ])
        XCTAssertEqual(p.weakCounterPairs(among: ["hon"]).map(\.counterID), ["hon"])
        XCTAssertEqual(Set(p.weakCounterPairs(among: ["hon", "hai"]).map(\.counterID)), ["hon", "hai"])
        XCTAssertTrue(p.weakCounterPairs(among: []).isEmpty)
    }

    func testAPairWhoseFormIsNotANumberKeyIsDropped() {
        let p = progress([
            attempt("hon", "11", .counterReading, .wrong, at: 0),
            attempt("hon", "what", .counterReading, .wrong, at: 1),
        ])
        XCTAssertEqual(p.weakCounterPairs.map(\.number), [.what])
    }

    func testRankingIsWeaknessThenNewestThenCounterThenNumberOrder() {
        let p = progress([
            attempt("a", "10", .counterReading, .wrong, at: 0),
            attempt("a", "2", .counterReading, .wrong, at: 0),
            attempt("b", "3", .counterReading, .wrong, at: 5),
            attempt("c", "3", .counterReading, .correct, at: 6),
            attempt("c", "3", .counterReading, .wrong, at: 7),
        ])
        // b/3 is all misses and newest; a/2 and a/10 tie on both, so number order puts 2 first;
        // c/3 has a right answer newest-first, so it is weaker only by half.
        XCTAssertEqual(p.weakCounterPairs.map { "\($0.counterID)/\($0.number.key)" }, ["b/3", "a/2", "a/10", "c/3"])
    }

    func testWeakestCountersSumTheirPairsAndKeepTheTopFive() {
        var attempts: [QuizAttempt] = []
        for (n, id) in ["a", "b", "c", "d", "e", "f"].enumerated() {
            attempts.append(attempt(id, "3", .counterReading, .wrong, at: n))
        }
        attempts.append(attempt("a", "4", .counterReading, .wrong, at: 10))
        let p = progress(attempts)
        XCTAssertEqual(p.weakestCounters.count, 5)
        XCTAssertEqual(p.weakestCounters.first, WeakCounter(counterID: "a", weakness: 2.0))
        XCTAssertEqual(p.weakestCounters.map(\.counterID).dropFirst(), ["b", "c", "d", "e"])
    }

    func testCounterAttemptsNeverChangeVerbWeakness() {
        let verb = attempt("たべる", "te", .conjugate, .wrong, at: 0)
        let alone = progress([verb])
        let mixed = progress([verb] + (0..<4).map { attempt("hon", "3", .counterReading, .wrong, at: $0 + 1) })
        XCTAssertEqual(mixed.weakPairs, alone.weakPairs)
        XCTAssertEqual(mixed.weakestVerbs, alone.weakestVerbs)
        XCTAssertEqual(mixed.weakestForms, alone.weakestForms)
    }
}
