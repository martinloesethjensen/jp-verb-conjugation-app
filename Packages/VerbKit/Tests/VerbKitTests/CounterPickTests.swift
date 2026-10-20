import XCTest
@testable import VerbKit

final class CounterPickTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func counter(_ id: String, _ level: JLPTLevel) -> Counter {
        Counter(id: id, counter: id, reading: id, meaning: id, jlpt: level, sound: "plain", symbol: "x", readings: [:])
    }

    private func date(_ day: Int, hour: Int = 15) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    func testSameDayGivesSameCounter() {
        let all = ["a", "b", "c"].map { counter($0, .n5) }
        XCTAssertEqual(
            counterOfTheDay(from: all, levels: LevelSettings(), on: date(5, hour: 1), calendar: calendar)?.id,
            counterOfTheDay(from: all, levels: LevelSettings(), on: date(5, hour: 23), calendar: calendar)?.id
        )
    }

    func testHiddenLevelsAreSkipped() {
        let all = [counter("a", .n5), counter("b", .n4), counter("c", .n5)]
        for day in 1...7 {
            let pick = counterOfTheDay(from: all, levels: LevelSettings(hidden: [.n5]), on: date(day), calendar: calendar)
            XCTAssertEqual(pick?.id, "b", "day \(day)")
        }
    }

    func testFallsBackToAllWhenLevelsHideEverything() {
        let all = [counter("a", .n5), counter("b", .n5)]
        XCTAssertNotNil(counterOfTheDay(from: all, levels: LevelSettings(hidden: [.n5]), on: date(3), calendar: calendar))
    }

    func testEmptyGivesNil() {
        XCTAssertNil(counterOfTheDay(from: [], levels: LevelSettings(), on: date(1), calendar: calendar))
    }
}
