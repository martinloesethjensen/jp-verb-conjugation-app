import Foundation

/// Which item a widget shows. Pure so it can be tested without WidgetKit.
public enum DailyPick {
    /// The same element all day and on every device. The day number is Gregorian-day based and
    /// independent of the device calendar: the local year/month/day are read with a Gregorian
    /// calendar that only borrows the caller's time zone, converted to days since 1970-01-01
    /// arithmetically, then taken modulo the item count over the stored item order.
    /// (`calendar.ordinality(of: .day, in: .era)` was observed to differ between 01:00 and
    /// 23:00 of the same local day in Europe/Copenhagen, so it is not used.)
    public static func element<T>(of items: [T], on date: Date, calendar: Calendar = .current) -> T? {
        guard !items.isEmpty else { return nil }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let parts = gregorian.dateComponents([.year, .month, .day], from: date)
        let day = daysSinceEpoch(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
        return items[((day % items.count) + items.count) % items.count]
    }

    public static func random<T>(of items: [T], using generator: inout some RandomNumberGenerator) -> T? {
        items.randomElement(using: &generator)
    }

    /// Days from 1970-01-01 to the proleptic Gregorian date (Hinnant's days_from_civil).
    private static func daysSinceEpoch(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }
}
