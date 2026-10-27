import XCTest
@testable import VerbKit

final class CounterSteppingTests: XCTestCase {
    private func counter(extent: Int, extra: [Int] = []) -> Counter {
        var readings: [String: [String]] = ["1": ["いち"]]
        for value in 11...max(11, extent) where extent > 10 { readings[String(value)] = ["x"] }
        for value in extra { readings[String(value)] = ["x"] }
        return Counter(id: "c", counter: "分", reading: "ふん", meaning: "m", sound: "plain", symbol: "clock",
                       readings: readings, extent: extent, extra: extra)
    }

    func testStepsIntoTheRangeFromTen() {
        let minutes = counter(extent: 59, extra: [100])
        XCTAssertEqual(minutes.step(.n(10), by: 1), .n(11))
        XCTAssertEqual(minutes.step(.n(10), by: 10), .n(20))
        XCTAssertEqual(minutes.step(.what, by: 1), .n(11))
        XCTAssertEqual(minutes.step(.n(3), by: 1), .n(11))
    }

    func testCannotStepBelowTheFirst() {
        XCTAssertNil(counter(extent: 59).step(.n(11), by: -1))
        XCTAssertEqual(counter(extent: 59).step(.n(15), by: -10), .n(11))
    }

    func testStepsOntoTheRoundNumberAfterTheExtent() {
        let minutes = counter(extent: 59, extra: [100])
        XCTAssertEqual(minutes.step(.n(59), by: 1), .n(100))
        XCTAssertEqual(minutes.step(.n(50), by: 10), .n(100))
        XCTAssertEqual(minutes.step(.n(100), by: -1), .n(59))
    }

    func testYenSkipsNumbersTheDataDoesNotHave() {
        let yen = counter(extent: 99, extra: [100, 200, 300])
        XCTAssertEqual(yen.step(.n(100), by: 1), .n(200))
        XCTAssertEqual(yen.step(.n(200), by: -10), .n(100))
        XCTAssertEqual(yen.step(.n(99), by: 10), .n(200))
    }

    func testClampsAtTheEnds() {
        let minutes = counter(extent: 59)
        XCTAssertEqual(minutes.step(.n(55), by: 10), .n(59))
        XCTAssertNil(minutes.step(.n(59), by: 1))
        XCTAssertNil(minutes.step(.n(59), by: 10))
    }

    func testACounterWithoutExtendedNumbersNeverSteps() {
        let core = counter(extent: 10)
        XCTAssertNil(core.step(.n(10), by: 1))
        XCTAssertNil(core.step(.n(10), by: 10))
    }
}
