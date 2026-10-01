import XCTest
@testable import VerbKit

final class DailyPickTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let items = ["a", "b", "c", "d", "e", "f", "g"]

    private func date(_ day: Int, hour: Int = 15) -> Date {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = day; components.hour = hour
        return calendar.date(from: components)!
    }

    func testSameDayGivesSameElement() {
        XCTAssertEqual(
            DailyPick.element(of: items, on: date(5, hour: 1), calendar: calendar),
            DailyPick.element(of: items, on: date(5, hour: 23), calendar: calendar)
        )
    }

    func testConsecutiveDaysCycleThroughTheList() throws {
        let picks = try (1...7).map { try XCTUnwrap(DailyPick.element(of: items, on: date($0), calendar: calendar)) }
        XCTAssertEqual(Set(picks), Set(items))
        let eighth = try XCTUnwrap(DailyPick.element(of: items, on: date(8), calendar: calendar))
        XCTAssertEqual(eighth, picks[0])
    }

    func testDifferentCalendarsAgree() {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = calendar.timeZone
        for day in 1...7 {
            XCTAssertEqual(
                DailyPick.element(of: items, on: date(day), calendar: buddhist),
                DailyPick.element(of: items, on: date(day), calendar: calendar)
            )
        }
    }

    func testEmptyGivesNil() {
        XCTAssertNil(DailyPick.element(of: [Int](), on: date(1), calendar: calendar))
        var generator = SystemRandomNumberGenerator()
        XCTAssertNil(DailyPick.random(of: [Int](), using: &generator))
    }

    func testRandomComesFromTheList() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<20 {
            XCTAssertTrue(items.contains(DailyPick.random(of: items, using: &generator)!))
        }
    }

    func testWorksOnGrammarPoints() {
        let points = GrammarFixture.points
        XCTAssertNotNil(DailyPick.element(of: points, on: date(3), calendar: calendar))
    }
}
