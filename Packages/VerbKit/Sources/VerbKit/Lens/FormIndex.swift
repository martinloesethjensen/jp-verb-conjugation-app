/// One reading of a surface: this verb, in this form, written this way.
public struct FormHit: Hashable, Sendable {
    public enum Script: String, Hashable, Sendable {
        /// As the data stores it: たべられる.
        case kana
        /// Derived by `KanjiSpelling`: 食べられる.
        case kanji
    }

    /// `Verb.id`, never `dict`, so the two きる stay apart.
    public let verbID: String
    public let formID: FormID
    public let script: Script

    public init(verbID: String, formID: FormID, script: Script) {
        self.verbID = verbID
        self.formID = formID
        self.script = script
    }
}

/// How many readings a surface has, and of how many verbs.
public enum FormAmbiguity: Hashable, Sendable {
    /// One verb in one form.
    case unique
    /// One verb in several forms: a ru-verb's passive and potential (食べられる).
    case sameVerb
    /// Several verbs: 言った / 行った in kana (いった), 着る / 来る (きた), 入れる / 入る's potential.
    case crossVerb
}

public extension Array where Element == FormHit {
    /// The verbs these hits name, without repeats, in order.
    var verbIDs: [String] {
        var seen = Set<String>()
        return map(\.verbID).filter { seen.insert($0).inserted }
    }

    var ambiguity: FormAmbiguity {
        if count <= 1 { return .unique }
        return verbIDs.count == 1 ? .sameVerb : .crossVerb
    }
}

/// A stem that conjugates on by rule: a derived form with its last kana dropped.
/// The data lists 食べさせられる but not 食べさせられなかった, so #145's tail rules
/// attach ない, た, ます… to the stem 食べさせられ.
public struct StemHit: Hashable, Sendable {
    public enum Pattern: String, Hashable, Sendable {
        /// The form ends in る and conjugates like a ru-verb: passive, causative,
        /// causative-passive, potential.
        case ruVerb
        /// The form ends in い and conjugates like an i-adjective: たい and the ない forms.
        case iAdjective
    }

    public let verbID: String
    /// The form the stem comes from (`causative_passive` for 食べさせられ).
    public let formID: FormID
    public let script: FormHit.Script
    public let pattern: Pattern

    public init(verbID: String, formID: FormID, script: FormHit.Script, pattern: Pattern) {
        self.verbID = verbID
        self.formID = formID
        self.script = script
        self.pattern = pattern
    }
}

/// Every surface the app can generate, in kana and in kanji, mapped back to the verb and
/// form it comes from: the shared base of the Sentence lens (#142) and of "What form is
/// this?" (#110). Built in one pass from the verbs and the catalogue, so it always agrees
/// with what the verb pages show. A surface can have several readings; lookups return all
/// of them and never pick one.
public struct FormIndex: Sendable {
    /// The derived forms whose stems `stemMatches` finds, and how they conjugate on.
    /// `causative_passive_short` and `pot_short_neg` have the same shapes as their
    /// longer siblings (のまされる, 飲めない), so they're stems too.
    public static let stemForms: [FormID: StemHit.Pattern] = [
        "passive": .ruVerb, "causative": .ruVerb, "causative_passive": .ruVerb,
        "causative_passive_short": .ruVerb, "potential": .ruVerb,
        "tai": .iAdjective, "short_neg": .iAdjective, "pot_short_neg": .iAdjective,
    ]

    /// A surface found in a text.
    public struct Match: Sendable {
        public let range: Range<String.Index>
        public let surface: String
        public let hits: [FormHit]
    }

    /// A derived stem found in a text.
    public struct StemMatch: Sendable {
        public let range: Range<String.Index>
        public let stem: String
        public let hits: [StemHit]
    }

    /// Sizes, for the pinned regression counts and the scaling test.
    public struct Statistics: Hashable, Sendable {
        /// Form strings indexed: one per form a verb has in the catalogue.
        public var forms = 0
        /// Distinct surfaces, and how many are kana or kanji.
        public var surfaces = 0
        public var kanaSurfaces = 0
        public var kanjiSurfaces = 0
        /// Surfaces with more than one hit, split by `FormAmbiguity`.
        public var sameVerbAmbiguous = 0
        public var crossVerbAmbiguous = 0
        public var ambiguous: Int { sameVerbAmbiguous + crossVerbAmbiguous }
        /// Kana forms of verbs with a `kanji` that `KanjiSpelling` couldn't spell. Zero on real data.
        public var spellingFailures = 0
        public var stems = 0
        /// Trie nodes across surfaces and stems: the memory the index holds.
        public var nodes = 0
    }

