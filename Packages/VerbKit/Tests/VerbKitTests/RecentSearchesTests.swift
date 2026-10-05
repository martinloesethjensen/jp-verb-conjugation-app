import XCTest
@testable import VerbKit

final class RecentSearchesTests: XCTestCase {
    private func query(_ text: String, _ tokens: [WordBankToken] = []) -> WordBankQuery {
        WordBankQuery(text: text, tokens: tokens)
    }

    func testNewestFirstAndCappedAtTen() {
        var recent = RecentSearches(rawValue: nil)
        for n in 1...12 { recent.record(query("q\(n)")) }
        XCTAssertEqual(recent.items.count, 10)
        XCTAssertEqual(recent.items.first?.text, "q12")
        XCTAssertEqual(recent.items.last?.text, "q3")
    }

    func testARepeatMovesToTheTop() {
        var recent = RecentSearches(rawValue: nil)
        recent.record(query("おおきに", [.kind(.word)]))
        recent.record(query("thank you"))
        recent.record(query("オオキニ ", [.kind(.word)]))
        XCTAssertEqual(recent.items.map(\.text), ["オオキニ ", "thank you"])
    }

    func testDifferentTokensAreDifferentSearches() {
        var recent = RecentSearches(rawValue: nil)
        recent.record(query("x", [.kind(.word)]))
        recent.record(query("x", [.kind(.phrase)]))
        XCTAssertEqual(recent.items.count, 2)
    }

    func testEmptySearchesAreNotRecorded() {
        var recent = RecentSearches(rawValue: nil)
        recent.record(query("  "))
        XCTAssertEqual(recent.items, [])
    }

    func testRemoveClearAndRoundTrip() {
        var recent = RecentSearches(rawValue: nil)
        recent.record(query("a"))
        recent.record(query("b", [.unfiled]))
        XCTAssertEqual(RecentSearches(rawValue: recent.rawValue).items, recent.items)
        recent.remove(query("a"))
        XCTAssertEqual(recent.items.map(\.text), ["b"])
        recent.clear()
        XCTAssertEqual(recent.items, [])
    }

    func testCorruptDataLoadsEmpty() {
        XCTAssertEqual(RecentSearches(rawValue: Data("nope".utf8)).items, [])
    }
}

final class KanjiExtractionTests: XCTestCase {
    func testDistinctKanjiInFirstSeenOrder() {
        XCTAssertEqual(KanjiExtraction.kanji(in: ["頭が痛い", "頭痛", "おおきに"]), ["頭", "痛"])
    }

    func testKanaAndTheIterationMarkAreSkipped() {
        XCTAssertEqual(KanjiExtraction.kanji(in: ["時々", "ありがとう"]), ["時"])
    }
}
