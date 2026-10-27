import XCTest
@testable import VerbKit

final class ReviewStampTests: XCTestCase {
    private func counter(_ extra: String = "") -> Counter {
        let json = """
        {"id": "hon", "counter": "本", "reading": "ほん", "meaning": "m", "sound": "h-b", "symbol": "pencil",
         "readings": {"1": ["いっぽん"]}\(extra)}
        """
        return try! JSONDecoder().decode(Counter.self, from: Data(json.utf8))
    }

    private func point(_ extra: String = "") throws -> GrammarPoint {
        let json = """
        {"id": "n-desu", "title": "んです", "summary": "s", "usages": [], "attachment": [], "conjugations": [],
         "pitfalls": [], "related": []\(extra)}
        """
        return try JSONDecoder().decode(GrammarPoint.self, from: Data(json.utf8))
    }

    private let stamp = #", "review": {"by": "teacher", "on": "2026-10-24", "sha256": "abc"}"#

    func testCountersAndGrammarDecodeWithoutAStamp() throws {
        XCTAssertNil(counter().review)
        XCTAssertFalse(counter().isReviewed)
        XCTAssertNil(try point().review)
        XCTAssertFalse(try point().isReviewed)
    }

    func testCountersAndGrammarDecodeAStamp() throws {
        let expected = ReviewStamp(by: .teacher, on: "2026-10-24", sha256: "abc")
        XCTAssertEqual(counter(stamp).review, expected)
        XCTAssertTrue(counter(stamp).isReviewed)
        XCTAssertEqual(try point(stamp).review, expected)
        XCTAssertTrue(try point(stamp).isReviewed)
    }

    func testAnUnknownReviewerFailsToDecode() {
        let bad = #", "review": {"by": "nobody", "on": "2026-10-24", "sha256": "abc"}"#
        let json = """
        {"id": "hon", "counter": "本", "reading": "ほん", "meaning": "m", "sound": "h-b", "symbol": "pencil",
         "readings": {"1": ["いっぽん"]}\(bad)}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(Counter.self, from: Data(json.utf8)))
    }

    func testReviewerNames() {
        XCTAssertEqual(Reviewer.owner.displayName, "the owner")
        XCTAssertEqual(Reviewer.teacher.displayName, "a teacher")
    }

    func testSummaryCountsStampedItemsAndFindsTheLatestDate() throws {
        let older = ReviewStamp(by: .owner, on: "2026-10-20", sha256: "a")
        let newer = ReviewStamp(by: .teacher, on: "2026-10-24", sha256: "b")
        var a = counter(), b = counter(), c = counter()
        a.review = older
        b.review = newer
        c.review = nil
        let summary = ReviewSummary([a, b, c])
        XCTAssertEqual(summary, ReviewSummary(reviewed: 2, total: 3, latest: "2026-10-24"))
    }

    func testSummaryOfNothingAndOfUnreviewedItems() {
        XCTAssertEqual(ReviewSummary([Counter]()), ReviewSummary(reviewed: 0, total: 0, latest: nil))
        XCTAssertEqual(ReviewSummary([counter(), counter()]), ReviewSummary(reviewed: 0, total: 2, latest: nil))
    }
}
