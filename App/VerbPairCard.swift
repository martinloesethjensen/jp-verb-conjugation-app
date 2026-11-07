import SwiftUI
import VerbKit

/// The verb page's transitive/intransitive pair (#58): this verb's phrase and its partner's,
/// `ドアを開ける ↔ ドアが開く`, with the partner one tap away. Draws nothing when the verb has no
/// pair or the partner is not in the loaded data.
struct VerbPairCard: View {
    let verb: Verb
    @Environment(VerbStore.self) private var verbStore
    @Environment(\.openRoute) private var openRoute

    var body: some View {
        if let pair = verb.pair, let partner = verb.pairPartner(in: verbStore.verbs),
           let partnerPair = partner.pair {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Transitive and intransitive", systemImage: "arrow.left.arrow.right")
                VStack(alignment: .leading, spacing: 8) {
                    row(pair, of: verb, opens: false)
                    Divider()
                    row(partnerPair, of: partner, opens: true)
                }
                .paperCard()
                LessonLinks(ids: [GrammarPoint.verbPairsID])
            }
        }
    }

    private func row(_ pair: VerbPair, of owner: Verb, opens: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(pair.transitivity.title) · \(pair.transitivity.particle)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(pair.transitivity.accessibilityTitle)
                Spacer()
                if opens {
                    Button {
                        openRoute(.verb(owner.id))
                    } label: {
                        HStack(spacing: 4) {
                            Text(owner.displayTitle)
                            RowChevron()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .accessibilityLabel("Open \(owner.displayTitle)")
                }
            }
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    JapaneseText(pair.jp)
                        .font(.body)
                    Text(pair.en)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
                .textActions(pair.jp, translate: true)
                SpeakButton(text: pair.jp)
            }
        }
    }
}

private extension Transitivity {
    var title: String {
        switch self {
        case .transitive: "Transitive"
        case .intransitive: "Intransitive"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .transitive: "Transitive, takes を"
        case .intransitive: "Intransitive, takes が"
        }
    }
}
