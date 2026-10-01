import SwiftData
import SwiftUI
import VerbKit
import WidgetKit

/// Reads the shared store; the widget never writes it.
@MainActor
enum GrammarLoader {
    static func points() -> [GrammarPoint] {
        guard let container = try? VerbModelContainer.make() else { return [] }
        let persisting = SwiftDataGrammarPersisting(modelContext: ModelContext(container))
        return (try? persisting.loadAllGrammarPoints()) ?? []
    }
}

struct GrammarEntry: TimelineEntry {
    let date: Date
    /// nil while the app has not downloaded any data yet.
    let point: GrammarPoint?
}

struct GrammarProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> GrammarEntry {
        GrammarEntry(date: .now, point: .sample)
    }

    func snapshot(for configuration: GrammarWidgetIntent, in context: Context) async -> GrammarEntry {
        GrammarEntry(date: .now, point: await choose(for: configuration, at: .now))
    }

    func timeline(for configuration: GrammarWidgetIntent, in context: Context) async -> Timeline<GrammarEntry> {
        let now = Date()
        let entry = GrammarEntry(date: now, point: await choose(for: configuration, at: now))
        let calendar = Calendar.current
        switch configuration.mode {
        case .lessonOfTheDay:
            let midnight = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) ?? now.addingTimeInterval(3600)
            let nextMidnight = calendar.nextDate(after: midnight, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) ?? midnight.addingTimeInterval(24 * 3600)
            // The second entry lands exactly at midnight with the next day's lesson.
            let tomorrow = GrammarEntry(date: midnight, point: await choose(for: configuration, at: midnight))
            return Timeline(entries: [entry, tomorrow], policy: .after(nextMidnight))
        case .random:
            return Timeline(entries: [entry], policy: .after(now.addingTimeInterval(3 * 3600)))
        case .pick:
            return Timeline(entries: [entry], policy: .never)
        }
    }

    @MainActor
    private func choose(for configuration: GrammarWidgetIntent, at date: Date) -> GrammarPoint? {
        let allPoints = GrammarLoader.points()
        // Day and random picks use the visible levels; never fall back to the empty state because of levels.
        let visible = allPoints.visible(in: LevelSettings.load())
        let points = visible.isEmpty ? allPoints : visible
        switch configuration.mode {
        case .lessonOfTheDay:
            return DailyPick.element(of: points, on: date)
        case .random:
            var generator = SystemRandomNumberGenerator()
            return DailyPick.random(of: points, using: &generator)
        case .pick:
            if let id = configuration.lesson?.id, let point = allPoints.first(where: { $0.id == id }) {
                return point
            }
            return DailyPick.element(of: points, on: date)
        }
    }
}

struct GrammarRuleWidget: Widget {
    let kind = "GrammarRuleWidget"

    // The Lock Screen (accessory) families do not exist on macOS.
    #if os(iOS)
    private static let families: [WidgetFamily] = [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline]
    #else
    private static let families: [WidgetFamily] = [.systemSmall, .systemMedium]
    #endif

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: GrammarWidgetIntent.self, provider: GrammarProvider()) { entry in
            GrammarWidgetView(entry: entry)
        }
        .configurationDisplayName("Grammar Rule")
        .description("A grammar lesson from Verb Table, on your Home or Lock Screen.")
        .supportedFamilies(Self.families)
    }
}
