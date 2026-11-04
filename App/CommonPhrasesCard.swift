import SwiftUI
import VerbKit

/// The verb page's "Common phrases" section: the chunks the verb is usually used in
/// (シャワーを浴びる, "take a shower"). Draws nothing when the verb has none.
struct CommonPhrasesCard: View {
    let collocations: [VerbCollocation]

    var body: some View {
        if !collocations.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Common phrases", systemImage: "text.bubble")
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(collocations.enumerated()), id: \.offset) { index, collocation in
                        if index > 0 { Divider() }
                        row(collocation)
                    }
                }
                .glassCard()
            }
        }
    }

    private func row(_ collocation: VerbCollocation) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                JapaneseText(collocation.jp)
                    .font(.body)
                Text(collocation.en)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .textActions(collocation.jp, translate: true)
            SpeakButton(text: collocation.jp)
        }
    }
}
