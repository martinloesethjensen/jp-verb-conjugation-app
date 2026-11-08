import SwiftUI
import VerbKit

/// The pattern at a glance, on genkō paper: the building block, +, the ending (chips switch between
/// a lesson's endings), and an example with the ending underlined. "Building blocks ›" explains
/// the blocks.
struct FormulaCard: View {
    let point: GrammarPoint
    let formula: GrammarFormula

    @Environment(\.palette) private var palette
    @Environment(VerbStore.self) private var verbStore
    @Environment(WordsStore.self) private var wordsStore
    @State private var selected: String?
    @State private var showingBlocks = false

    private var ending: String { selected.flatMap { formula.endings.contains($0) ? $0 : nil } ?? formula.endings[0] }

    private var baseTitle: String {
        switch formula.base {
        case let .slot(slot): slot.title
        case let .text(text): text
        }
    }

    /// A live example for a slotted formula, otherwise the written one.
    private var example: String? {
        if case .slot = formula.base,
           let rule = point.attachment.first(where: { $0.then == ending && !$0.slots.isEmpty }) {
            let pool: [SlotSource] = rule.wordClass == .verb ? verbStore.verbs : wordsStore.words(of: rule.wordClass)
            let eligible: [GrammarSlot: Set<String>] = rule.wordClass == .verb
                ? Dictionary(rule.slots.map { ($0, Set(rule.eligibleVerbs($0, among: verbStore.verbs).map(\.stableKey))) },
                             uniquingKeysWith: { first, _ in first })
                : [:]
            return rule.example(from: pool, eligible: eligible, offset: 0)?.built
        }
        return formula.examples[ending]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if formula.endings.count > 1 {
                WrappingFlowLayout(spacing: 8) {
                    ForEach(formula.endings, id: \.self) { option in
                        Button {
                            selected = option
                        } label: {
                            FilterChip(option, isOn: option == ending)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(option == ending ? .isSelected : [])
                    }
                }
            }
            WrappingFlowLayout(spacing: 10) {
                Text(baseTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.ink)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .overlay(Capsule().stroke(palette.muted, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                Text("+")
                    .font(.title3)
                    .foregroundStyle(palette.muted)
                JapaneseText(ending)
                    .font(.headword(.title))
                    .foregroundStyle(palette.ink)
            }
            .accessibilityElement(children: .combine)
            if let example {
                JapaneseText(example, emphasizing: GrammarHighlight.range(in: example, patterns: [ending]))
                    .font(.sentence(.title3))
                    .foregroundStyle(palette.ink)
            }
            Button {
                showingBlocks = true
            } label: {
                Text("Building blocks ›")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.button)
            }
            .buttonStyle(.plain)
        }
        .paperCard(cornerRadius: 14, ruled: true)
        .sheet(isPresented: $showingBlocks) { BuildingBlocksSheet() }
        .dismissOnLink { showingBlocks = false }
    }
}
