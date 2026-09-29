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
                .foregroundStyle(verb.type.accentColor)
                .glassEffect(.regular.tint(verb.type.accentColor.opacity(0.35)), in: Capsule())

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verb.dict)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(verb.teGroup?.accentColor ?? verb.type.accentColor)
                    if let kanji = verb.kanji {
                        Text(kanji)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
