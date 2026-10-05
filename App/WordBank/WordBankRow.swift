import SwiftUI
import VerbKit

/// A list row: the text (with furigana), its first standard equivalent and first
/// meaning, and up to three tag pills (dialect tags first).
struct WordBankRow: View {
    @Environment(WordBankStore.self) private var store
    let entry: WordBankEntryValue
    /// The folder path, shown when a result is outside the folder being viewed.
    var folderPath: String?

    private var tags: [AnyView] {
        let dialect = store.dialectTags.filter { entry.dialectTagIDs.contains($0.id) }.map { AnyView(TagPill($0)) }
        let custom = store.customTags.filter { entry.customTagIDs.contains($0.id) }.map { AnyView(TagPill($0)) }
        return Array((dialect + custom).prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            JapaneseText(entry.text)
                .font(.title3.weight(.bold))
            if let equivalent = entry.equivalents.first {
                Label {
                    JapaneseText(equivalent.written)
                } icon: {
                    Image(systemName: "arrow.right").accessibilityLabel("Standard")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            if let sense = entry.senses.first {
                Text(sense.meaning)
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(.secondary)
            }
            if let folderPath {
                Label(folderPath, systemImage: "folder").font(.caption).foregroundStyle(.secondary)
            }
            let tags = tags
            if !tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(tags.indices, id: \.self) { tags[$0] }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
