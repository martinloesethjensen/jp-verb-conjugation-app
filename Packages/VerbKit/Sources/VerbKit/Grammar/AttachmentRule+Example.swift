import Foundation

public extension AttachmentRule {
    /// The first word (from `offset` on) that this rule builds a pattern for. Each step also moves
    /// to the rule's next slot, so stepping through shows the past and negative too. A verb missing
    /// from a slot's `eligible` keys is skipped for that slot, so the volitional lesson never shows
    /// わかりましょう. Nil without slots, an ending or words.
    func example(from pool: [SlotSource], eligible: [GrammarSlot: Set<String>], offset: Int) -> (base: String, built: String)? {
        guard !pool.isEmpty, !slots.isEmpty, then != nil else { return nil }
        let ordered = slots.indices.map { slots[($0 + offset) % slots.count] }
        for step in 0..<pool.count {
            let word = pool[(offset + step) % pool.count]
            for slot in ordered {
                if let keys = eligible[slot], !keys.contains(word.stableKey) { continue }
                if let built = build(word, slot: slot), let base = word.form(for: slot) {
                    return (base, built)
                }
            }
        }
        return nil
    }
}
