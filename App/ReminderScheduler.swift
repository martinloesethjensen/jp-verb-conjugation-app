import Foundation
import UserNotifications
import VerbKit

/// Schedules the opt-in verb-of-the-day notifications and routes a tap on one to the verb page.
enum ReminderScheduler {
    static let enabledKey = "reminderEnabled"
    static let minutesKey = "reminderMinutes"
    static let defaultMinutes = 9 * 60
    static let reviewEnabledKey = "reviewReminderEnabled"
    static let reviewMinutesKey = "reviewReminderMinutes"
    static let streakEnabledKey = "streakReminderEnabled"
    static let streakMinutesKey = "streakReminderMinutes"
    /// Every request this app schedules; a refresh replaces them all.
    private static let identifierPrefixes = ["verb-of-the-day-", "review-", "streak-"]

    /// True when the user allowed notifications.
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// The Review and Streak keeper settings, with their defaults.
    static var studySettings: StudyReminderSettings {
        let defaults = UserDefaults.appGroup
        return StudyReminderSettings(
            reviewEnabled: defaults.bool(forKey: reviewEnabledKey),
            reviewMinutes: defaults.object(forKey: reviewMinutesKey) as? Int ?? StudyReminderSettings.reviewDefaultMinutes,
            streakEnabled: defaults.bool(forKey: streakEnabledKey),
            streakMinutes: defaults.object(forKey: streakMinutesKey) as? Int ?? StudyReminderSettings.streakDefaultMinutes
        )
    }

    /// Replaces our pending notifications: Verb of the day for the next few days (the verb widget's
    /// pool, the verbs at the visible levels), then Review and Streak keeper from the quiz history.
    /// Only removes them when the switches are off or notifications aren't allowed.
    static func refresh(verbs: [Verb], attempts: [QuizAttempt]) async {
        let center = UNUserNotificationCenter.current()
        let defaults = UserDefaults.appGroup
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { id in identifierPrefixes.contains { id.hasPrefix($0) } }
        )
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let visible = verbs.visible(in: LevelSettings.load())
        let pool = visible.isEmpty ? verbs : visible
        await scheduleStudyReminders(pool: pool, attempts: attempts, center: center)
        guard defaults.bool(forKey: enabledKey) else { return }
        let minutes = defaults.object(forKey: minutesKey) as? Int ?? defaultMinutes
        for item in DailyReminder.items(verbs: pool, now: .now, minutesAfterMidnight: minutes) {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.userInfo = ["url": item.url.absoluteString]
            let trigger = UNCalendarNotificationTrigger(dateMatching: item.fireDate, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger))
        }
    }
}

extension ReminderScheduler {
    /// Review ("8 forms to review") and Streak keeper, per `StudyReminderPlan`.
    fileprivate static func scheduleStudyReminders(pool: [Verb], attempts: [QuizAttempt], center: UNUserNotificationCenter) async {
        let settings = studySettings
        guard settings.reviewEnabled || settings.streakEnabled else { return }
        let forms = Set(QuizForm.all.map(\.id))
        let weakCount = QuizProgress(attempts: attempts)
            .weakPairs(among: Set(pool.map(\.id)))
            .filter { forms.contains($0.formID) }
            .count
        for item in StudyReminderPlan.items(attempts: attempts, weakCount: weakCount, settings: settings, now: .now) {
            let content = UNMutableNotificationContent()
            content.title = StudyReminderText.title(item.kind)
            content.body = StudyReminderText.body(item.kind)
            content.sound = .default
            content.userInfo = ["url": item.url.absoluteString]
            let trigger = UNCalendarNotificationTrigger(dateMatching: item.fireDate, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger))
        }
    }
}

/// The study reminders' wording (spec "Wording").
enum StudyReminderText {
    static func title(_ kind: StudyReminderKind) -> String {
        switch kind {
        case .review: "Time to review"
        case let .streak(days): days == 1 ? "Keep your streak going" : "Keep your \(days)-day streak"
        }
    }

    static func body(_ kind: StudyReminderKind) -> String {
        switch kind {
        case let .review(count): (count == 1 ? "1 form" : "\(count) forms") + " to review. Tap for a Weak spots quiz."
        case .streak: "One quick quiz keeps it going."
        }
    }
}

/// Receives taps on a reminder. `RootView` watches `pendingURL` and opens it like a widget link.
@MainActor
@Observable
final class ReminderRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderRouter()
    var pendingURL: URL?

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard let string = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: string) else { return }
        await MainActor.run { pendingURL = url }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
