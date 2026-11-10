import SwiftUI
import VerbKit

/// "How it attaches": per rule, its slot chips, the ending and a live example built from
/// the app's words. "Try another word" steps through the words of each class. A rule
/// without slots shows its written pattern and examples as before.
struct AttachmentSection: View {
    @Environment(\.palette) private var palette
    @Environment(VerbStore.self) private var verbStore
    @Environment(WordsStore.self) private var wordsStore
    let rules: [AttachmentRule]
    /// The lesson's patterns (`GrammarHighlight.patterns`), underlined in the examples.
    var patterns: [String] = []
    @State private var offset = 0
    @State private var showingBlocks = false

    private func words(_ wordClass: WordClass) -> [SlotSource] {
        wordClass == .verb ? verbStore.verbs : wordsStore.words(of: wordClass)
    }

    /// The first word (from `offset` on) that the rule builds a pattern for. Each step also
    /// moves to the rule's next slot, so "Try another word" shows the past and negative too.
    /// A verb that lacks the form the rule spells out is skipped for that slot, so the
    /// volitional lesson never shows わかりましょう.
    /// The live example for `rule` at the current offset (`AttachmentRule.example`).
    private func example(_ rule: AttachmentRule) -> (base: String, built: String)? {
        let eligible: [GrammarSlot: Set<String>] = rule.wordClass == .verb
            ? Dictionary(rule.slots.map { slot in
                (slot, Set(rule.eligibleVerbs(slot, among: verbStore.verbs).map(\.stableKey)))
            }, uniquingKeysWith: { first, _ in first })
            : [:]
        return rule.example(from: words(rule.wordClass), eligible: eligible, offset: offset)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("How it attaches") {
                if rules.contains(where: { example($0) != nil }) {
                    Button("Try another word", systemImage: "arrow.triangle.2.circlepath") { offset += 1 }
                        .font(.footnote)
                        .foregroundStyle(palette.button)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                if index > 0 { Divider().overlay(palette.rule) }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(rule.wordClass.displayName).font(.subheadline.weight(.semibold))
                        if let condition = rule.condition {
                            JapaneseText("· \(condition)").font(.subheadline).foregroundStyle(palette.muted)
                        }
                    }
                    if !rule.slots.isEmpty {
                        chips(rule)
                    }
                    if let example = example(rule) {
                        HStack(spacing: 8) {
                            JapaneseText(example.base).foregroundStyle(palette.muted)
                            Image(systemName: "arrow.right").font(.caption).foregroundStyle(palette.muted)
                                .accessibilityHidden(true)
                            JapaneseText(example.built, emphasizing: GrammarHighlight.range(in: example.built, patterns: [rule.then ?? ""] + patterns))
                                .font(.sentence(.title3))
                        }
                        .accessibilityElement(children: .combine)
                    } else if let table = KanaRowTable(rule: rule) {
                        // The table shows every example and how its ending moves, so it stands in
                        // for the example lines and the note that spells out the endings.
                        JapaneseText(rule.pattern).font(.headline)
                        KanaRowTableView(table: table)
                    } else {
                        JapaneseText(rule.pattern).font(.headline)
                        ForEach(rule.example.components(separatedBy: " / "), id: \.self) { example in
                            JapaneseText(example, emphasizing: GrammarHighlight.range(in: example, patterns: patterns))
                                .font(.sentence(.title3))
                        }
                    }
                    if let note = rule.note, rule.kanaRow == nil {
                        JapaneseText(note).font(.footnote).foregroundStyle(palette.muted)
                    }
                }
                .padding(.vertical, 10)
            }
            }
            .paperCard(cornerRadius: 14, ruled: true)
        }
        .sheet(isPresented: $showingBlocks) { BuildingBlocksSheet() }
        .dismissOnLink { showingBlocks = false }
    }

    private func chips(_ rule: AttachmentRule) -> some View {
        HStack(spacing: 6) {
            ForEach(rule.slots, id: \.self) { slot in
                Button {
                    showingBlocks = true
                } label: {
                    Text(slot.title)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(palette.button.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the building blocks")
            }
            if rule.daToNa {
                JapaneseText("だ → な").font(.caption.weight(.bold)).foregroundStyle(palette.muted)
            }
            if let then = rule.then {
                JapaneseText("+ \(then)").font(.subheadline.weight(.semibold))
            }
        }
    }
}
