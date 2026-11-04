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

    func testMatchesEnglishExampleText() {
        XCTAssertTrue(matchesGrammarSearch(nDesu, query: "headache"))
        XCTAssertEqual(grammarSearchRank(nDesu, query: "HEADACHE"), .example)
    }

    func testMatchesUsageHeading() {
        // "Giving a reason" is the usage heading; it is in neither the title nor the summary.
        XCTAssertEqual(grammarSearchRank(nDesu, query: "giving a"), .heading)
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

    // MARK: keywords and ranking

    private func point(
        _ id: String, title: String = "〜テスト", summary: String = "A pattern.", keywords: [String] = [],
        heading: String = "Usage", en: String = "An example."
    ) -> GrammarPoint {
        GrammarPoint(
            id: id, title: title, summary: summary, keywords: keywords,
            usages: [GrammarUsage(heading: heading, explanation: "e", examples: [GrammarExample(jp: "例です。", en: en)])],
            attachment: [], conjugations: [], pitfalls: [], related: []
        )
    }

    func testMatchesKeyword() {
        let node = point("node", keywords: ["because", "since"])
        XCTAssertTrue(matchesGrammarSearch(node, query: "Because"))
        XCTAssertEqual(grammarSearchRank(node, query: "because"), .exact)
        XCTAssertEqual(grammarSearchRank(node, query: "becau"), .titleOrKeyword)
        XCTAssertNil(grammarSearchRank(node, query: "although"))
    }

    func testEmptyQueryHasNoRankButMatches() {
        XCTAssertNil(grammarSearchRank(nDesu, query: " "))
        XCTAssertEqual([nDesu].searched(for: " "), [nDesu])
    }

    func testRanksKeywordAboveHeadingAboveExample() {
        let example = point("example", en: "I stayed home because it rained.")
        let heading = point("heading", heading: "Giving a reason with because")
        let summary = point("summary", summary: "Says why, like because.")
        let keyword = point("keyword", keywords: ["because"])
        let ranked = [example, heading, summary, keyword].searched(for: "because")
        XCTAssertEqual(ranked.map(\.id), ["keyword", "summary", "heading", "example"])
    }

    func testRanksTitleAboveHeading() {
        let heading = point("heading", heading: "ので or から")
        let title = point("title", title: "〜ので")
        XCTAssertEqual([heading, title].searched(for: "ので").map(\.id), ["title", "heading"])
    }

    func testWholeKeywordRanksAbovePartOfAKeyword() {
        let mustNot = point("te-mo-ii", keywords: ["may", "must not"])
        let must = point("nakereba", keywords: ["must", "have to"])
        XCTAssertEqual([mustNot, must].searched(for: "must").map(\.id), ["nakereba", "te-mo-ii"])
    }

    func testTiesKeepTheirOrder() {
        let a = point("a", keywords: ["should"])
        let b = point("b", keywords: ["should"])
        XCTAssertEqual([a, b].searched(for: "should").map(\.id), ["a", "b"])
        XCTAssertEqual([b, a].searched(for: "should").map(\.id), ["b", "a"])
    }

    func testSearchedDropsNonMatches() {
        let a = point("a", keywords: ["while"])
        let b = point("b", keywords: ["because"])
        XCTAssertEqual([a, b].searched(for: "while").map(\.id), ["a"])
    }
}