    private let surfaceTrie: SurfaceTrie<FormHit>
    private let stemTrie: SurfaceTrie<StemHit>
    public let statistics: Statistics

    /// Indexes every form in `catalogue` that each verb has, in kana and, when the verb
    /// has a `kanji`, in kanji. Hits are in verb order, then catalogue order. The
    /// catalogue is passed in rather than read from `FormCatalogue.bundled`, so a synced
    /// one (#100) or a test one works the same; `FormIndexCache` rebuilds on a change.
    public init(verbs: [Verb], catalogue: FormCatalogue) {
        var surfaces = SurfaceTrie<FormHit>()
        var stems = SurfaceTrie<StemHit>()
        var statistics = Statistics()
        let specs = catalogue.specs(for: .verb)
        for verb in verbs {
            let forms = Word(verb).forms
            let spelling = KanjiSpelling(verb)
            for spec in specs {
                guard let kana = forms[spec.id], !kana.isEmpty else { continue }
                statistics.forms += 1
                surfaces.insert(kana, FormHit(verbID: verb.id, formID: spec.id, script: .kana))
                let kanji = spelling?.spell(kana)
                if let kanji {
                    surfaces.insert(kanji, FormHit(verbID: verb.id, formID: spec.id, script: .kanji))
                } else if spelling != nil {
                    statistics.spellingFailures += 1
                }
                guard let pattern = Self.stemForms[spec.id],
                      kana.hasSuffix(pattern == .ruVerb ? "る" : "い") else { continue }
                let stem = String(kana.dropLast())
                stems.insert(stem, StemHit(verbID: verb.id, formID: spec.id, script: .kana, pattern: pattern))
                if let kanji {
                    stems.insert(String(kanji.dropLast()), StemHit(verbID: verb.id, formID: spec.id, script: .kanji, pattern: pattern))
                }
            }
        }
        for entry in surfaces.entries {
            statistics.surfaces += 1
            if entry.hits.contains(where: { $0.script == .kana }) { statistics.kanaSurfaces += 1 }
            if entry.hits.contains(where: { $0.script == .kanji }) { statistics.kanjiSurfaces += 1 }
            switch entry.hits.ambiguity {
            case .unique: break
            case .sameVerb: statistics.sameVerbAmbiguous += 1
            case .crossVerb: statistics.crossVerbAmbiguous += 1
            }
        }
        statistics.stems = stems.entries.count
        statistics.nodes = surfaces.nodeCount + stems.nodeCount
        self.surfaceTrie = surfaces
        self.stemTrie = stems
        self.statistics = statistics
    }

    /// Every reading of exactly `surface`; empty when the app generates no such form.
    public func hits(for surface: some StringProtocol) -> [FormHit] {
        surfaceTrie.hits(for: surface)
    }

    /// Every reading of exactly `stem` as a derived stem; empty when it isn't one.
    public func stemHits(for stem: some StringProtocol) -> [StemHit] {
        stemTrie.hits(for: stem)
    }

    /// Every surface that starts at `start` in `text`, longest first: 食べさせられる,
    /// then 食べさせ, then 食べ… The longest isn't always right (十分かかります holds
    /// 借ります's かります), so #145 checks each against word boundaries.
    public func matches(in text: String, from start: String.Index) -> [Match] {
        surfaceTrie.prefixes(of: text, from: start).map { prefix in
            let entry = surfaceTrie.entries[prefix.entry]
            return Match(range: start..<prefix.end, surface: entry.surface, hits: entry.hits)
        }
    }

    /// The longest surface that starts at `start` in `text`, if any.
    public func longestMatch(in text: String, from start: String.Index) -> Match? {
        matches(in: text, from: start).first
    }

    /// Every derived stem that starts at `start` in `text`, longest first.
    public func stemMatches(in text: String, from start: String.Index) -> [StemMatch] {
        stemTrie.prefixes(of: text, from: start).map { prefix in
            let entry = stemTrie.entries[prefix.entry]
            return StemMatch(range: start..<prefix.end, stem: entry.surface, hits: entry.hits)
        }
    }

    /// Every surface the index holds, in the order first indexed.
    public var surfaces: [String] {
        surfaceTrie.entries.map(\.surface)
    }

    /// The surfaces with more than one reading of the given kind, in the order first indexed.
    public func ambiguousSurfaces(_ ambiguity: FormAmbiguity) -> [String] {
        surfaceTrie.entries.filter { $0.hits.ambiguity == ambiguity }.map(\.surface)
    }
}
