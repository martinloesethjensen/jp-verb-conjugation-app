import SwiftUI
import VerbKit

/// A counter in the home directory: the counter large, its reading, what it counts, and an
/// "irregular" tag where the readings have no pattern.
struct DirectoryRow: View {
    let counter: Counter
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.palette) private var palette
    /// With furigana on, the reading already sits over the counter, so the reading column is dropped.
    @AppStorage(FuriganaSetting.defaultsKey, store: .appGroup) private var showFurigana = true

    private var irregularTag: some View {
        Text("irregular")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .fixedSize()
            .overlay(Capsule().strokeBorder(palette.ink, lineWidth: 1))
    }

    private var chevron: some View { RowChevron() }

    /// At accessibility sizes the meaning gets its own full-width line instead of sharing one with the
    /// reading, tag and chevron, so it wraps instead of truncating.
    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        JapaneseText(units: counter.headwordUnits).font(.headword(.title2)).foregroundStyle(palette.ink)
                        if !showFurigana || counter.reading == counter.counter {
                            Text(counter.reading).font(.subheadline).foregroundStyle(palette.muted)
                        }
                        Spacer(minLength: 0)
                        chevron
                    }
                    Text(counter.meaning).font(.subheadline).foregroundStyle(palette.ink)
                    if counter.sound == "irregular" { irregularTag }
                }
            } else {
                HStack(spacing: 12) {
                    JapaneseText(units: counter.headwordUnits)
                        .font(.headword(.title2))
                        .foregroundStyle(palette.ink)
                        .frame(minWidth: 32)
                    if !showFurigana {
                        Text(counter.reading)
                            .font(.subheadline)
                            .foregroundStyle(palette.muted)
                            .frame(minWidth: 36, alignment: .leading)
                    }
                    Text(counter.meaning)
                        .font(.subheadline)
                        .foregroundStyle(palette.ink)
                        .lineLimit(2)
                    if counter.sound == "irregular" { irregularTag }
                    Spacer(minLength: 0)
                    chevron
                }
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(counter.sound == "irregular"
            ? "\(counter.counter), \(counter.reading), \(counter.meaning), irregular"
            : "\(counter.counter), \(counter.reading), \(counter.meaning)")
        .accessibilityAddTraits(.isButton)
    }
}
