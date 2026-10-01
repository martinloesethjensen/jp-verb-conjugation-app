import Foundation

/// Which verb a widget shows. Pure so it can be tested without WidgetKit.
public enum VerbPick {
    public static func verbOfTheDay(verbs: [Verb], on date: Date, calendar: Calendar = .current) -> Verb? {
        DailyPick.element(of: verbs, on: date, calendar: calendar)
    }

    public static func randomVerb(verbs: [Verb], using generator: inout some RandomNumberGenerator) -> Verb? {
        DailyPick.random(of: verbs, using: &generator)
    }
}
