import XCTest
@testable import VerbKit

final class SoundPatternsTests: XCTestCase {
    private func counter(
        _ id: String, sound: String, changed: [String] = [], six: String = "ろくほん", one: String = "いちほん"
    ) -> Counter {
        Counter(
            id: id, counter: id, reading: id, meaning: id, sound: sound, symbol: "pencil",
            readings: ["1": [one], "6": [six]], changed: changed
        )
    }

    private func nums(_ keys: [String]) -> [CounterNumber] { keys.compactMap(CounterNumber.init(key:)) }

    func testRowsAreInFixedOrderAndSkipEmptyClasses() {
        let rows = soundPatternRows(from: [
            counter("a", sound: "h-b"), counter("b", sound: "plain"), counter("c", sound: "k"),
        ])
        XCTAssertEqual(rows.map(\.sound), ["plain", "k", "h-b"])
    }

    func testMarkedIsTheIntersectionOfMembers() {
        let rows = soundPatternRows(from: [
            counter("a", sound: "k", changed: ["1", "6"]), counter("b", sound: "k", changed: ["1", "3", "6"]),
        ])
        XCTAssertEqual(rows[0].marked, [.n(1), .n(6)])
    }

    func testSingleCounterExceptionsAreNotMarked() {
        let rows = soundPatternRows(from: [
            counter("a", sound: "plain", changed: ["4"]), counter("b", sound: "plain"),
        ])
        XCTAssertEqual(rows[0].marked, [])
    }

    func testIrregularRowIsFlagged() {
        let rows = soundPatternRows(from: [counter("a", sound: "irregular")])
        XCTAssertTrue(rows[0].isIrregular)
        XCTAssertEqual(rows[0].marked, [])
    }

    func testStemForSixIsRokkuAcrossKAndHRows() {
        let rows = soundPatternRows(from: [
            counter("k", sound: "k", changed: ["6"], six: "ろっこ"),
            counter("b", sound: "h-b", changed: ["6"], six: "ろっぽん"),
            counter("p", sound: "h-p", changed: ["6"], six: "ろっぷん"),
        ])
        XCTAssertEqual(soundPatternStem(for: .n(6), in: rows), "ろっ")
    }

    func testNoStemWhenNothingSharedOrOnlyOneRow() {
        let three = { (r: String) in ["3": [r]] }
        let b = Counter(id: "b", counter: "b", reading: "b", meaning: "b", sound: "h-b", symbol: "x",
                        readings: three("さんぼん"), changed: ["3"])
        let p = Counter(id: "p", counter: "p", reading: "p", meaning: "p", sound: "h-p", symbol: "x",
                        readings: ["3": ["さんぷん"], "4": ["よんぷん"]], changed: ["3", "4"])
        let rows = soundPatternRows(from: [b, p])
        XCTAssertNil(soundPatternStem(for: .n(3), in: rows))
        XCTAssertNil(soundPatternStem(for: .n(4), in: rows))
    }

    func testRealDataPatterns() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("data/counters.json"))
        let file = try JSONDecoder().decode(CountersDataFile.self, from: data)
        let rows = soundPatternRows(from: file.counters)
        func marked(_ sound: String) throws -> [CounterNumber] {
            try XCTUnwrap(rows.first { $0.sound == sound }).marked
        }
        XCTAssertEqual(try marked("plain"), [])
        XCTAssertEqual(try marked("k"), nums(["1", "6", "8", "10"]))
        XCTAssertEqual(try marked("s"), nums(["1", "8", "10"]))
        XCTAssertEqual(try marked("h-b"), nums(["1", "3", "6", "8", "10", "what"]))
        XCTAssertEqual(try marked("h-p"), nums(["1", "3", "4", "6", "8", "10", "what"]))
        XCTAssertEqual(soundPatternStem(for: .n(6), in: rows), "ろっ")
    }
}
