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
    /// The endings, distinct, in rule order.
    public var endings: [String]
    /// For a written pattern, the first written example using each ending ("はず": "行くはず").
    /// Slotted formulas build theirs live (`AttachmentRule.example`).
    public var examples: [String: String]

    public init(base: Base, endings: [String], examples: [String: String] = [:]) {
        self.base = base
        self.endings = endings
        self.examples = examples
    }
}

public extension GrammarPoint {
    /// The formula header: from the rules with slots and an ending when there are any, otherwise
    /// from the first rule's written pattern when it reads "<base> + <ending> / <ending>…".
    /// Nil when neither gives one.
    var formula: GrammarFormula? {
        let slotted = attachment.filter { !$0.slots.isEmpty && $0.then != nil }
        if let first = slotted.first, let slot = first.slots.first {
            var endings: [String] = []
            for rule in slotted where !endings.contains(rule.then!) { endings.append(rule.then!) }
            return GrammarFormula(base: .slot(slot), endings: endings)
        }
        guard let rule = attachment.first, !rule.pattern.contains(";") else { return nil }
        let parts = rule.pattern.components(separatedBy: " + ")
        guard parts.count == 2 else { return nil }
        let base = parts[0].trimmingCharacters(in: .whitespaces)
        let endings = parts[1].components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !base.isEmpty, !endings.isEmpty else { return nil }
        var examples: [String: String] = [:]
        let written = attachment.flatMap { $0.example.components(separatedBy: " / ") }
            .map { $0.components(separatedBy: "→ ").last!.trimmingCharacters(in: .whitespaces) }
        for ending in endings {
            examples[ending] = written.first { $0.hasSuffix(ending) }
        }
        return GrammarFormula(base: .text(base), endings: endings, examples: examples)
    }
}
