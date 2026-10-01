import SwiftUI
import VerbKit

/// Asks what to practise before a quiz starts. Rows are the topics the verbs in
/// play have forms in, plus Everything.
struct QuizTopicSheet: View {
    let verbs: [Verb]
    var onStart: ([Verb], Set<QuizTopic>) -> Void
    var onCancel: () -> Void

    private enum Choice: Hashable {
        case everything
        case topic(QuizTopic)
    }

    @State private var choice: Choice = .everything

    private var choices: [QuizTopicChoice] { QuizTopic.choices(for: verbs) }

    private var selectedTopics: Set<QuizTopic> {
        switch choice {
        case .everything: return Set(choices.map(\.topic))
        case .topic(let topic): return [topic]
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Practise") {
                    ForEach(choices, id: \.topic) { item in
                        row(title: item.topic.title, count: item.count, choice: .topic(item.topic))
                    }
                    row(title: "Everything", count: choices.reduce(0) { $0 + $1.count }, choice: .everything)
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
                    Button("Start") { onStart(verbs, selectedTopics) }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func row(title: String, count: Int, choice value: Choice) -> some View {
        Button {
            choice = value
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text("\(count) forms").foregroundStyle(.secondary)
                Image(systemName: choice == value ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(choice == value ? Color.accentColor : Color.secondary)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
