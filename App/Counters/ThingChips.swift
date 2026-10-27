import SwiftUI
import VerbKit

/// What a counter counts: one chip per thing, primary first. Outlined chips are acceptable but
/// not the standard counter, dimmed chips are casual fallbacks. Tapping a chip lists every
/// counter that lists the word.
struct ThingChips: View {
    let counter: Counter
    @Environment(CountersStore.self) private var store
    @Environment(\.openRoute) private var openRoute
    @State private var shown: CountedThing?

    private var things: [CountedThing] { counter.thingsByFit }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WrappingFlowLayout {
                ForEach(things, id: \.word) { thing in
                    Button {
                        shown = thing
                    } label: {
                        chip(thing)
                    }
                    .buttonStyle(.plain)
                    .popover(item: Binding(
                        get: { shown?.word == thing.word ? shown : nil },
                        set: { shown = $0 }
                    )) { thing in
                        otherCounters(for: thing)
                            .presentationCompactAdaptation(.popover)
                    }
                }
            }
            if let legend {
                Text(legend)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var legend: String? {
        let hasAcceptable = things.contains { $0.fit == .acceptable }
        let hasCasual = things.contains { $0.fit == .casual }
        switch (hasAcceptable, hasCasual) {
        case (true, true): return "Outlined: heard, but another counter is standard. Dimmed: a casual fallback."
        case (true, false): return "Outlined: heard, but another counter is standard."
        case (false, true): return "Dimmed: a casual fallback."
        case (false, false): return nil
        }
    }

    private func chip(_ thing: CountedThing) -> some View {
        HStack(spacing: 8) {
            Image(systemName: thing.symbol ?? counter.symbol)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                if thing.kana != thing.word {
                    Text(thing.kana)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(thing.word)
                    .font(.body)
            }
            Text(thing.meaning)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            switch thing.fit {
            case .primary:
                Capsule().fill(.clear).glassEffect(in: Capsule())
            case .acceptable:
                Capsule().strokeBorder(.secondary, lineWidth: 1)
            case .casual:
                Capsule().fill(.clear).glassEffect(in: Capsule())
            }
        }
        .opacity(thing.fit == .casual ? 0.6 : 1)
        .contentShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(thing.word), \(thing.kana), \(thing.meaning)\(fitSuffix(thing.fit))")
        .accessibilityHint("Shows the counters for this word")
    }

    private func fitSuffix(_ fit: CounterFit) -> String {
        switch fit {
        case .primary: ""
        case .acceptable: ", acceptable"
        case .casual: ", casual"
        }
    }

    /// Every counter that lists `thing`, primary first (the Things section of a search).
    private func otherCounters(for thing: CountedThing) -> some View {
        let match = searchCounters(store.counters, groups: [], query: thing.word).things
            .first { $0.thing.word == thing.word }
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(thing.word): \(thing.meaning)")
                .font(.headline)
            ForEach(match?.counters ?? [counter]) { other in
                Button {
                    shown = nil
                    openRoute(.counter(other.id))
                } label: {
                    HStack {
                        Text(other.counter).font(.title3.weight(.bold))
                        Text(other.reading)
                        Text(other.meaning).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }
}

extension CountedThing: Identifiable {
    public var id: String { word }
}
