import SwiftUI
import VerbKit

/// What the topic sheet reports: some topics, or the pairs answered wrongly before.
enum QuizSelection {
    case topics(Set<QuizTopic>)
    case weakSpots
}

/// Asks what to practise before a quiz starts. Rows are the topics the verbs in
/// play have forms in, plus Everything and, first, Weak spots.
struct QuizTopicSheet: View {
    let verbs: [Verb]
    /// Weak pairs among the given verbs, so the count follows "Favourites only".
    let weakSpotCount: ([Verb]) -> Int
    var onStart: ([Verb], QuizSelection) -> Void
    var onCancel: () -> Void

    private enum Choice: Hashable {
        case weakSpots
        case everything
        case topic(QuizTopic)
    }

    @State private var choice: Choice = .everything
    @State private var favouritesOnly = false
    @AppStorage(FavouriteVerbs.defaultsKey, store: .appGroup) private var favouritesRaw = ""

    private var favouriteVerbs: [Verb] { FavouriteVerbs(rawValue: favouritesRaw).filter(verbs) }

    /// The verbs the quiz draws from: only the starred ones when that is switched on.
    private var quizVerbs: [Verb] { favouritesOnly ? favouriteVerbs : verbs }

    private var choices: [QuizTopicChoice] { QuizTopic.choices(for: quizVerbs) }

    private var weakSpots: Int { weakSpotCount(quizVerbs) }

    private var weakSpotsDetail: String {
        if weakSpots > 0 { return "\(weakSpots) \(weakSpots == 1 ? "pair" : "pairs")" }
        return favouritesOnly && weakSpotCount(verbs) > 0 ? "None in favourites" : "Answer some questions first"
    }

    /// False when narrowing the verbs has left nothing behind `value`.
    private func isAvailable(_ value: Choice) -> Bool {
        switch value {
        case .weakSpots: return weakSpots > 0
        case .everything: return true
        case .topic(let topic): return choices.contains { $0.topic == topic }
        }
    }

    private var selection: QuizSelection {
        switch choice {
        case .weakSpots: return .weakSpots
        case .everything: return .topics(Set(choices.map(\.topic)))
        case .topic(let topic): return .topics([topic])
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Practise") {
                    row(
                        title: "Weak spots",
                        detail: weakSpotsDetail,
                        choice: .weakSpots,
                        enabled: weakSpots > 0
                    )
                    ForEach(choices, id: \.topic) { item in
                        row(title: item.topic.title, detail: Self.formsText(item.count), choice: .topic(item.topic))
                    }
                    row(title: "Everything", detail: Self.formsText(choices.reduce(0) { $0 + $1.count }), choice: .everything)
                }
                // Only worth offering when there is a choice to make: some, but not all, verbs starred.
                if !favouriteVerbs.isEmpty && favouriteVerbs.count < verbs.count {
                    Section {
                        Toggle("Favourites only (\(favouriteVerbs.count))", isOn: $favouritesOnly)
                    }
                }
            }
            .onChange(of: favouritesOnly) {
                if !isAvailable(choice) { choice = .everything }
            }
            .navigationTitle("Quiz")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { onStart(quizVerbs, selection) }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private static func formsText(_ count: Int) -> String {
        "\(count) \(count == 1 ? "form" : "forms")"
    }

    private func row(title: String, detail: String, choice value: Choice, enabled: Bool = true) -> some View {
        Button {
            choice = value
        } label: {
            HStack {
                Text(title).foregroundStyle(enabled ? .primary : .secondary)
                Spacer()
                Text(detail).foregroundStyle(.secondary)
                Image(systemName: choice == value ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(choice == value ? Color.accentColor : Color.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .contentShape(Rectangle())
    }
}
