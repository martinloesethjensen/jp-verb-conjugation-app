import SwiftUI
import VerbKit

/// A counter as a list row in search results: the counter, its reading and meaning, its symbol and level.
struct CounterRow: View {
    @Environment(\.palette) private var palette
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
                    LevelBadge(level: counter.jlpt)
                }
                Text(counter.meaning)
                    .font(.caption)
                    .foregroundStyle(palette.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: counter.symbol)
                .foregroundStyle(palette.muted)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
