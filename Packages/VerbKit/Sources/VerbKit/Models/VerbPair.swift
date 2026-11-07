import Foundation

/// A verb's transitive/intransitive partner (自動詞・他動詞, #58): 開ける ↔ 開く. Each half holds its
/// own phrase, so the verb page can show `ドアを開ける ↔ ドアが開く` by reading both verbs.
/// See docs/superpowers/specs/2026-11-05-verb-pairs-design.md.
public struct VerbPair: Codable, Hashable, Sendable {
    /// The partner's `Verb.id`.
    public var verb: String
    /// This verb's half of the pair.
    public var transitivity: Transitivity
    /// A short phrase in this verb's dictionary form that shows its particle: `ドアを開ける`.
    public var jp: String
    public var en: String

    public init(verb: String, transitivity: Transitivity, jp: String, en: String) {
        self.verb = verb
        self.transitivity = transitivity
        self.jp = jp
        self.en = en
    }
}

public enum Transitivity: String, Codable, Hashable, Sendable {
    /// 他動詞: someone does it to something, marked with を.
    case transitive
    /// 自動詞: it happens by itself, marked with が.
    case intransitive

    /// The particle the phrase uses for this half.
    public var particle: String {
        switch self {
        case .transitive: "を"
        case .intransitive: "が"
        }
    }
}

public extension Verb {
    /// The partner verb, when this verb has a pair and the partner is in `verbs`.
    func pairPartner(in verbs: [Verb]) -> Verb? {
        guard let pair else { return nil }
        return verbs.first { $0.id == pair.verb }
    }
}
