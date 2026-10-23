import SwiftUI
import VerbKit

/// A counter in the home directory: the counter large, its reading, what it counts, and an
/// "irregular" tag where the readings have no pattern.
struct DirectoryRow: View {
    let counter: Counter

    var body: some View {
        HStack(spacing: 12) {
            Text(counter.counter)
                .font(.title2.weight(.bold))
                .frame(minWidth: 32)
            Text(counter.reading)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(minWidth: 36, alignment: .leading)
            Text(counter.meaning)
                .font(.subheadline)
                .lineLimit(2)
            if counter.sound == "irregular" {
                Text("irregular")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .glassEffect(in: Capsule())
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
