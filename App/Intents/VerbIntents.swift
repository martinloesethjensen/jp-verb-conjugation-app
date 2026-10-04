import AppIntents
import SwiftData
import VerbKit

/// Reads the shared store, like the widget does; intents can run without the app being open.
@MainActor
enum IntentData {
    static func verbs() -> [Verb] {
        guard let container = try? VerbModelContainer.make() else { return [] }
        let persisting = SwiftDataVerbPersisting(modelContext: ModelContext(container))
        return (try? persisting.loadAllVerbs()) ?? []
    }
}

struct VerbAppEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Verb"
    static let defaultQuery = VerbAppEntityQuery()

    var id: String   // Verb.id (the dictionary form)
    var title: String
    var meaning: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(meaning)")
    }

    init(_ verb: Verb) {
        id = verb.id
        title = verb.kanji.map { "\(verb.dict) (\($0))" } ?? verb.dict
        meaning = verb.meaning
    }
}

struct VerbAppEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [VerbAppEntity] {
        await IntentData.verbs().filter { identifiers.contains($0.id) }.map(VerbAppEntity.init)
    }
    func suggestedEntities() async throws -> [VerbAppEntity] {
        await IntentData.verbs().map(VerbAppEntity.init)
    }
    func entities(matching string: String) async throws -> [VerbAppEntity] {
        await IntentData.verbs().filter { matchesSearch($0, query: string) }.map(VerbAppEntity.init)
    }
}

/// "Show たべる": opens the verb page through the same `verbtable://` link the widgets use.
struct ShowVerbIntent: AppIntent {
    static let title: LocalizedStringResource = "Show a verb"
    static let description = IntentDescription("Opens a verb's conjugation table.")

    @Parameter(title: "Verb")
    var verb: VerbAppEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$verb)")
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(Route.verb(verb.id).url))
    }
}

enum QuizTopicOption: String, AppEnum {
    case basic, potential, nDesu, auxiliaries, otherForms

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Topic"
    static let caseDisplayRepresentations: [QuizTopicOption: DisplayRepresentation] = [
        .basic: "Basic forms",
        .potential: "Potential",
        .nDesu: "んです",
        .auxiliaries: "Auxiliaries",
        .otherForms: "More forms",
    ]

    var topic: QuizTopic { QuizTopic(rawValue: rawValue) ?? .basic }
}

/// "Quiz me": starts a quiz on everything, or on the chosen topic.
struct StartQuizIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a quiz"
    static let description = IntentDescription("Starts a conjugation quiz, on every topic or just one.")

    @Parameter(title: "Topic")
    var topic: QuizTopicOption?

    static var parameterSummary: some ParameterSummary {
        Summary("Start a quiz on \(\.$topic)")
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(QuizLink(topic: topic?.topic).url))
    }
}

struct VerbTableShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowVerbIntent(),
            phrases: [
                "Show \(\.$verb) in \(.applicationName)",
                "Conjugate \(\.$verb) in \(.applicationName)",
            ],
            shortTitle: "Show a verb",
            systemImageName: "book"
        )
        AppShortcut(
            intent: StartQuizIntent(),
            phrases: [
                "Quiz me in \(.applicationName)",
                "Start a quiz in \(.applicationName)",
            ],
            shortTitle: "Quiz me",
            systemImageName: "gamecontroller"
        )
    }
}
