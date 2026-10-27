import XCTest
@testable import VerbKit

final class WordBankDatesTests: XCTestCase {
    /// Noon in the current zone, so the expected day cannot roll over.
    private func date(year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0, second: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        )!
    }

    func testDayIsAFixedYearMonthDayStamp() {
        XCTAssertEqual(WordBankDates.day(date(year: 2026, month: 3, day: 9)), "2026-03-09")
    }

    func testTimestampAddsTheTimeSoBackupsStayDistinct() {
        let value = date(year: 2026, month: 3, day: 9, hour: 14, minute: 5, second: 7)
        XCTAssertEqual(WordBankDates.timestamp(value), "2026-03-09 14.05.07")
    }
}
