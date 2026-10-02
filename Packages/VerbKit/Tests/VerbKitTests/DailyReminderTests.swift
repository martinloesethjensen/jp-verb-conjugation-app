import XCTest
@testable import VerbKit

final class DailyReminderTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Copenhagen")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func verbs() throws -> [Verb] { try RealVerbs.load() }

    func testOneItemPerDayStartingToday() throws {
        let items = DailyReminder.items(verbs: try verbs(), now: date(2, 7), minutesAfterMidnight: 9 * 60, days: 3, calendar: calendar)
        XCTAssertEqual(items.map(\.fireDate.day), [2, 3, 4])
        XCTAssertEqual(Set(items.map(\.identifier)).count, 3)
        XCTAssertTrue(items.allSatisfy { $0.fireDate.hour == 9 && $0.fireDate.minute == 0 })
    }

    func testTodayIsSkippedWhenTheTimeHasPassed() throws {
        let items = DailyReminder.items(verbs: try verbs(), now: date(2, 10), minutesAfterMidnight: 9 * 60, days: 3, calendar: calendar)
        XCTAssertEqual(items.map(\.fireDate.day), [3, 4])
    }

    func testPicksTheSameVerbAsTheWidget() throws {
        let verbs = try verbs()
        let item = try XCTUnwrap(DailyReminder.items(verbs: verbs, now: date(2, 7), minutesAfterMidnight: 9 * 60, days: 1, calendar: calendar).first)
        let expected = try XCTUnwrap(VerbPick.verbOfTheDay(verbs: verbs, on: date(2, 9), calendar: calendar))
        XCTAssertEqual(Route(url: item.url), .verb(expected.id))
        XCTAssertTrue(item.title.contains(expected.kanji ?? expected.dict))
    }

    func testEmptyVerbsGiveNoItems() {
        XCTAssertTrue(DailyReminder.items(verbs: [], now: date(2, 7), minutesAfterMidnight: 540, calendar: calendar).isEmpty)
    }

    func testMinutesAreClamped() {
        XCTAssertEqual(DailyReminder.clampedMinutes(-5), 0)
        XCTAssertEqual(DailyReminder.clampedMinutes(5000), 1439)
    }
}
