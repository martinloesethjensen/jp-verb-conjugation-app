import Foundation

/// The counter the widget shows on `date`. Hidden levels are skipped; if they hide everything the
/// pick falls back to all counters, so the widget never shows its empty state because of settings.
public func counterOfTheDay(
    from counters: [Counter], levels: LevelSettings, on date: Date, calendar: Calendar = .current
) -> Counter? {
    let visible = counters.visible(in: levels)
    return DailyPick.element(of: visible.isEmpty ? counters : visible, on: date, calendar: calendar)
}
