import SwiftUI
import VerbKit

/// Search results: the reading line, a paper card per kind, and the hidden-levels row.
struct SearchResultsList: View {
    let query: String
    let results: GlobalSearchResults
    @Binding var scope: SearchScope
    let onShowHidden: () -> Void
    /// Records the query as recent, then opens the result.
    let open: (SearchDestination) -> Void

    @Environment(WordBankStore.self) private var wordBank
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SearchScopeChips(scope: $scope)
                Text(SearchDisplay.resultsLine(query: query, readingAs: results.readingAs, count: results.count))
                    .font(.subheadline)
                    .foregroundStyle(palette.muted)
                    .padding(.horizontal, 16)

                Group {
                    if !results.verbs.isEmpty {
                        section("Verbs") { ForEach(results.verbs) { verbRow($0) } }
                    }
                    if !results.grammar.isEmpty {
                        section("Grammar") { ForEach(results.grammar) { grammarRow($0) } }
                    }
                    if !results.counters.isEmpty {
                        section("Counters") { counterRows }
                    }
                    if !results.wordBank.isEmpty {
                        section("Word Bank") { ForEach(results.wordBank) { wordBankRow($0.entry) } }
                    }
                    if results.hiddenCount > 0 { hiddenRow }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 12)
        }
    }

    // MARK: Sections

    private func section(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title)
            VStack(spacing: 0) {
                Group(subviews: rows()) { subviews in
                    ForEach(Array(subviews.enumerated()), id: \.offset) { index, subview in
                        if index > 0 { Divider().overlay(palette.rule) }
                        subview
                    }
                }
            }
            .paperCard(cornerRadius: 14)
        }
    }

    private func row(_ destination: SearchDestination, @ViewBuilder content: () -> some View) -> some View {
        Button {
            open(destination)
        } label: {
            HStack(spacing: 12) {
                content()
                Spacer(minLength: 0)
                RowChevron()
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Rows

    private func verbRow(_ verb: Verb) -> some View {
        row(.route(.verb(verb.id))) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    JapaneseText(verb.kanji ?? verb.dict)
                        .font(.headword(.title3))
                        .foregroundStyle(palette.ink)
                    Text(verb.meaning)
                        .font(.subheadline)
                        .foregroundStyle(palette.muted)
                }
                TypeLabel(verb.type, teGroup: verb.teGroup)
            }
            LevelBadge(level: verb.jlpt)
        }
    }

    private func grammarRow(_ point: GrammarPoint) -> some View {
        row(.route(.grammar(point.id))) {
            VStack(alignment: .leading, spacing: 3) {
                JapaneseText(point.title)
                    .font(.headword(.body))
                    .foregroundStyle(palette.ink)
                Text(point.summary)
                    .font(.subheadline)
                    .foregroundStyle(palette.muted)
                    .lineLimit(1)
            }
            LevelBadge(range: point.levelRange)
        }
    }

    @ViewBuilder
    private var counterRows: some View {
        ForEach(results.counters.groups) { group in
            row(.route(.counterGroup(group.id))) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title).foregroundStyle(palette.ink)
                    Text(group.summary).font(.subheadline).foregroundStyle(palette.muted).lineLimit(1)
                }
            }
        }
        ForEach(results.counters.counters) { counter in
            row(.route(.counter(counter.id))) {
                JapaneseText(counter.counter)
                    .font(.headword(.title2))
                    .foregroundStyle(palette.ink)
                    .frame(minWidth: 36)
                Text(counter.meaning).foregroundStyle(palette.ink)
                LevelBadge(level: counter.jlpt)
            }
        }
        ForEach(Array(results.counters.forms.enumerated()), id: \.offset) { _, form in
            row(.route(.counter(form.counter.id))) {
                JapaneseText(form.counter.written(form.number))
                    .font(.headword(.body))
                    .foregroundStyle(palette.ink)
                Text(form.reading).foregroundStyle(palette.muted)
            }
        }
        ForEach(Array(results.counters.things.enumerated()), id: \.offset) { _, match in
            if let counter = match.counters.first {
                row(.route(.counter(counter.id))) {
                    VStack(alignment: .leading, spacing: 2) {
                        JapaneseText(match.thing.word).foregroundStyle(palette.ink)
                        Text(match.thing.meaning).font(.subheadline).foregroundStyle(palette.muted)
                    }
                    Spacer(minLength: 8)
                    JapaneseText(counter.counter)
                        .font(.headword(.title3))
                        .foregroundStyle(palette.ink)
                }
            }
        }
    }

    private func wordBankRow(_ entry: WordBankEntryValue) -> some View {
        row(.wordBankEntry(entry.id)) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    JapaneseText(entry.text)
                        .font(.headword(.title3))
                        .foregroundStyle(palette.ink)
                    if let meaning = entry.senses.first?.meaning {
                        Text(meaning).font(.subheadline).foregroundStyle(palette.muted)
                    }
                }
                if let folderID = entry.folderID {
                    Text("Folder: " + wordBank.tree.path(of: folderID).map(\.name).joined(separator: " › "))
                        .font(.caption)
                        .foregroundStyle(palette.muted)
                }
            }
        }
    }

    private var hiddenRow: some View {
        HStack {
            Text(SearchDisplay.hiddenLine(count: results.hiddenCount, levels: results.hiddenLevels))
                .font(.subheadline)
                .foregroundStyle(palette.muted)
            Spacer(minLength: 8)
            Button("Show", action: onShowHidden)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.button)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.rule, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}

/// Where a search result leads.
enum SearchDestination {
    case route(Route)
    case wordBankEntry(UUID)
}
