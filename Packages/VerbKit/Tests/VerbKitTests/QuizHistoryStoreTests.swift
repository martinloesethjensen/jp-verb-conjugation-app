import XCTest
@testable import VerbKit

@MainActor
final class QuizHistoryStoreTests: XCTestCase {
    private struct Boom: Error {}

    private final class Double: QuizHistoryPersisting {
        var stored: [QuizAttempt]
        var failing = false
        var appendCalls = 0
        init(stored: [QuizAttempt] = []) { self.stored = stored }
        func loadAll() throws -> [QuizAttempt] {
            if failing { throw Boom() }
            return stored
        }
        func append(_ attempt: QuizAttempt) throws {
            appendCalls += 1
            if failing { throw Boom() }
            stored.append(attempt)
        }
        func deleteAll() throws {
            if failing { throw Boom() }
            stored = []
        }
    }

    private func attempt(_ verb: String) -> QuizAttempt {
        QuizAttempt(verb: verb, formID: "te", kind: .conjugate, outcome: .correct, date: Date(timeIntervalSince1970: 1))
    }

    func testConstructionLoadsExistingAttempts() {
        let a = attempt("a")
        let p = Double(stored: [a])
        XCTAssertEqual(QuizHistoryStore(persisting: p).attempts, [a])
    }

    func testRecordAppendsAndPersistsOnce() {
        let p = Double()
        let store = QuizHistoryStore(persisting: p)
        let a = attempt("a")
        store.record(a)
        XCTAssertEqual(store.attempts, [a])
        XCTAssertEqual(p.stored, [a])
        XCTAssertEqual(p.appendCalls, 1)
    }

    func testResetClearsBoth() {
        let p = Double(stored: [attempt("a")])
        let store = QuizHistoryStore(persisting: p)
        store.reset()
        XCTAssertEqual(store.attempts, [])
        XCTAssertEqual(p.stored, [])
    }

    func testThrowingPersisterLeavesStoreUsable() {
        let p = Double()
        p.failing = true
        let store = QuizHistoryStore(persisting: p)
        XCTAssertEqual(store.attempts, [])
        let a = attempt("a")
        store.record(a)
        XCTAssertEqual(store.attempts, [a])
    }
}
