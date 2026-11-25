import SwiftUI
import VerbKit

struct VerbRow: View {
    let verb: Verb
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if typeSize.isAccessibilitySize {
                // At accessibility sizes the headword gets its own line, so the ruby flow never
                // splits 来る between lines to make room for the meaning.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    headword
                    Spacer(minLength: 4)
                    LevelBadge(level: verb.jlpt)
                }
                Text(verb.meaning)
                    .font(.subheadline)
                    .foregroundStyle(palette.muted)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    headword
                    Text(verb.meaning)
                        .font(.subheadline)
                        .foregroundStyle(palette.muted)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    LevelBadge(level: verb.jlpt)
                }
            }
            TypeLabel(verb.type, teGroup: verb.teGroup)
        }
        .padding(.vertical, 4)
    }

    /// The kanji spelling with its own reading as furigana; kana alone for する.
    private var headword: some View {
        JapaneseText(units: verb.dictionaryUnits)
            .font(.headword(.title3))
            .foregroundStyle(palette.ink)
            .fixedSize(horizontal: true, vertical: false)
    }
}
