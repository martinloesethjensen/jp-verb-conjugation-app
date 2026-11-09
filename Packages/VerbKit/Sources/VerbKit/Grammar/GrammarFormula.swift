import Foundation

/// What a lesson's formula header shows: the building block a pattern attaches to, then each
/// ending ("plain form + はず / かもしれない / わけ", "て-form + もいい / はいけない").
public struct GrammarFormula: Equatable, Sendable {
    public enum Base: Equatable, Sendable {
        /// A building block the app can build live examples for.
        case slot(GrammarSlot)
        /// Written text from a rule without slots ("plain form").
        case text(String)
    }

    public var base: Base
    /// Every slot of the rule the base comes from (empty for a written pattern).
    public var slots: [GrammarSlot]
    /// The endings, distinct, in rule order.
    public var endings: [String]
    /// For a written pattern, the first written example using each ending ("はず": "行くはず").
    /// Slotted formulas build theirs live (`AttachmentRule.example`).
    public var examples: [String: String]

    /// The rule takes several plain forms (now, not, past, past not): the header says "plain form"
    /// rather than the first one's name.
    public var isPlainForm: Bool {
        slots.count > 1 && slots.allSatisfy { [.plain, .plainNeg, .plainPast, .plainPastNeg].contains($0) }
    }

    public init(base: Base, slots: [GrammarSlot] = [], endings: [String], examples: [String: String] = [:]) {
        self.base = base
        self.slots = slots
        self.endings = endings
        self.examples = examples
    }
}

public extension GrammarPoint {
    /// The formula header: from the rules with slots and an ending when there are any, otherwise
    /// from the first rule's written pattern when it reads "<base> + <ending> / <ending>…".
    /// Nil when neither gives one, or when the endings would not cover every part of the title
    /// (a formula must never present one part of a lesson, such as the ichidan-only rule, as the
    /// whole pattern).
    var formula: GrammarFormula? {
        let slotted = attachment.filter { !$0.slots.isEmpty && $0.then != nil }
        let candidate: GrammarFormula?
        if let first = slotted.first, let slot = first.slots.first {
            var endings: [String] = [], slots: [GrammarSlot] = []
            for rule in slotted {
                if !endings.contains(rule.then!) { endings.append(rule.then!) }
                for slot in rule.slots where !slots.contains(slot) { slots.append(slot) }
            }
            candidate = GrammarFormula(base: .slot(slot), slots: slots, endings: endings)
        } else {
            candidate = writtenFormula
        }
        guard let candidate, coversTitle(candidate.endings) else { return nil }
        return candidate
    }

    private var writtenFormula: GrammarFormula? {
        guard let rule = attachment.first, !rule.pattern.contains(";") else { return nil }
        let parts = rule.pattern.components(separatedBy: " + ")
        guard parts.count == 2 else { return nil }
        let base = parts[0].trimmingCharacters(in: .whitespaces)
        let endings = parts[1].components(separatedBy: "/").map(Self.withoutNote).filter { !$0.isEmpty }
        guard !base.isEmpty, !endings.isEmpty else { return nil }
        var examples: [String: String] = [:]
        let written = attachment.flatMap { $0.example.components(separatedBy: " / ") }
            .map { $0.components(separatedBy: "→ ").last!.trimmingCharacters(in: .whitespaces) }
        for ending in endings {
            examples[ending] = written.first { $0.hasSuffix(ending) }
        }
        return GrammarFormula(base: .text(base), endings: endings, examples: examples)
    }

    /// Every part of the title (split on ・, without 〜, two characters or more) matches an ending,
    /// one containing the other: はず・かもしれない・わけ is covered by its three endings, ている・てある
    /// is not covered by いる alone.
    private func coversTitle(_ endings: [String]) -> Bool {
        let parts = title.components(separatedBy: "・")
            .map { $0.replacingOccurrences(of: "〜", with: "").trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 2 }
        return parts.allSatisfy { part in endings.contains { $0.contains(part) || part.contains($0) } }
    }

    /// "そうだ (hearsay)" → "そうだ".
    private static func withoutNote(_ text: String) -> String {
        (text.components(separatedBy: "(").first ?? text).trimmingCharacters(in: .whitespaces)
    }

    /// Correct sentences to line a pitfall's wrong form up against: its own examples, then the
    /// lesson's written attachment examples (学生かもしれない), then its usage examples.
    func mistakeCandidates(for pitfall: GrammarPitfall) -> [String] {
        let written = attachment.flatMap { $0.example.components(separatedBy: " / ") }
            .map { $0.components(separatedBy: "→ ").last!.trimmingCharacters(in: .whitespaces) }
        return pitfall.examples.map(\.jp) + written + usages.flatMap { $0.examples.map(\.jp) }
    }
}
