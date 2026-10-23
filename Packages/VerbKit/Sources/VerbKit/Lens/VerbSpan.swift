/// One part of how a verb span is built: 食べさせられ (causative-passive) ▸ なかった (plain
/// past negative). The tap sheet lists the parts and says which ones were built by rule.
public struct ChainPart: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// A catalogue form, labelled by `FormCatalogue`. The first part is the index's form
        /// or derived stem (食べさせられ is `causative_passive`); a later one is the ending of
        /// that form (なかった is `short_past_neg`'s).
        case form(FormID)
        /// The masu stem, as a noun of purpose before に (見に行く, 遊びに行く).
        case stem
        /// An ending or auxiliary the catalogue has no form for, labelled here:
        /// "てしまう · polite past", "です".
        case auxiliary(String)
    }

    public let surface: String
    public let kind: Kind
    /// True when the tail rules built this part rather than the index listing it.
    public let isRuleBuilt: Bool

    public init(surface: String, kind: Kind, isRuleBuilt: Bool) {
        self.surface = surface
        self.kind = kind
        self.isRuleBuilt = isRuleBuilt
    }
}

/// One candidate for a verb span: this verb, built this way.
public struct VerbCandidate: Hashable, Sendable {
    /// `Verb.id`, never `dict`.
    public let verbID: String
    public let chain: [ChainPart]

    public init(verbID: String, chain: [ChainPart]) {
        self.verbID = verbID
        self.chain = chain
    }

    /// The catalogue form when the span is exactly one generated form (食べました is
    /// `masu_past`); nil for a chain the tail rules built.
    public var formID: FormID? {
        guard chain.count == 1, let part = chain.first, !part.isRuleBuilt, case .form(let id) = part.kind else { return nil }
        return id
    }

    public var isRuleBuilt: Bool { chain.contains(where: \.isRuleBuilt) }
}

/// A verb the matcher found in a sentence.
public struct VerbSpan: Hashable, Sendable {
    public enum Status: Hashable, Sendable {
        /// One candidate.
        case known
        /// Several candidates, all in `candidates`: kana きた (来る or 着る), 食べられる
        /// (passive or potential). The sheet lets the learner choose.
        case ambiguous
        /// Looks like a conjugated verb the app doesn't have (降ったら): greyed as "not in
        /// the app yet", with `guesses` at its dictionary form.
        case notInApp
    }

    /// The span in the text passed to `VerbMatcher.spans(in:)`.
    public let range: Range<String.Index>
    /// The verb as written, without any spaces a transcript put inside it.
    public let surface: String
    public let status: Status
    /// Every candidate, in index order; empty for `.notInApp`.
    public let candidates: [VerbCandidate]
    /// For `.notInApp`, the probable dictionary forms, best first (降っ → 降る, 降う, 降つ).
    /// Guesses from the spelling alone, so the sheet says "probably".
    public let guesses: [String]

    public init(range: Range<String.Index>, surface: String, status: Status, candidates: [VerbCandidate], guesses: [String] = []) {
        self.range = range
        self.surface = surface
        self.status = status
        self.candidates = candidates
        self.guesses = guesses
    }

    /// The verbs the candidates name, without repeats, in order.
    public var verbIDs: [String] {
        var seen = Set<String>()
        return candidates.map(\.verbID).filter { seen.insert($0).inserted }
    }
}
