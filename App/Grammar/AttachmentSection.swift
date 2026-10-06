import SwiftUI
import VerbKit

/// "How it attaches": per rule, its slot chips, the ending and a live example built from
/// the app's words. "Try another word" steps through the words of each class. A rule
/// without slots shows its written pattern and examples as before.
struct AttachmentSection: View {
    @Environment(VerbStore.self) private var verbStore
    @Environment(WordsStore.self) private var wordsStore
    let rules: [AttachmentRule]
    @State private var offset = 0
    @State private var showingBlocks = false

    private func words(_ wordClass: WordClass) -> [SlotSource] {
        wordClass == .verb ? verbStore.verbs : wordsStore.words(of: wordClass)
    }

    /// The first word (from `offset` on) that the rule builds a pattern for. Each step also
    /// moves to the rule's next slot, so "Try another word" shows the past and negative too.
    private func example(_ rule: AttachmentRule) -> (base: String, built: String)? {
        let pool = words(rule.wordClass)
        guard !pool.isEmpty, !rule.slots.isEmpty, rule.then != nil else { return nil }
        let slots = rule.slots.indices.map { rule.slots[($0 + offset) % rule.slots.count] }
        for step in 0..<pool.count {
            let word = pool[(offset + step) % pool.count]
            for slot in slots {
                if let built = rule.build(word, slot: slot), let base = word.form(for: slot) {
                    return (base, built)
                }
            }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("How it attaches").font(.title3.weight(.semibold))
                Spacer()
                if rules.contains(where: { example($0) != nil }) {
                    Button("Try another word", systemImage: "arrow.triangle.2.circlepath") { offset += 1 }
                        .font(.footnote)
                }
            }
            ForEach(Array(rules.enumerated()), id: \.offset) { _, rule in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(rule.wordClass.displayName).font(.subheadline.weight(.semibold))
                        if let condition = rule.condition {
                            JapaneseText("· \(condition)").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    if !rule.slots.isEmpty {
                        chips(rule)
                    }
                    if let example = example(rule) {
                        HStack(spacing: 8) {
                            JapaneseText(example.base).foregroundStyle(.secondary)
                            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            JapaneseText(example.built).font(.title3.weight(.semibold))
                        }
                        .accessibilityElement(children: .combine)
                    } else {
                        JapaneseText(rule.pattern).font(.headline)
                        ForEach(rule.example.components(separatedBy: " / "), id: \.self) { example in
                            JapaneseText(example).font(.title3)
                        }
                    }
                    if let note = rule.note {
                        JapaneseText(note).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .sheet(isPresented: $showingBlocks) { BuildingBlocksSheet() }
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
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the building blocks")
            }
            if rule.daToNa {
                JapaneseText("だ → な").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }
            if let then = rule.then {
                JapaneseText("+ \(then)").font(.subheadline.weight(.semibold))
            }
        }
    }
}
