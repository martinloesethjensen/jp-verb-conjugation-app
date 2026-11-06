import SwiftUI
import VerbKit

struct VerbRow: View {
    let verb: Verb
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // The kanji spelling with its own reading as furigana; kana alone for する.
                JapaneseText(units: verb.dictionaryUnits)
                    .font(.headword(.title3))
                    .foregroundStyle(palette.ink)
                Text(verb.meaning)
                    .font(.subheadline)
                    .foregroundStyle(palette.muted)
                    .lineLimit(1)
                Spacer(minLength: 4)
                LevelBadge(level: verb.jlpt)
            }
            TypeLabel(verb.type, teGroup: verb.teGroup)
        }
        .padding(.vertical, 4)
    }
}
