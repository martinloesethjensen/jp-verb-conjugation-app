import SwiftData
import SwiftUI
import VerbKit
import WidgetKit

/// Reads the shared store; the widget never writes it.
@MainActor
enum CounterLoader {
    static func counters() -> [Counter] {
        guard let container = try? VerbModelContainer.make() else { return [] }
        let persisting = SwiftDataCountersPersisting(modelContext: ModelContext(container))
        return (try? persisting.loadCounters())?.counters ?? []
    }
}

struct CounterEntry: TimelineEntry {
    let date: Date
    /// nil while the app has not downloaded any counters yet.
    let counter: Counter?
}

extension Counter {
    static let widgetSample = Counter(
        id: "hon", counter: "本", reading: "ほん", meaning: "long, thin things", sound: "h-b", symbol: "pencil",
        readings: [
            "1": ["いっぽん"], "2": ["にほん"], "3": ["さんぼん"], "4": ["よんほん"], "5": ["ごほん"],
            "6": ["ろっぽん"], "7": ["ななほん"], "8": ["はっぽん"], "9": ["きゅうほん"], "10": ["じゅっぽん"],
            "what": ["なんぼん"],
        ],
        changed: ["1", "3", "6", "8", "10", "what"]
    )
}

struct CounterProvider: TimelineProvider {
    func placeholder(in context: Context) -> CounterEntry {
        CounterEntry(date: .now, counter: .widgetSample)
    }

    func getSnapshot(in context: Context, completion: @escaping (CounterEntry) -> Void) {
        Task { @MainActor in completion(CounterEntry(date: .now, counter: choose(at: .now))) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CounterEntry>) -> Void) {
        Task { @MainActor in
            let now = Date()
            let calendar = Calendar.current
            let midnight = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) ?? now.addingTimeInterval(3600)
            let nextMidnight = calendar.nextDate(after: midnight, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) ?? midnight.addingTimeInterval(24 * 3600)
            // The second entry lands exactly at midnight with the next day's counter.
            let entries = [
                CounterEntry(date: now, counter: choose(at: now)),
                CounterEntry(date: midnight, counter: choose(at: midnight)),
            ]
            completion(Timeline(entries: entries, policy: .after(nextMidnight)))
        }
    }

    @MainActor
    private func choose(at date: Date) -> Counter? {
        counterOfTheDay(from: CounterLoader.counters(), levels: LevelSettings.load(), on: date)
    }
}

struct CounterOfTheDayWidget: Widget {
    let kind = "CounterOfTheDayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CounterProvider()) { entry in
            CounterWidgetView(entry: entry)
        }
        .configurationDisplayName("Counter of the Day")
        .description("A counter and all its readings, from Verb Table.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
