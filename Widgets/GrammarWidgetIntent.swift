import AppIntents
import VerbKit
import WidgetKit

enum GrammarWidgetMode: String, AppEnum {
    case lessonOfTheDay, random, pick

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Show"
    static let caseDisplayRepresentations: [GrammarWidgetMode: DisplayRepresentation] = [
        .lessonOfTheDay: "Lesson of the day",
        .random: "Random lesson",
        .pick: "Pick a lesson",
    ]
}

struct GrammarChoice: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Lesson"
    static let defaultQuery = GrammarChoiceQuery()

    var id: String   // GrammarPoint.id
    var title: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct GrammarChoiceQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [GrammarChoice] {
        let all = await GrammarLoader.points()
        return all.filter { identifiers.contains($0.id) }.map(GrammarChoice.init)
    }
    func suggestedEntities() async throws -> [GrammarChoice] {
        await GrammarLoader.points().map(GrammarChoice.init)
    }
    func entities(matching string: String) async throws -> [GrammarChoice] {
        await GrammarLoader.points().filter { matchesGrammarSearch($0, query: string) }.map(GrammarChoice.init)
    }
}

extension GrammarChoice {
    init(_ point: GrammarPoint) {
        self.init(id: point.id, title: point.title)
    }
}

struct GrammarWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Grammar Rule"
    static let description = IntentDescription("Choose which grammar lesson the widget shows.")

    @Parameter(title: "Show", default: .lessonOfTheDay)
    var mode: GrammarWidgetMode

    @Parameter(title: "Lesson")
    var lesson: GrammarChoice?

    static var parameterSummary: some ParameterSummary {
        When(\.$mode, .equalTo, GrammarWidgetMode.pick) {
            Summary("\(\.$mode) \(\.$lesson)")
        } otherwise: {
            Summary("\(\.$mode)")
        }
    }
}
