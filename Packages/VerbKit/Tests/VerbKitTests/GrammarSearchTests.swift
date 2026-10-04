import XCTest
@testable import VerbKit

final class GrammarSearchTests: XCTestCase {
    private var nDesu: GrammarPoint { GrammarFixture.points[0] }

    func testEmptyAndWhitespaceQueriesMatchEverything() {
        XCTAssertTrue(matchesGrammarSearch(nDesu, query: ""))
        XCTAssertTrue(matchesGrammarSearch(nDesu, query: "   "))
    }

    func testMatchesTitle() {
        XCTAssertTrue(matchesGrammarSearch(nDesu, query: "んです"))
    }

    func testMatchesSummaryText() {
        // "なんです" only appears in the summary, not the title.
        XCTAssertTrue(matchesGrammarSearch(nDesu, query: "なんです"))
        XCTAssertTrue(matchesGrammarSearch(nDesu, query: "EXPLANATION"))
    }

    func testMatchesJapaneseExampleText() {
        XCTAssertTrue(matchesGrammarSearch(nDesu, query: "頭が痛い"))
    }

    func testDoesNotMatchEnglishExampleText() {
        XCTAssertFalse(matchesGrammarSearch(nDesu, query: "headache"))
    }

    func testNoMatch() {
        XCTAssertFalse(matchesGrammarSearch(nDesu, query: "はず"))
    }

    func testMatchesRomajiTitle() {
        XCTAssertTrue(matchesGrammarSearch(nDesu, query: "ndesu"))
    }

    func testMatchesRomajiJapaneseExample() {
        // The example is 頭が痛いんです。 Romaji becomes hiragana, so only the kana part can match.
        XCTAssertTrue(matchesGrammarSearch(nDesu, query: "indesu"))
        XCTAssertTrue(matchesGrammarSearch(nDesu, query: "i n desu"))   // spaces are ignored
    }

    func testRomajiCannotMatchKanjiInExample() {
        XCTAssertFalse(matchesGrammarSearch(nDesu, query: "atama ga itai"))   // without a furigana dictionary
    }

    func testRomajiNoMatchInGrammar() {
        XCTAssertFalse(matchesGrammarSearch(nDesu, query: "hazu"))
    }

    // MARK: search by reading

    private let readings = FuriganaDictionary(readings: ["頭": "あたま", "痛い": "いた"])

    func testRomajiMatchesKanjiExampleThroughFurigana() {
        XCTAssertTrue(matchesGrammarSearch(nDesu, query: "atama ga itai", furigana: readings))
    }

    func testKanaMatchesKanjiExampleThroughFurigana() {
        XCTAssertTrue(matchesGrammarSearch(nDesu, query: "あたまがいたい", furigana: readings))
    }

    func testFuriganaDoesNotCreateFalseMatches() {
        XCTAssertFalse(matchesGrammarSearch(nDesu, query: "hazu", furigana: readings))
    }

    func testReadingOfReplacesKnownKanjiOnly() {
        XCTAssertEqual(readings.reading(of: "頭が痛いんです。"), "あたまがいたいんです。")
        XCTAssertEqual(readings.reading(of: "電車が"), "電車が")
    }
}
