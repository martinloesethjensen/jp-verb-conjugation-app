import SwiftUI
import VerbKit

/// A list row (canvas board "Proposed: Word Bank"): the text in Mincho with furigana and its first
/// meaning beside it, then up to three tag pills (dialect tags first) and "= " its first standard form.
struct WordBankRow: View {
    @Environment(WordBankStore.self) private var store
    let entry: WordBankEntryValue
    /// The folder path, shown when a result is outside the folder being viewed.
    var folderPath: String?
    /// Why a search result matched, when it isn't obvious from the text.
    var explanation: WordBankMatch.Explanation?
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize

    private var tags: [AnyView] {
        let dialect = store.dialectTags.filter { entry.dialectTagIDs.contains($0.id) }.map { AnyView(TagPill($0)) }
        let custom = store.customTags.filter { entry.customTagIDs.contains($0.id) }.map { AnyView(TagPill($0)) }
        return Array((dialect + custom).prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The text in Mincho with its first meaning beside it (below at accessibility sizes).
            let first = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            first {
                JapaneseText(entry.text)
                    .font(.headword(.title3))
                    .foregroundStyle(palette.ink)
                if let sense = entry.senses.first {
                    Text(sense.meaning)
                        .font(.subheadline)
                        .foregroundStyle(palette.muted)
                        .lineLimit(2)
                }
            }
            let tags = tags
            if !tags.isEmpty || entry.equivalents.first != nil {
                // Wraps, so pills and the standard form never truncate at large text sizes.
                WrappingFlowLayout(spacing: 6) {
                    ForEach(tags.indices, id: \.self) { tags[$0] }
                    if let equivalent = entry.equivalents.first {
                        HStack(spacing: 2) {
                            Text("=").accessibilityLabel("Standard:")
                            JapaneseText(equivalent.written)
                        }
                        .font(.caption)
                        .foregroundStyle(palette.muted)
                    }
                }
            }
            if let explanation {
                MatchExplanationLabel(explanation: explanation)
            }
            if let folderPath {
                Label(folderPath, systemImage: "folder").font(.caption).foregroundStyle(palette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
