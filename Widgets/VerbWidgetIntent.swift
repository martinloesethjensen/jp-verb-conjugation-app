import AppIntents
import VerbKit
import WidgetKit

enum VerbWidgetMode: String, AppEnum {
    case verbOfTheDay, random, pick

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Show"
    static let caseDisplayRepresentations: [VerbWidgetMode: DisplayRepresentation] = [
        .verbOfTheDay: "Verb of the day",
        .random: "Random verb",
        .pick: "Pick a verb",
    ]
}

struct VerbChoice: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Verb"
    static let defaultQuery = VerbChoiceQuery()

    var id: String   // Verb.id (the dictionary form)
    var title: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct VerbChoiceQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [VerbChoice] {
        let all = await VerbLoader.verbs()
        return all.filter { identifiers.contains($0.id) }.map(VerbChoice.init)
    }
    func suggestedEntities() async throws -> [VerbChoice] {
        await VerbLoader.verbs().map(VerbChoice.init)
    }
    func entities(matching string: String) async throws -> [VerbChoice] {
        await VerbLoader.verbs().filter { matchesSearch($0, query: string) }.map(VerbChoice.init)
    }
}

extension VerbChoice {
    init(_ verb: Verb) {
        self.init(id: verb.id, title: verb.kanji.map { "\(verb.dict) (\($0))" } ?? verb.dict)
    }
}

struct VerbWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Verb"
    static let description = IntentDescription("Choose which verb the widget shows.")

    @Parameter(title: "Show", default: .verbOfTheDay)
    var mode: VerbWidgetMode

    @Parameter(title: "Verb")
    var verb: VerbChoice?

    static var parameterSummary: some ParameterSummary {
        When(\.$mode, .equalTo, VerbWidgetMode.pick) {
            Summary("\(\.$mode) \(\.$verb)")
        } otherwise: {
            Summary("\(\.$mode)")
        }
    }
}
