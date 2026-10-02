import Foundation

/// The verb-of-the-day notifications to schedule. Pure so it can be tested without
/// UserNotifications. A repeating notification cannot change its text, so the app schedules one
/// per upcoming day and refreshes the list whenever it is active.
public enum DailyReminder {
    /// How many days ahead notifications are scheduled (iOS keeps at most 64 pending).
    public static let daysAhead = 14

    public struct Item: Equatable, Sendable {
        /// Year, month, day, hour and minute of the delivery, in the calendar's time zone.
        public let fireDate: DateComponents
        public let identifier: String
        public let title: String
        public let body: String
        /// Opens the verb page: `verbtable://verb/<id>`.
        public let url: URL
    }

    /// Settings value: minutes after midnight, clamped to a valid time of day.
    public static func clampedMinutes(_ minutes: Int) -> Int { min(max(minutes, 0), 24 * 60 - 1) }

    /// One item per day from today, picked the way the widget picks the verb of the day. A time that
    /// has already passed today is skipped. Empty when `verbs` is empty.
    public static func items(
        verbs: [Verb], now: Date, minutesAfterMidnight: Int,
        days: Int = daysAhead, calendar: Calendar = .current
    ) -> [Item] {
        guard !verbs.isEmpty, days > 0 else { return [] }
        let minutes = clampedMinutes(minutesAfterMidnight)
        let startOfToday = calendar.startOfDay(for: now)
        var items: [Item] = []
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday),
                  let fire = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day),
                  fire > now,
                  let verb = VerbPick.verbOfTheDay(verbs: verbs, on: fire, calendar: calendar)
            else { continue }
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let written = verb.kanji ?? verb.dict
            items.append(Item(
                fireDate: parts,
                identifier: String(format: "verb-of-the-day-%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0),
                title: "Verb of the day: \(written)",
                body: verb.kanji == nil ? verb.meaning : "\(verb.dict) · \(verb.meaning)",
                url: Route.verb(verb.id).url
            ))
        }
        return items
    }
}
