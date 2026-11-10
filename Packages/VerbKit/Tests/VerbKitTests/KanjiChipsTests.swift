import XCTest
@testable import VerbKit

final class KanjiChipsTests: XCTestCase {
    func testKanjiKeepTheirOrderAcrossFields() {
        XCTAssertEqual(KanjiExtraction.chips(text: "めっちゃ", spelling: nil, standard: ["凄く", "とても"]).kanji, ["凄"])
        XCTAssertEqual(KanjiExtraction.chips(text: "直す", spelling: nil, standard: ["片付ける"]).kanji, ["直", "片", "付"])
    }

    func testTheSourceIsNamedOnlyWhenOneFieldHasKanji() {
        XCTAssertEqual(KanjiExtraction.chips(text: "めっちゃ", spelling: nil, standard: ["凄く"]).source, .standard)
        XCTAssertEqual(KanjiExtraction.chips(text: "おおきに", spelling: "大きに", standard: ["ありがとう"]).source, .spelling)
        XCTAssertEqual(KanjiExtraction.chips(text: "直す", spelling: nil, standard: ["片付ける"]).source, .mixed)
        XCTAssertEqual(KanjiExtraction.chips(text: "食う", spelling: nil, standard: []).source, .text)
        XCTAssertEqual(KanjiExtraction.chips(text: "ほんま", spelling: nil, standard: ["ほんとう"]).source, .text)
    }

    func testDayIsPublicAndFixed() {
        // 12:00 UTC, the same calendar day in any time zone within ±11 h.
        XCTAssertEqual(WordBankDates.day(Date(timeIntervalSince1970: 1_761_825_600)), "2025-10-30")
    }
}
