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
    let weakSpotCount: Int
    var onStart: ([Verb], QuizSelection) -> Void
    var onCancel: () -> Void

    private enum Choice: Hashable {
        case weakSpots
        case everything
        case topic(QuizTopic)
    }

    @State private var choice: Choice = .everything

    private var choices: [QuizTopicChoice] { QuizTopic.choices(for: verbs) }

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
                        detail: weakSpotCount > 0 ? "\(weakSpotCount) \(weakSpotCount == 1 ? "pair" : "pairs")" : "Answer some questions first",
                        choice: .weakSpots,
                        enabled: weakSpotCount > 0
                    )
                    ForEach(choices, id: \.topic) { item in
                        row(title: item.topic.title, detail: Self.formsText(item.count), choice: .topic(item.topic))
                    }
                    row(title: "Everything", detail: Self.formsText(choices.reduce(0) { $0 + $1.count }), choice: .everything)
                }
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
                    Button("Start") { onStart(verbs, selection) }
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
