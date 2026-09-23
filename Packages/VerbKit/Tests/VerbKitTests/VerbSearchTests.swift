import XCTest
@testable import VerbKit

final class VerbSearchTests: XCTestCase {
    private let taberu = Verb(
        type: .ru, label: "Ru-verb", dict: "たべる", kanji: "食べる",
        meaning: "to eat", description: "A common ichidan verb.",
        forms: VerbForms(
            masuPos: "たべます", masuNeg: "たべません", masuPast: "たべました",
            masuPastNeg: "たべませんでした", te: "たべて", shortPos: "たべる",
            shortNeg: "たべない", shortPast: "たべた", shortPastNeg: "たべなかった"
        ),
        examples: []
    )

    func testEmptyQueryMatchesEverything() {
        XCTAssertTrue(matchesSearch(taberu, query: ""))
        XCTAssertTrue(matchesSearch(taberu, query: "   "))
    }

    func testMatchesDictForm() {
        XCTAssertTrue(matchesSearch(taberu, query: "たべる"))
    }

    func testMatchesKanji() {
        XCTAssertTrue(matchesSearch(taberu, query: "食べる"))
    }

    func testMatchesMeaningCaseInsensitive() {
        XCTAssertTrue(matchesSearch(taberu, query: "EAT"))
    }

    func testMatchesConjugatedForm() {
        XCTAssertTrue(matchesSearch(taberu, query: "たべません"))
    }

    func testNoMatchReturnsFalse() {
        XCTAssertFalse(matchesSearch(taberu, query: "のむ"))
    }

    func testTypeFilterNilMatchesAll() {
        XCTAssertTrue(matchesType(taberu, filter: nil))
    }

    func testTypeFilterMatchesExactType() {
        XCTAssertTrue(matchesType(taberu, filter: .ru))
        XCTAssertFalse(matchesType(taberu, filter: .u))
    }
}
