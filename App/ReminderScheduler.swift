import Foundation
import UserNotifications
import VerbKit

/// Schedules the opt-in verb-of-the-day notifications and routes a tap on one to the verb page.
enum ReminderScheduler {
    static let enabledKey = "reminderEnabled"
    static let minutesKey = "reminderMinutes"
    static let defaultMinutes = 9 * 60
    private static let identifierPrefix = "verb-of-the-day-"

    /// True when the user allowed notifications.
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Replaces our pending notifications with the next few days, or only removes them when the
    /// reminder is off. Uses the same pool as the verb widget: the verbs at the visible levels.
    static func refresh(verbs: [Verb]) async {
        let center = UNUserNotificationCenter.current()
        let defaults = UserDefaults.appGroup
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        )
        guard defaults.bool(forKey: enabledKey) else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let visible = verbs.visible(in: LevelSettings.load())
        let pool = visible.isEmpty ? verbs : visible
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
