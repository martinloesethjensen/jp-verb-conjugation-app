import SwiftUI
import VerbKit

/// A counter in the home directory: the counter large, its reading, what it counts, and an
/// "irregular" tag where the readings have no pattern.
struct DirectoryRow: View {
    let counter: Counter
    @Environment(\.dynamicTypeSize) private var typeSize

    private var irregularTag: some View {
        Text("irregular")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .fixedSize()
            .glassEffect(in: Capsule())
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    /// At accessibility sizes the meaning gets its own full-width line instead of sharing one with the
    /// reading, tag and chevron, so it wraps instead of truncating.
    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        Text(counter.counter).font(.title2.weight(.bold))
                        Text(counter.reading).font(.subheadline).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        chevron
                    }
                    Text(counter.meaning).font(.subheadline)
                    if counter.sound == "irregular" { irregularTag }
                }
            } else {
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
                    if counter.sound == "irregular" { irregularTag }
                    Spacer(minLength: 0)
                    chevron
                }
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
