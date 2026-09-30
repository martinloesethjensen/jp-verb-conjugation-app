import XCTest
import SwiftData
@testable import VerbKit

@MainActor
final class SwiftDataFuriganaPersistingTests: XCTestCase {
    private func makePersisting() throws -> SwiftDataFuriganaPersisting {
        let container = try VerbModelContainer.makeInMemory()
        return SwiftDataFuriganaPersisting(modelContext: ModelContext(container))
    }

    func testLoadIsNilInitially() throws {
        XCTAssertNil(try makePersisting().loadFuriganaDictionary())
    }

    func testReplaceStoresTheDictionaryAndLoadRoundTripsIt() throws {
        let persisting = try makePersisting()
        try persisting.replaceFuriganaDictionary(with: FuriganaFixture.dictionary)
        XCTAssertEqual(try persisting.loadFuriganaDictionary(), FuriganaFixture.dictionary)
    }

    func testAReloadedDictionaryStillMatchesText() throws {
        let persisting = try makePersisting()
        try persisting.replaceFuriganaDictionary(with: FuriganaFixture.dictionary)
        let loaded = try XCTUnwrap(try persisting.loadFuriganaDictionary())
        XCTAssertEqual(loaded.units(for: "来られる").first, TextUnit(text: "来", reading: "こ"))
    }

    func testReplaceOverwritesTheEarlierDictionaryInsteadOfAddingARow() throws {
        let persisting = try makePersisting()
        try persisting.replaceFuriganaDictionary(with: FuriganaFixture.dictionary)
        let newer = FuriganaDictionary(readings: ["猫": "ねこ"])
        try persisting.replaceFuriganaDictionary(with: newer)
        XCTAssertEqual(try persisting.loadFuriganaDictionary(), newer)
    }

    func testAnEmptyDictionaryRoundTrips() throws {
        let persisting = try makePersisting()
        try persisting.replaceFuriganaDictionary(with: .empty)
        XCTAssertEqual(try persisting.loadFuriganaDictionary(), .empty)
    }

    func testVerbsGrammarAndFuriganaShareOneContainerWithoutInterfering() throws {
        let container = try VerbModelContainer.makeInMemory()
        let context = ModelContext(container)
        let furigana = SwiftDataFuriganaPersisting(modelContext: context)
        let grammar = SwiftDataGrammarPersisting(modelContext: context)
        let verbs = SwiftDataVerbPersisting(modelContext: context)

        try grammar.replaceAllGrammarPoints(with: GrammarFixture.points)
        try verbs.replaceAllVerbs(with: [])
        try furigana.replaceFuriganaDictionary(with: FuriganaFixture.dictionary)

        XCTAssertEqual(try furigana.loadFuriganaDictionary(), FuriganaFixture.dictionary)
        XCTAssertEqual(try grammar.loadAllGrammarPoints().count, 2)
    }
}
