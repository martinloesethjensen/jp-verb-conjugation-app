import XCTest
import SwiftData
@testable import VerbKit

@MainActor
final class SwiftDataGrammarPersistingTests: XCTestCase {
    private func makePersisting() throws -> SwiftDataGrammarPersisting {
        let container = try VerbModelContainer.makeInMemory()
        return SwiftDataGrammarPersisting(modelContext: ModelContext(container))
    }

    private func makePoint(id: String) -> GrammarPoint {
        GrammarPoint(
            id: id, title: id, summary: "s", level: .beginner,
            usages: [], attachment: [], conjugations: [], pitfalls: [], related: []
        )
    }

    func testLoadIsEmptyInitially() throws {
        XCTAssertEqual(try makePersisting().loadAllGrammarPoints(), [])
    }

    func testReplaceInsertsAndRoundTripsEveryField() throws {
        let persisting = try makePersisting()
        try persisting.replaceAllGrammarPoints(with: GrammarFixture.points)

        let loaded = try persisting.loadAllGrammarPoints()
        XCTAssertEqual(loaded, GrammarFixture.points)
    }

    func testAttachmentWordClassSurvivesTheRoundTrip() throws {
        let persisting = try makePersisting()
        try persisting.replaceAllGrammarPoints(with: GrammarFixture.points)

        let nDesu = try XCTUnwrap(try persisting.loadAllGrammarPoints().first { $0.id == "n-desu" })
        XCTAssertEqual(nDesu.attachment.first?.wordClass, .verb)
    }

    func testLoadPreservesAuthoredOrder() throws {
        let persisting = try makePersisting()
        let ids = ["c", "a", "d", "b"]
        try persisting.replaceAllGrammarPoints(with: ids.map(makePoint))

        XCTAssertEqual(try persisting.loadAllGrammarPoints().map(\.id), ids)
    }

    func testReplaceRemovesStaleEntries() throws {
        let persisting = try makePersisting()
        try persisting.replaceAllGrammarPoints(with: [makePoint(id: "old")])
        try persisting.replaceAllGrammarPoints(with: [makePoint(id: "new")])

        XCTAssertEqual(try persisting.loadAllGrammarPoints().map(\.id), ["new"])
    }

    func testGrammarAndVerbsShareOneContainerWithoutInterfering() throws {
        let container = try VerbModelContainer.makeInMemory()
        let context = ModelContext(container)
        let grammar = SwiftDataGrammarPersisting(modelContext: context)
        let verbs = SwiftDataVerbPersisting(modelContext: context)

        try grammar.replaceAllGrammarPoints(with: [makePoint(id: "g")])
        try verbs.replaceAllVerbs(with: [])

        XCTAssertEqual(try grammar.loadAllGrammarPoints().map(\.id), ["g"])
    }
}
