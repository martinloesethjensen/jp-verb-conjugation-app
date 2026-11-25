import Foundation

/// The Review and Streak keeper reminder switches and times (minutes after midnight).
public struct StudyReminderSettings: Equatable, Sendable {
    public static let reviewDefaultMinutes = 18 * 60
    public static let streakDefaultMinutes = 20 * 60

    public var reviewEnabled: Bool
    public var reviewMinutes: Int
    public var streakEnabled: Bool
    public var streakMinutes: Int

    public init(reviewEnabled: Bool, reviewMinutes: Int, streakEnabled: Bool, streakMinutes: Int) {
        self.reviewEnabled = reviewEnabled
        self.reviewMinutes = reviewMinutes
        self.streakEnabled = streakEnabled
        self.streakMinutes = streakMinutes
    }
}

/// What a study reminder says, without its wording (that lives in App).
public enum StudyReminderKind: Equatable, Sendable {
    /// "8 forms to review": the weak (verb, form) pairs at the visible levels.
    case review(count: Int)
    /// "Keep your 5-day streak".
    case streak(days: Int)
}

public struct StudyReminderItem: Equatable, Sendable {
    public let kind: StudyReminderKind
    /// Year, month, day, hour and minute of the delivery, in the calendar's time zone.
    public let fireDate: DateComponents
    public let identifier: String
    /// What a tap opens: a Weak spots quiz for a review, a quiz on everything for a streak.
    public let url: URL
}

/// Which Review and Streak keeper notifications to schedule (spec:
/// `docs/superpowers/specs/2026-11-25-study-reminders-design.md`). Pure, so it is tested without
/// UserNotifications; the app calls it whenever it is active, a quiz answer is recorded or a
/// setting changes, and replaces what is pending.
///
/// - Review: each of the next `days` days while `weakCount > 0`, skipping a day already practised
///   and the day of the streak keeper, so at most two of our notifications arrive on one day.
/// - Streak keeper: one at most. Today when today has no answer yet and the streak ended
///   yesterday; tomorrow when today is practised. A streak that broke gets none.
/// "Practised" means an answered (not timed-out) quiz question, as for the streak itself.
public enum StudyReminderPlan {
    public static func items(
        attempts: [QuizAttempt], weakCount: Int, settings: StudyReminderSettings, now: Date,
        days: Int = DailyReminder.daysAhead, calendar: Calendar = .current
    ) -> [StudyReminderItem] {
        let today = calendar.startOfDay(for: now)
        let practisedToday = attempts.contains { $0.outcome.isAnswered && calendar.isDate($0.date, inSameDayAs: now) }
        let streak = QuizProgress(attempts: attempts, calendar: calendar, now: now).currentStreak

        var items: [StudyReminderItem] = []
        var streakDay: Date?
        if settings.streakEnabled, streak > 0 {
            let day = practisedToday ? calendar.date(byAdding: .day, value: 1, to: today) : today
            if let day, let fire = fire(on: day, minutes: settings.streakMinutes, calendar: calendar), fire > now {
                streakDay = day
                items.append(item(.streak(days: streak), fire: fire, prefix: "streak", url: QuizLink(topic: nil).url, calendar: calendar))
            }
        }
        if settings.reviewEnabled, weakCount > 0 {
            for offset in 0..<max(days, 0) {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      !(offset == 0 && practisedToday), day != streakDay,
                      let fire = fire(on: day, minutes: settings.reviewMinutes, calendar: calendar), fire > now
                else { continue }
                items.append(item(.review(count: weakCount), fire: fire, prefix: "review", url: QuizLink.weakSpots.url, calendar: calendar))
            }
        }
        return items
    }

    private static func fire(on day: Date, minutes: Int, calendar: Calendar) -> Date? {
        let clamped = DailyReminder.clampedMinutes(minutes)
        return calendar.date(bySettingHour: clamped / 60, minute: clamped % 60, second: 0, of: day)
    }

    private static func item(_ kind: StudyReminderKind, fire: Date, prefix: String, url: URL, calendar: Calendar) -> StudyReminderItem {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let id = String(format: "%@-%04d%02d%02d", prefix, parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return StudyReminderItem(kind: kind, fireDate: parts, identifier: id, url: url)
    }
}
