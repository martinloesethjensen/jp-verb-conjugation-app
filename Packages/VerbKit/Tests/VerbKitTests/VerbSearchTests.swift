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

    func testMatchesRomajiDictionaryForm() {
        XCTAssertTrue(matchesSearch(taberu, query: "taberu"))
        XCTAssertTrue(matchesSearch(taberu, query: "TABERU"))
    }

    func testMatchesRomajiConjugatedForm() {
        XCTAssertTrue(matchesSearch(taberu, query: "tabemashita"))
        XCTAssertTrue(matchesSearch(taberu, query: "tabenakatta"))
    }

    func testMatchesPartialRomaji() {
        XCTAssertTrue(matchesSearch(taberu, query: "tab"))
        XCTAssertTrue(matchesSearch(taberu, query: "tabesh"))   // "sh" is dropped, leaving たべ
    }

    func testRomajiNoMatch() {
        XCTAssertFalse(matchesSearch(taberu, query: "nomu"))
    }

    func testEnglishMeaningStillMatchesOnRawText() {
        XCTAssertTrue(matchesSearch(taberu, query: "eat"))
    }
}
