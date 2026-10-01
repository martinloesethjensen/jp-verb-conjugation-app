import Foundation

/// Which verb a widget shows. Pure so it can be tested without WidgetKit.
public enum VerbPick {
    /// The same verb all day and on every device: the local calendar day's number
    /// modulo the verb count, over the stored verb order. The day number is taken from the
    /// local year/month/day, counted in UTC, because `ordinality(of: .day, in: .era)` is
    /// not stable within a local day on current SDKs.
    public static func verbOfTheDay(verbs: [Verb], on date: Date, calendar: Calendar = .current) -> Verb? {
        guard !verbs.isEmpty else { return nil }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let midnight = utc.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day)) ?? date
        let day = Int((midnight.timeIntervalSince1970 / 86_400).rounded(.down))
        return verbs[((day % verbs.count) + verbs.count) % verbs.count]
    }

    public static func randomVerb(verbs: [Verb], using generator: inout some RandomNumberGenerator) -> Verb? {
        verbs.randomElement(using: &generator)
    }
}
