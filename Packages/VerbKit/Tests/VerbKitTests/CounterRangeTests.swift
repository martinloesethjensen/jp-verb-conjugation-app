import XCTest
@testable import VerbKit

final class CounterRangeTests: XCTestCase {
    private func counter(extent: Int = 10, extra: [Int] = []) -> Counter {
        var readings: [String: [String]] = ["1": ["いち"]]
        if extent > 10 { for value in 11...extent { readings[String(value)] = ["x"] } }
        for value in extra { readings[String(value)] = ["x"] }
        return Counter(id: "c\(extent)\(extra.count)", counter: "分", reading: "ふん", meaning: "m", sound: "plain",
                       symbol: "clock", readings: readings, extent: extent, extra: extra)
    }

    func testCoreOnlyCountersHaveOnlyTheCoreRange() {
        XCTAssertEqual(CounterRange.available(for: [counter(), counter()]), [.core])
    }

    func testRangesFollowWhatTheCountersHave() {
        XCTAssertEqual(CounterRange.available(for: [counter(), counter(extent: 59)]),
                       [.core, .elevenToTwenty, .tens])
        XCTAssertEqual(CounterRange.available(for: [counter(extent: 24)]), [.core, .elevenToTwenty])
        XCTAssertEqual(CounterRange.available(for: [counter(extent: 59, extra: [100])]),
                       [.core, .elevenToTwenty, .tens, .hundredsUp])
    }

    func testTitles() {
        XCTAssertEqual(CounterRange.allCases.map(\.title), ["1–10", "11–20", "30–90", "100+"])
    }

    func testRowsAreTheNumbersSomeCounterHas() {
        let minutes = counter(extent: 59)
        XCTAssertEqual(CounterRange.core.numbers(for: [minutes]), CounterNumber.allCases)
        XCTAssertEqual(CounterRange.elevenToTwenty.numbers(for: [minutes]), (11...20).map(CounterNumber.n))
        XCTAssertEqual(CounterRange.tens.numbers(for: [minutes]), [30, 40, 50].map(CounterNumber.n))
        XCTAssertEqual(CounterRange.hundredsUp.numbers(for: [minutes]), [])
    }

    func testYenHasTheRoundNumbersAbove100() {
        let yen = counter(extent: 99, extra: [100, 200, 3000, 10000])
        XCTAssertEqual(CounterRange.hundredsUp.numbers(for: [yen, counter(extent: 59, extra: [100])]),
                       [100, 200, 3000, 10000].map(CounterNumber.n))
        XCTAssertEqual(CounterRange.tens.numbers(for: [yen]), (3...9).map { CounterNumber.n($0 * 10) })
    }
}
