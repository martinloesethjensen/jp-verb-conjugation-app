import XCTest
import SwiftData
@testable import VerbKit

@MainActor
final class SwiftDataVerbPersistingTests: XCTestCase {
    private func makePersisting() throws -> SwiftDataVerbPersisting {
        let container = try VerbModelContainer.makeInMemory()
        let context = ModelContext(container)
        return SwiftDataVerbPersisting(modelContext: context)
    }

    private func makeVerb(dict: String) -> Verb {
        Verb(
            type: .ru, label: "Ru-verb", dict: dict, kanji: "漢字",
            meaning: "to \(dict)", description: "d", notes: "n", teGroup: nil,
            forms: VerbForms(
                masuPos: "a", masuNeg: "b", masuPast: "c", masuPastNeg: "d",
                te: "e", shortPos: "f", shortNeg: "g", shortPast: "h",
                shortPastNeg: "i", potential: "j"
            ),
            examples: [VerbExample(form: .te, jp: "jp", en: "en")]
        )
    }

    func testLoadAllVerbsIsEmptyInitially() throws {
        let persisting = try makePersisting()
        XCTAssertEqual(try persisting.loadAllVerbs(), [])
    }

    func testReplaceAllVerbsInsertsAndRoundTrips() throws {
        let persisting = try makePersisting()
        let verb = makeVerb(dict: "たべる")
        try persisting.replaceAllVerbs(with: [verb])

        let loaded = try persisting.loadAllVerbs()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0], verb)
        XCTAssertEqual(loaded[0].forms.potential, "j")
    }

    func testReplaceAllVerbsRemovesStaleEntries() throws {
        let persisting = try makePersisting()
        try persisting.replaceAllVerbs(with: [makeVerb(dict: "のむ")])
        try persisting.replaceAllVerbs(with: [makeVerb(dict: "よむ")])

        let loaded = try persisting.loadAllVerbs()
        XCTAssertEqual(loaded.map(\.dict), ["よむ"])
    }
}
