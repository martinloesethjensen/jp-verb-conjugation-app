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
            id: id, title: id, summary: "s", jlpt: .n5,
            usages: [], attachment: [], conjugations: [], pitfalls: [], related: []
        )
    }

    func testLoadIsEmptyInitially() throws {
        XCTAssertEqual(try makePersisting().loadAllGrammarPoints(), [])
    }

    func testReplaceInsertsAndRoundTripsEveryField() throws {
        let persisting = try makePersisting()
        try persisting.replaceAllGrammar(points: GrammarFixture.points, textbooks: GrammarFixture.textbooks)

        let loaded = try persisting.loadAllGrammarPoints()
        XCTAssertEqual(loaded, GrammarFixture.points)
    }

    func testAttachmentWordClassSurvivesTheRoundTrip() throws {
        let persisting = try makePersisting()
        try persisting.replaceAllGrammar(points: GrammarFixture.points, textbooks: GrammarFixture.textbooks)

        let nDesu = try XCTUnwrap(try persisting.loadAllGrammarPoints().first { $0.id == "n-desu" })
        XCTAssertEqual(nDesu.attachment.first?.wordClass, .verb)
    }

    func testTextbooksRoundTripInOrder() throws {
        let persisting = try makePersisting()
        XCTAssertEqual(try persisting.loadAllTextbooks(), [])
        try persisting.replaceAllGrammar(points: GrammarFixture.points, textbooks: GrammarFixture.textbooks)

        XCTAssertEqual(try persisting.loadAllTextbooks(), GrammarFixture.textbooks)
        XCTAssertEqual(try persisting.loadAllGrammarPoints().first?.taughtIn.first?.book, "genki-2")
    }

    func testReplaceRemovesStaleTextbooks() throws {
        let persisting = try makePersisting()
        try persisting.replaceAllGrammar(points: [], textbooks: GrammarFixture.textbooks)
        let only = Textbook(id: "other", title: "Other", edition: nil, firstLesson: 1, lessons: 5)
        try persisting.replaceAllGrammar(points: [], textbooks: [only])

        XCTAssertEqual(try persisting.loadAllTextbooks(), [only])
    }

    func testLoadPreservesAuthoredOrder() throws {
        let persisting = try makePersisting()
        let ids = ["c", "a", "d", "b"]
        try persisting.replaceAllGrammar(points: ids.map(makePoint), textbooks: [])

        XCTAssertEqual(try persisting.loadAllGrammarPoints().map(\.id), ids)
    }

    func testReplaceRemovesStaleEntries() throws {
        let persisting = try makePersisting()
        try persisting.replaceAllGrammar(points: [makePoint(id: "old")], textbooks: [])
        try persisting.replaceAllGrammar(points: [makePoint(id: "new")], textbooks: [])

        XCTAssertEqual(try persisting.loadAllGrammarPoints().map(\.id), ["new"])
    }

    func testGrammarAndVerbsShareOneContainerWithoutInterfering() throws {
        let container = try VerbModelContainer.makeInMemory()
        let context = ModelContext(container)
        let grammar = SwiftDataGrammarPersisting(modelContext: context)
        let verbs = SwiftDataVerbPersisting(modelContext: context)

        try grammar.replaceAllGrammar(points: [makePoint(id: "g")], textbooks: [])
        try verbs.replaceAllVerbs(with: [])

        XCTAssertEqual(try grammar.loadAllGrammarPoints().map(\.id), ["g"])
    }
}
