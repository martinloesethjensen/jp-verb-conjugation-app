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
}
