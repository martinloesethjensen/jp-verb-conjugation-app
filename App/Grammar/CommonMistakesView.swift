import SwiftUI
import VerbKit

/// One pitfall: heading, explanation, first example and the lesson it comes from.
struct MistakeRow: View {
    let mistake: CommonMistake

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            JapaneseText(mistake.heading).font(.headline)
            JapaneseText(mistake.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            if let example = mistake.examples.first {
                JapaneseText(example.jp).font(.subheadline)
            }
            HStack(spacing: 4) {
                Text("From \(mistake.sourceTitle)")
                Image(systemName: "chevron.right").imageScale(.small)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tint)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(mistake.sourceTitle)")
    }
}

/// Every lesson and counter pitfall by theme. Tapping one opens its lesson.
struct CommonMistakesView: View {
    @Environment(VerbStore.self) private var verbStore
    @Environment(CountersStore.self) private var countersStore
    @Environment(\.furiganaDictionary) private var furigana
    @Environment(\.openRoute) private var openRoute
    @AppStorage(LevelSettings.defaultsKey, store: .appGroup) private var hiddenLevelsRaw = ""
    @State private var search = ""
    var onOpen: () -> Void

    private var all: [CommonMistake] {
        CommonMistakes.build(grammar: verbStore.grammarPoints, counters: countersStore.counters)
    }

    private var shown: [CommonMistake] {
        all.visible(in: LevelSettings(rawValue: hiddenLevelsRaw))
            .filter { matchesMistakeSearch($0, query: search, furigana: furigana) }
    }

    var body: some View {
        let groups = CommonMistakes.grouped(shown)
        List {
            ForEach(groups, id: \.theme) { group in
                Section {
                    ForEach(group.mistakes) { mistake in
                        Button {
                            onOpen()
                            openRoute(mistake.source)
                        } label: {
                            MistakeRow(mistake: mistake)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("\(group.theme.title) (\(group.mistakes.count))")
                } footer: {
                    Text(group.theme.blurb)
                }
            }
        }
        .navigationTitle("Common mistakes")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search mistakes…")
        .overlay {
            if groups.isEmpty {
                if search.isEmpty {
                    ContentUnavailableView("No mistakes to show", systemImage: "checkmark.seal")
                } else {
                    ContentUnavailableView.search(text: search)
                }
            }
        }
    }
}

struct CommonMistakesSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CommonMistakesView(onOpen: { dismiss() })
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
