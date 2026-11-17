import SwiftUI
import VerbKit

/// Search results in four sections: Forms, Counters, Groups, Things. Empty sections are hidden.
struct CounterSearchResultsView: View {
    @Environment(\.palette) private var palette
    let results: CounterSearchResults
    let search: String
    let summary: String
    let hiddenMatchCount: Int
    let open: (CounterDestination) -> Void

    var body: some View {
        List {
            if !results.forms.isEmpty {
                Section("Forms") {
                    ForEach(results.forms.indices, id: \.self) { index in
                        formRow(results.forms[index])
                    }
                }
                .paperRow()
            }
            if !results.counters.isEmpty {
                Section("Counters") {
                    ForEach(results.counters) { counter in
                        Button {
                            open(.counter(counter, focus: nil))
                        } label: {
                            CounterRow(counter: counter)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .paperRow()
            }
            if !results.groups.isEmpty {
                Section("Groups") {
                    ForEach(results.groups) { group in
                        Button {
                            open(.group(group))
                        } label: {
                            Label(group.title, systemImage: group.symbol)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .paperRow()
            }
            if !results.things.isEmpty {
                Section("Things") {
                    ForEach(results.things.indices, id: \.self) { index in
                        thingRow(results.things[index])
                    }
                }
                .paperRow()
            }
            if !results.isEmpty && hiddenMatchCount > 0 {
                HiddenMatchesRow(count: hiddenMatchCount)
            }
        }
        .paperBackground()
        .overlay {
            if results.isEmpty {
                if hiddenMatchCount > 0 {
                    NoMatchInLevelsView(summary: summary, hiddenCount: hiddenMatchCount)
                } else {
                    PaperEmptyState("No results for “\(search)”", message: "Check the spelling or try a new search.", glyph: "無")
                }
            }
        }
    }

    /// 三本 large, its reading, then "本 at 3". Opens the counter page on that number.
    private func formRow(_ match: CounterFormMatch) -> some View {
        HStack {
            Button {
                open(.counter(match.counter, focus: match.number))
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(match.counter.written(match.number))
                        .font(.title2.weight(.bold))
                    Text(match.reading)
                        .font(.body)
                    HStack(spacing: 6) {
                        Text("\(match.counter.counter) at \(match.number == .what ? "何" : match.number.key)")
                            .font(.caption)
                            .foregroundStyle(palette.muted)
                        if match.number.isExtended { UnreviewedLabel() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            SpeakButton(text: match.reading)
        }
    }

    /// "傘 かさ · umbrella", then its counters. One counter makes the whole row open it.
    private func thingRow(_ match: CounterThingMatch) -> some View {
        let label = VStack(alignment: .leading, spacing: 4) {
            Text("\(match.thing.word) \(match.thing.kana) · \(match.thing.meaning)")
                .font(.body)
        }
        return Group {
            if let only = match.counters.first, match.counters.count == 1 {
                Button {
                    open(.counter(only, focus: nil))
                } label: {
                    HStack {
                        label
                        Spacer(minLength: 0)
                        Text(only.counter).font(.title3.weight(.bold))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    label
                    HStack {
                        ForEach(match.counters) { counter in
                            Button(counter.counter) { open(.counter(counter, focus: nil)) }
                                .buttonStyle(.paperSecondaryInline)
                        }
                    }
                }
            }
        }
    }
}
