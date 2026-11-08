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

    func testANativeStampWithANameDecodes() throws {
        let native = #", "review": {"by": "native", "on": "2026-11-07", "sha256": "abc", "name": "Aiko"}"#
        let review = try XCTUnwrap(counter(native).review)
        XCTAssertEqual(review.by, .native)
        XCTAssertEqual(review.name, "Aiko")
        XCTAssertEqual(review.by.displayName, "a native speaker")
        XCTAssertNil(counter(stamp).review?.name)
    }

    // MARK: Verbs, examples and words (plan 7)

    private func dataURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // VerbKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // VerbKit
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("data/\(name).json")
    }

    /// The first published verb, with `extra` added to it and `example` to its first example.
    private func verb(_ extra: String = "", example: String = "") throws -> Verb {
        let file = try JSONSerialization.jsonObject(with: Data(contentsOf: dataURL("verbs"))) as! [String: Any]
        var json = (file["verbs"] as! [[String: Any]])[0]
        var examples = json["examples"] as! [[String: Any]]
        examples[0] = try stamped(examples[0], example)
        json["examples"] = examples
        json = try stamped(json, extra)
        return try JSONDecoder().decode(Verb.self, from: JSONSerialization.data(withJSONObject: json))
    }

    /// `object` with the `, "review": {…}` fragment (or nothing) merged in.
    private func stamped(_ object: [String: Any], _ fragment: String) throws -> [String: Any] {
        guard !fragment.isEmpty else { return object }
        let extra = try JSONSerialization.jsonObject(with: Data("{\(fragment.dropFirst())}".utf8)) as! [String: Any]
        return object.merging(extra) { _, new in new }
    }

    func testVerbsExamplesAndWordsDecodeWithoutAStamp() throws {
        let verbs = try JSONDecoder().decode(VerbDataFile.self, from: Data(contentsOf: dataURL("verbs"))).verbs
        XCTAssertFalse(verbs.isEmpty)
        XCTAssertEqual(ReviewSummary(verbs).total, verbs.count)
        XCTAssertEqual(ReviewSummary(verbs.flatMap(\.examples)).total, verbs.reduce(0) { $0 + $1.examples.count })
        let words = try JSONDecoder().decode(WordsDataFile.self, from: Data(contentsOf: dataURL("words"))).words
        XCTAssertFalse(words.isEmpty)
        XCTAssertEqual(ReviewSummary(words).total, words.count)
    }

    func testAVerbAnExampleAndAWordDecodeAStamp() throws {
        let expected = ReviewStamp(by: .teacher, on: "2026-10-24", sha256: "abc")
        let stamped = try verb(stamp, example: stamp)
        XCTAssertEqual(stamped.review, expected)
        XCTAssertTrue(stamped.isReviewed)
        XCTAssertEqual(stamped.examples[0].review, expected)
        XCTAssertNil(try verb().review)
        XCTAssertNil(try verb().examples[0].review)
        XCTAssertEqual(Word(stamped).review, expected)
        let words = """
        {"version": "1", "description": "d", "words": [{"class": "i-adjective", "dict": "たかい", "meaning": "tall",
         "forms": {"te": "たかくて"}\(stamp)}]}
        """
        let word = try JSONDecoder().decode(WordsDataFile.self, from: Data(words.utf8)).words[0]
        XCTAssertEqual(word.review, expected)
    }

    func testExampleStampSurvivesAnEncodeRoundTrip() throws {
        let stamped = try verb(stamp, example: stamp)
        let again = try JSONDecoder().decode(Verb.self, from: JSONEncoder().encode(stamped))
        XCTAssertEqual(again.review, stamped.review)
        XCTAssertEqual(again.examples[0].review, stamped.examples[0].review)
        let plain = String(decoding: try JSONEncoder().encode(try verb().examples[0]), as: UTF8.self)
        XCTAssertFalse(plain.contains("review"))
    }

    func testStoredWordKeepsItsStamp() throws {
        var word = Word(wordClass: .iAdjective, dict: "たかい", meaning: "tall", description: "", forms: Conjugations())
        word.review = ReviewStamp(by: .native, on: "2026-11-08", sha256: "abc", name: "Aiko")
        let stored = try JSONDecoder().decode(StoredWord.self, from: JSONEncoder().encode(StoredWord(word)))
        XCTAssertEqual(stored.word.review, word.review)
    }

    func testSummaryOfVerbExamples() throws {
        let verbs = [try verb(example: stamp), try verb()]
        let total = verbs.reduce(0) { $0 + $1.examples.count }
        XCTAssertEqual(ReviewSummary(verbs.flatMap(\.examples)), ReviewSummary(reviewed: 1, total: total, latest: "2026-10-24"))
    }
}
