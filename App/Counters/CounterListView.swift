import SwiftUI
import VerbKit

/// A counter as a list row: the counter, its reading and meaning, its symbol and level.
struct CounterRow: View {
    let counter: Counter

    var body: some View {
        HStack(spacing: 12) {
            Text(counter.counter)
                .font(.title.weight(.bold))
                .frame(minWidth: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(counter.reading)
                        .font(.body)
                    if let level = counter.jlpt {
                        Text(level.displayName)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .glassEffect(in: Capsule())
                    }
                }
                Text(counter.meaning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: counter.symbol)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// "All counters": every counter the level settings leave visible, grouped by level.
struct CounterListView: View {
    @Environment(CountersStore.self) private var store
    @AppStorage(LevelSettings.defaultsKey, store: .appGroup) private var hiddenLevelsRaw = ""

    private var visible: [Counter] {
        store.counters.visible(in: LevelSettings(rawValue: hiddenLevelsRaw))
    }

    var body: some View {
        List {
            ForEach(JLPTLevel.allCases.reversed(), id: \.self) { level in
                let counters = visible.filter { $0.jlpt == level }
                if !counters.isEmpty {
                    Section(level.displayName) {
                        ForEach(counters) { counter in
                            NavigationLink(value: CounterDestination.counter(counter, focus: nil)) {
                                CounterRow(counter: counter)
                            }
                        }
                    }
                }
            }
            let unleveled = visible.filter { $0.jlpt == nil }
            if !unleveled.isEmpty {
                Section {
                    ForEach(unleveled) { counter in
                        NavigationLink(value: CounterDestination.counter(counter, focus: nil)) {
                            CounterRow(counter: counter)
                        }
                    }
                }
            }
        }
        .navigationTitle("All counters")
        .overlay {
            if visible.isEmpty {
                ContentUnavailableView("No counters in your levels", systemImage: "line.3.horizontal.decrease.circle")
            }
        }
    }
}
