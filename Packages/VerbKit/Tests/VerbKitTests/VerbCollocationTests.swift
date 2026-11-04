import XCTest
import SwiftData
@testable import VerbKit

final class VerbCollocationTests: XCTestCase {
    private func verbJSON(collocations: String?) -> Data {
        let field = collocations.map { #", "collocations": \#($0)"# } ?? ""
        return Data("""
        {"type": "ru", "label": "Ru-verb", "dict": "あびる", "kanji": "浴びる", "meaning": "to take (a shower)",
         "description": "d", "forms": {"masu_pos": "あびます", "masu_neg": "あびません", "masu_past": "あびました",
         "masu_past_neg": "あびませんでした", "te": "あびて", "short_pos": "あびる", "short_neg": "あびない",
         "short_past": "あびた", "short_past_neg": "あびなかった"},
         "examples": []\(field)}
        """.utf8)
    }

    private let abiru = Verb(
        type: .ru, label: "Ru-verb", dict: "あびる", kanji: "浴びる",
        meaning: "to take (a shower)", description: "d",
        forms: VerbForms(
            masuPos: "あびます", masuNeg: "あびません", masuPast: "あびました",
            masuPastNeg: "あびませんでした", te: "あびて", shortPos: "あびる",
            shortNeg: "あびない", shortPast: "あびた", shortPastNeg: "あびなかった"
        ),
        examples: [],
        collocations: [VerbCollocation(jp: "シャワーを浴びる", en: "take a shower")]
    )

    func testAVerbWithoutCollocationsDecodesWithNone() throws {
        let verb = try JSONDecoder().decode(Verb.self, from: verbJSON(collocations: nil))
        XCTAssertEqual(verb.collocations, [])
    }

    func testCollocationsDecodeAndTheirIdIsIgnored() throws {
        let json = #"[{"id": "abcdef", "jp": "シャワーを浴びる", "en": "take a shower"}]"#
        let verb = try JSONDecoder().decode(Verb.self, from: verbJSON(collocations: json))
        XCTAssertEqual(verb.collocations, [VerbCollocation(jp: "シャワーを浴びる", en: "take a shower")])
    }

    func testEncodingRoundTrips() throws {
        let decoded = try JSONDecoder().decode(Verb.self, from: JSONEncoder().encode(abiru))
        XCTAssertEqual(decoded, abiru)
    }

    func testSearchMatchesCollocationEnglishCaseInsensitively() {
        XCTAssertTrue(matchesSearch(abiru, query: "take a shower"))
        XCTAssertTrue(matchesSearch(abiru, query: "Shower"))
        XCTAssertFalse(matchesSearch(abiru, query: "take a bath"))
    }

    func testSearchMatchesCollocationJapanese() {
        XCTAssertTrue(matchesSearch(abiru, query: "シャワー"))
    }

    @MainActor
    func testCollocationsSurviveSwiftDataRoundTrip() throws {
        let persisting = SwiftDataVerbPersisting(modelContext: ModelContext(try VerbModelContainer.makeInMemory()))
        try persisting.replaceAllVerbs(with: [abiru])
        XCTAssertEqual(try persisting.loadAllVerbs().first?.collocations, abiru.collocations)
    }

    func testAnEntityWithNoStoredCollocationsReadsAsNone() {
        var verb = abiru
        verb.collocations = []
        XCTAssertEqual(VerbEntity(verb).toVerb()?.collocations, [])
    }

    func testRealDataGivesEveryN5VerbTwoOrMoreCollocations() throws {
        let verbs = try RealVerbs.load()
        for verb in verbs where verb.jlpt == .n5 {
            XCTAssertGreaterThanOrEqual(verb.collocations.count, 2, "\(verb.id) needs collocations")
        }
        let abiru = try XCTUnwrap(verbs.first { $0.dict == "あびる" })
        XCTAssertTrue(matchesSearch(abiru, query: "take a shower"))
    }
}
