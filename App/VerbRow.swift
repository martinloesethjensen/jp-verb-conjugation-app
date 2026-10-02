import SwiftUI
import VerbKit

struct VerbRow: View {
    let verb: Verb

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verb.label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .accentPill(verb.type.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verb.dict)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                    if let kanji = verb.kanji {
                        JapaneseText(kanji)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let level = verb.jlpt {
                        Text(level.displayName)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .glassEffect(in: Capsule())
                    }
                }
                Text(verb.meaning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
