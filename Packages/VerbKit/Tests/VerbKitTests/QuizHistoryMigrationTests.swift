import XCTest
import SwiftData
@testable import VerbKit

/// `QuizAttempt.verb` became `subject` (a verb id or a counter id). A store written before the
/// rename, with the old column, must still open and keep its history.
@MainActor
final class QuizHistoryMigrationTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testAnOldStoreKeepsItsAttemptsUnderTheNewName() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "quiz-history-v1", withExtension: "sqlite"))
        try FileManager.default.copyItem(at: fixture, to: directory.appendingPathComponent("VerbKit.sqlite"))

        let context = ModelContext(try VerbModelContainer.make(directory: directory))
        let attempts = try SwiftDataQuizHistoryPersisting(modelContext: context).loadAll()

        // The row with a kind this build does not know is skipped, not a crash.
        XCTAssertEqual(attempts.map(\.subject).sorted(), ["たべる", "みる"])
        XCTAssertEqual(attempts.first { $0.subject == "たべる" }?.kind, .conjugate)
        XCTAssertEqual(attempts.first { $0.subject == "たべる" }?.outcome, .correct)
        XCTAssertEqual(attempts.first { $0.subject == "みる" }?.kind, .identify)
        XCTAssertEqual(attempts.first { $0.subject == "みる" }?.outcome, .wrong)
    }
}
