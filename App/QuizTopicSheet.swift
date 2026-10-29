import SwiftUI
import VerbKit

/// What the topic sheet reports: some topics, or the pairs answered wrongly before.
enum QuizSelection {
    case topics(Set<QuizTopic>)
    case weakSpots
    /// Grammar connections, built from the sheet's verbs and every word.
    case connections
    /// Common mistakes with a wrong form: pick the wrong one.
    case spotMistake
    /// Example sentences with a marked particle blanked: pick the particle.
    case particles
}

extension QuizSessionTopic {
    /// What a saved verb quiz started from the sheet was practising. Connections have their
    /// own screen and are never saved, so they never get here.
    init(_ selection: QuizSelection) {
        switch selection {
        case .topics(let topics): self.init(topics: topics)
        case .weakSpots, .connections, .spotMistake, .particles: self = .weakSpots
        }
    }
}

/// Asks what to practise before a quiz starts. Rows are the topics the verbs in
/// play have forms in, plus Everything and, first, Weak spots.
struct QuizTopicSheet: View {
    let verbs: [Verb]
    let connectionPatterns: Int
    /// How many Spot the mistake questions the level settings allow; the row is off at zero.
    let spotMistakeQuestions: Int
    /// How many particle blanks the level settings allow; the row is off at zero.
    let particleQuestions: Int
    /// Weak pairs among the given verbs, so the count follows "Favourites only".
    let weakSpotCount: ([Verb]) -> Int
    /// A saved quiz that can be picked up again, offered above the topics (issue #38).
    var resumable: QuizSession? = nil
    var onResume: () -> Void = {}
    var onStart: ([Verb], QuizSelection) -> Void
    var onCancel: () -> Void

    private enum Choice: Hashable {
        case weakSpots
        case connections
        case spotMistake
        case particles
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
        case .connections: return connectionPatterns > 0
        case .spotMistake: return spotMistakeQuestions > 0
        case .particles: return particleQuestions > 0
        case .everything: return true
        case .topic(let topic): return choices.contains { $0.topic == topic }
        }
    }

    private var selection: QuizSelection {
        switch choice {
        case .weakSpots: return .weakSpots
        case .connections: return .connections
        case .spotMistake: return .spotMistake
        case .particles: return .particles
        case .everything: return .topics(Set(choices.map(\.topic)))
        case .topic(let topic): return .topics([topic])
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let resumable {
                    Section {
                        Button(action: onResume) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Resume \(resumable.topic.title)")
                                    Text(resumable.summary)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "play.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } footer: {
                        Text("A new verb quiz replaces the unfinished one.")
                    }
                }
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
                Section {
                    row(
                        title: "Connections",
                        detail: connectionPatterns == 1 ? "1 pattern" : "\(connectionPatterns) patterns",
                        choice: .connections,
                        enabled: connectionPatterns > 0
                    )
                    row(
                        title: "Spot the mistake",
                        detail: spotMistakeQuestions == 0 ? "None for your levels" : "\(spotMistakeQuestions) \(spotMistakeQuestions == 1 ? "mistake" : "mistakes")",
                        choice: .spotMistake,
                        enabled: spotMistakeQuestions > 0
                    )
                    row(
                        title: "Particles",
                        detail: particleQuestions == 0 ? "None for your levels" : "\(particleQuestions) \(particleQuestions == 1 ? "sentence" : "sentences")",
                        choice: .particles,
                        enabled: particleQuestions > 0
                    )
                } footer: {
                    Text("Connections: join verbs, adjectives and nouns to grammar patterns, しずか + ので. Spot the mistake: find the wrong form among correct ones. Particles: fill in the particle, 電車＿乗る.")
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
            // On the label, so the gap between title and detail is tappable too.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityValue(choice == value ? "Selected" : "")
    }
}
