import SwiftData
import SwiftUI
import VerbKit
import WidgetKit

/// Reads the shared store; the widget never writes it.
@MainActor
enum VerbLoader {
    static func verbs() -> [Verb] {
        guard let container = try? VerbModelContainer.make() else { return [] }
        let persisting = SwiftDataVerbPersisting(modelContext: ModelContext(container))
        return (try? persisting.loadAllVerbs()) ?? []
    }
}

struct VerbEntry: TimelineEntry {
    let date: Date
    /// nil while the app has not downloaded any verbs yet.
    let verb: Verb?
}

struct VerbProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> VerbEntry {
        VerbEntry(date: .now, verb: nil)
    }

    func snapshot(for configuration: VerbWidgetIntent, in context: Context) async -> VerbEntry {
        VerbEntry(date: .now, verb: await choose(for: configuration, at: .now))
    }

    func timeline(for configuration: VerbWidgetIntent, in context: Context) async -> Timeline<VerbEntry> {
        let now = Date()
        let entry = VerbEntry(date: now, verb: await choose(for: configuration, at: now))
        let calendar = Calendar.current
        switch configuration.mode {
        case .verbOfTheDay:
            let midnight = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) ?? now.addingTimeInterval(3600)
            return Timeline(entries: [entry], policy: .after(midnight))
        case .random:
            return Timeline(entries: [entry], policy: .after(now.addingTimeInterval(3 * 3600)))
        case .pick:
            return Timeline(entries: [entry], policy: .never)
        }
    }

    @MainActor
    private func choose(for configuration: VerbWidgetIntent, at date: Date) -> Verb? {
        let verbs = VerbLoader.verbs()
        switch configuration.mode {
        case .verbOfTheDay:
            return VerbPick.verbOfTheDay(verbs: verbs, on: date)
        case .random:
            var generator = SystemRandomNumberGenerator()
            return VerbPick.randomVerb(verbs: verbs, using: &generator)
        case .pick:
            if let id = configuration.verb?.id, let verb = verbs.first(where: { $0.id == id }) {
                return verb
            }
            return VerbPick.verbOfTheDay(verbs: verbs, on: date)
        }
    }
}

struct VerbTableWidget: Widget {
    let kind = "VerbTableWidget"

    // The Lock Screen (accessory) families do not exist on macOS.
    #if os(iOS)
    private static let families: [WidgetFamily] = [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline]
    #else
    private static let families: [WidgetFamily] = [.systemSmall, .systemMedium]
    #endif

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: VerbWidgetIntent.self, provider: VerbProvider()) { entry in
            VerbWidgetView(entry: entry)
        }
        .configurationDisplayName("Verb Table")
        .description("A verb and its key forms, from your Home or Lock Screen.")
        .supportedFamilies(Self.families)
    }
}
