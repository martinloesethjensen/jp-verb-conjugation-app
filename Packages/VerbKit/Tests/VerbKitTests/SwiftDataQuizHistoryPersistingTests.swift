import XCTest
import SwiftData
@testable import VerbKit

@MainActor
final class SwiftDataQuizHistoryPersistingTests: XCTestCase {
    private func make() throws -> (SwiftDataQuizHistoryPersisting, ModelContext) {
        let container = try VerbModelContainer.makeInMemory()
        let context = ModelContext(container)
        return (SwiftDataQuizHistoryPersisting(modelContext: context), context)
    }

    private func attempt(_ verb: String, _ outcome: QuizOutcome = .correct, kind: QuizQuestionKind = .conjugate, at t: TimeInterval) -> QuizAttempt {
        QuizAttempt(verb: verb, formID: "te", kind: kind, outcome: outcome, date: Date(timeIntervalSince1970: t))
    }

    func testLoadAllIsEmptyInitially() throws {
        let (p, _) = try make()
        XCTAssertEqual(try p.loadAll(), [])
    }

    func testAppendThenLoadAllKeepsEveryField() throws {
        let (p, _) = try make()
        let a = attempt("食べる", .wrong, kind: .identify, at: 100)
        let b = attempt("飲む", .timedOut, at: 200)
        try p.append(a)
        try p.append(b)
        XCTAssertEqual(try p.loadAll(), [a, b])
    }

    func testLoadAllSortsByDateThenInsertion() throws {
        let (p, _) = try make()
        let late = attempt("a", at: 300)
        let tie1 = attempt("b", at: 100)
        let tie2 = attempt("c", at: 100)
        try p.append(late)
        try p.append(tie1)
        try p.append(tie2)
        XCTAssertEqual(try p.loadAll(), [tie1, tie2, late])
    }

    func testDeleteAllEmpties() throws {
        let (p, _) = try make()
        try p.append(attempt("a", at: 1))
        try p.deleteAll()
        XCTAssertEqual(try p.loadAll(), [])
    }

    func testUnknownRawRowsAreSkipped() throws {
        let (p, context) = try make()
        let good = attempt("a", at: 1)
        try p.append(good)
        context.insert(QuizAttemptEntity(id: UUID(), verb: "x", formID: "te", kindRaw: "bogus", outcomeRaw: "correct", date: Date()))
        context.insert(QuizAttemptEntity(id: UUID(), verb: "y", formID: "te", kindRaw: "conjugate", outcomeRaw: "bogus", date: Date()))
        try context.save()
        XCTAssertEqual(try p.loadAll(), [good])
    }
}
