/// Finds the verbs in a sentence: the Sentence lens (#142) and, on one word, "What form is
/// this?" (#110). The research's tokenizer-gated hybrid:
///
/// 1. A verb starts and ends on a token boundary; punctuation and the end of the text count.
/// 2. From each token start it takes every index surface and derived stem there, extends them
///    with the tail rules (`ConjugationTail`), and keeps the longest that ends on a boundary.
/// 3. The token reading breaks ties the kanji can't: 入れる (いれ) vs 入る's potential (はいれ).
/// 4. A bare masu stem counts only before に (見に行く), so the nouns 休み and 話 don't match.
/// 5. Where no in-app verb fits, a token that looks like a conjugated verb (降っ + たら) is
///    greyed as not in the app, with a guess at its dictionary form.
/// 6. `LensStoplist` keeps すみません, どうして, じゃない and friends from being highlighted.
///
/// Spaces are ignored (speech transcripts put one before digits: 歩いて 10分), and nothing
/// relies on 、, which transcripts leave out. Matching is synchronous and costs the sentence
/// length times the longest surface, so re-running it on every transcript update is cheap.
public struct VerbMatcher: Sendable {
    private let index: FormIndex
    private let tokenizer: any Tokenizing
    private let spellings: [String: KanjiSpelling]
    /// Stems the index doesn't derive: masu stems, the stems of すぎる / やすい / にくい, て-forms
    /// without て for ちゃう, and the ら-less potential (起きれ).
    private let ruleStems: SurfaceTrie<RuleStem>

    struct RuleStem: Hashable, Sendable {
        enum Use: Hashable, Sendable {
            /// Takes the tails at this slot.
            case tails(ConjugationTail.Slot)
            /// A masu stem: a verb only before に.
            case purpose
        }

        let verbID: String
        let formID: FormID
        let use: Use
        let isRuleBuilt: Bool
    }

    /// `index` is the one `FormIndexCache` holds for `verbs`; the verbs give the readings that
    /// break kanji ties.
    public init(index: FormIndex, verbs: [Verb], tokenizer: any Tokenizing = SystemTokenizer()) {
        self.index = index
        self.tokenizer = tokenizer
        var spellings: [String: KanjiSpelling] = [:]
        for verb in verbs {
            spellings[verb.id] = KanjiSpelling(verb)
        }
        self.spellings = spellings
        var stems = SurfaceTrie<RuleStem>()
        for surface in index.surfaces {
            for hit in index.hits(for: surface) {
                func add(_ stem: some StringProtocol, _ use: RuleStem.Use, ruleBuilt: Bool = false) {
                    guard !stem.isEmpty else { return }
                    stems.insert(String(stem), RuleStem(verbID: hit.verbID, formID: hit.formID, use: use, isRuleBuilt: ruleBuilt))
                }
                switch hit.formID {
                case "masu_pos" where surface.hasSuffix("ます"):
                    add(surface.dropLast(2), .purpose)
                case "sugiru" where surface.hasSuffix("る"):
                    add(surface.dropLast(), .tails(.ruStem))
                case "yasui" where surface.hasSuffix("い"), "nikui" where surface.hasSuffix("い"):
                    add(surface.dropLast(), .tails(.adjStem))
                case "te" where surface.hasSuffix("て"):
                    add(surface.dropLast(), .tails(.chaStem))
                case "te" where surface.hasSuffix("で"):
                    add(surface.dropLast(), .tails(.jaStem))
                case "potential" where surface.hasSuffix("られる"):
                    // 起きられる → 起きれる: common, but not a form the data generates.
                    add(surface.dropLast(3) + "れ", .tails(.ruStem), ruleBuilt: true)
                default:
                    break
                }
            }
        }
        self.ruleStems = stems
    }

    /// The verbs in `text`, in order, without overlaps.
    public func spans(in text: String) -> [VerbSpan] {
        let compact = CompactText(text)
        let sentence = Sentence(compact.text, tokenizer.tokens(in: compact.text))
        let stopped = LensStoplist.ranges(in: sentence.text).sorted { $0.lowerBound < $1.lowerBound }
        var stop = 0
        var spans: [VerbSpan] = []
        var next = sentence.text.startIndex
        for position in sentence.tokens.indices {
            let start = sentence.tokens[position].range.lowerBound
            while stop < stopped.count, stopped[stop].upperBound <= start { stop += 1 }
            guard start >= next, stop == stopped.count || !stopped[stop].contains(start) else { continue }
            let found: VerbSpan?
            switch knownSpan(in: sentence, at: position) {
            case .span(let span): found = span
            case .ruledOut: found = nil
            case .none: found = greySpan(in: sentence, at: position)
            }
            guard let found else { continue }
            next = found.range.upperBound
            spans.append(compact.original(found))
        }
        return spans
    }

    // MARK: Verbs in the app

    private enum Known {
        case span(VerbSpan)
        /// Surfaces fit, but the context rules them all out.
        case ruledOut
        case none
    }

    private struct Found {
        let end: String.Index
        let candidate: VerbCandidate
    }

    private func knownSpan(in sentence: Sentence, at position: Int) -> Known {
        let text = sentence.text
        let start = sentence.tokens[position].range.lowerBound
        var found: [Found] = []
        func add(_ base: ChainPart, verbID: String, end: String.Index, slot: ConjugationTail.Slot?, alone: Bool) {
            if alone { found.append(Found(end: end, candidate: VerbCandidate(verbID: verbID, chain: [base]))) }
            guard let slot else { return }
            for tail in ConjugationTail.extensions(at: slot, in: text, from: end) {
                found.append(Found(end: tail.end, candidate: VerbCandidate(verbID: verbID, chain: [base] + tail.parts)))
            }
        }
        for match in index.matches(in: text, from: start) {
            for hit in match.hits {
                let base = ChainPart(surface: match.surface, kind: .form(hit.formID), isRuleBuilt: false)
                add(base, verbID: hit.verbID, end: match.range.upperBound, slot: ConjugationTail.slots[hit.formID], alone: true)
            }
        }
        // A stem is no word alone: it needs a tail.
        for match in index.stemMatches(in: text, from: start) {
            for hit in match.hits {
                let base = ChainPart(surface: match.stem, kind: .form(hit.formID), isRuleBuilt: false)
                add(base, verbID: hit.verbID, end: match.range.upperBound, slot: hit.pattern == .ruVerb ? .ruStem : .adjStem, alone: false)
            }
        }
        for prefix in ruleStems.prefixes(of: text, from: start) {
            let entry = ruleStems.entries[prefix.entry]
            for hit in entry.hits {
                switch hit.use {
                case .purpose:
                    guard text[prefix.end...].hasPrefix("に") else { continue }
                    let base = ChainPart(surface: entry.surface, kind: .stem, isRuleBuilt: false)
                    add(base, verbID: hit.verbID, end: prefix.end, slot: nil, alone: true)
                case .tails(let slot):
                    let base = ChainPart(surface: entry.surface, kind: .form(hit.formID), isRuleBuilt: hit.isRuleBuilt)
                    add(base, verbID: hit.verbID, end: prefix.end, slot: slot, alone: false)
                }
            }
        }
        found.removeAll { !sentence.boundaries.contains($0.end) }
        guard !found.isEmpty else { return .none }
        let before = text[..<start]
        found.removeAll { item in
            LensStoplist.excludes(verbID: item.candidate.verbID, surface: String(text[start..<item.end]), after: before)
        }
        guard let end = found.map(\.end).max() else { return .ruledOut }
        let range = start..<end
        let surface = String(text[range])
        var candidates = Self.preferListed(found.filter { $0.end == end }.map(\.candidate))
        candidates = breakTie(candidates, surface: surface, reading: sentence.reading(from: position, to: end))
        let status: VerbSpan.Status = candidates.count == 1 ? .known : .ambiguous
        return .span(VerbSpan(range: range, surface: surface, status: status, candidates: candidates))
    }

    /// Without repeats, and for each verb only the chains with the fewest rule-built parts:
    /// a form the catalogue lists beats the same span built by rule. 食べられます is the
    /// potential's `pot_masu_pos`, not also the passive stem + ます.
    static func preferListed(_ candidates: [VerbCandidate]) -> [VerbCandidate] {
        var fewest: [String: Int] = [:]
        for candidate in candidates {
            let count = candidate.chain.filter(\.isRuleBuilt).count
            fewest[candidate.verbID] = min(fewest[candidate.verbID] ?? .max, count)
        }
        var seen = Set<VerbCandidate>()
        return candidates.filter { candidate in
            candidate.chain.filter(\.isRuleBuilt).count == fewest[candidate.verbID] && seen.insert(candidate).inserted
        }
    }

    /// Keeps the verbs whose reading the tokenizer heard, when the kanji fits several:
    /// 入れ read いれ is 入れる, read はいれ it is 入る's potential; 出させ read ださ is 出す,
    /// read で it is 出る. Keeps all of them when the reading fits none or is missing.
    private func breakTie(_ candidates: [VerbCandidate], surface: String, reading: String?) -> [VerbCandidate] {
        guard let reading, Set(candidates.map(\.verbID)).count > 1,
              let first = surface.first, FuriganaDictionary.isKanji(first)
        else { return candidates }
        let heard = candidates.filter { candidate in
            guard let spelling = spellings[candidate.verbID], surface.hasPrefix(spelling.kanjiStem) else { return false }
            return spelling.readingStems.contains { reading.hasPrefix($0) }
        }
        return heard.isEmpty ? candidates : heard
    }

    // MARK: Verbs the app lacks

    /// Tokens that conjugate a verb, after its stem: 降っ + たら, 遅れ + た, 思い + ます.
    private static let conjugationTokens: Set<String> = [
        "た", "て", "たら", "ます", "まし", "ませ", "ましょう", "ない", "なかっ", "たり", "だ", "で", "ば", "う", "よう",
    ]
    /// Tokens a greyed span runs on through: 吸っ て は いけ ませ ん, 撮っ て も いい です.
    private static let continuationTokens: Set<String> = conjugationTokens.union([
        "い", "いる", "しまい", "しまう", "しまっ", "は", "も", "いい", "です", "いけ", "ん", "ください",
        "おき", "おい", "み", "くれ", "もらい", "もらっ", "もらえ",
    ])

    /// A verb the app doesn't have: a token that starts with kanji and is one kanji or
    /// kanji + okurigana (not an adjective's かっ, く or しい), followed by a conjugation
    /// token. A lone kanji + で, だ, ば or う is a noun (雨で, 家で), and so is anything + で
    /// or だ that doesn't end in ん or い (考えだ; not 読んだ, 泳いで). Kana-only verbs (いる,
    /// なる) can't be told from other words this way, so they're left alone.
    private func greySpan(in sentence: Sentence, at position: Int) -> VerbSpan? {
        let tokens = sentence.tokens
        let word = tokens[position].surface
        guard let first = word.first, let last = word.last, FuriganaDictionary.isKanji(first),
              word.count == 1 || !FuriganaDictionary.isKanji(last),
              !word.hasSuffix("かっ"), !word.hasSuffix("く"), !word.hasSuffix("しい"),
              position + 1 < tokens.count, tokens[position + 1].range.lowerBound == tokens[position].range.upperBound
        else { return nil }
        let following = tokens[position + 1].surface
        guard Self.conjugationTokens.contains(following),
              word.count > 1 || !["で", "だ", "ば", "う"].contains(following),
              !["で", "だ"].contains(following) || word.hasSuffix("ん") || word.hasSuffix("い")
        else { return nil }
        var end = tokens[position + 1].range.upperBound
        for token in tokens[(position + 2)...] {
            guard token.range.lowerBound == end, Self.continuationTokens.contains(token.surface) else { break }
            end = token.range.upperBound
        }
        let range = tokens[position].range.lowerBound..<end
        return VerbSpan(
            range: range, surface: String(sentence.text[range]), status: .notInApp, candidates: [],
            guesses: Self.dictionaryGuesses(stem: word, before: following)
        )
    }

    private static let iRow: [Character: Character] = [
        "い": "う", "き": "く", "ぎ": "ぐ", "し": "す", "ち": "つ", "に": "ぬ", "び": "ぶ", "み": "む", "り": "る",
    ]
    private static let aRow: [Character: Character] = [
        "わ": "う", "か": "く", "が": "ぐ", "さ": "す", "た": "つ", "な": "ぬ", "ば": "ぶ", "ま": "む", "ら": "る",
    ]

    /// Probable dictionary forms of a verb from the token before its ending, best first:
    /// 降っ → 降る, 降う, 降つ; 遅れ → 遅れる; 思い + ます → 思う; 守ら + ない → 守る.
    static func dictionaryGuesses(stem: String, before ending: String) -> [String] {
        let base = String(stem.dropLast())
        guard let last = stem.last, !FuriganaDictionary.isKanji(last) else { return [stem + "る"] }
        let masu = ["ます", "まし", "ませ", "ましょう"].contains(ending)
        switch last {
        case "っ": return ["る", "う", "つ"].map { base + $0 }
        case "ん": return ["む", "ぶ", "ぬ"].map { base + $0 }
        case "い" where masu: return [base + "う"]
        case "い": return [base + (ending.hasPrefix("で") || ending.hasPrefix("だ") ? "ぐ" : "く")]
        case "し": return [base + "す"]
        default:
            if let u = iRow[last] {
                // A godan masu stem (思い, 置き), or a ru-verb stem (起き): only a ru-verb's
                // stem takes た and て directly.
                return masu ? [base + String(u), stem + "る"] : [stem + "る"]
            }
            if let u = aRow[last], ending.hasPrefix("な") { return [base + String(u)] }
            return [stem + "る"]
        }
    }
}

/// The text the matcher works on: tokens, and the boundaries a verb may start and end on.
private struct Sentence {
    let text: String
    let tokens: [Token]
    let boundaries: Set<String.Index>

    init(_ text: String, _ tokens: [Token]) {
        self.text = text
        self.tokens = tokens
        var boundaries: Set<String.Index> = [text.endIndex]
        for token in tokens {
            boundaries.insert(token.range.lowerBound)
            boundaries.insert(token.range.upperBound)
        }
        self.boundaries = boundaries
    }

    /// The tokenizer's reading of the tokens from `position` up to `end`, or nil when one
    /// has none.
    func reading(from position: Int, to end: String.Index) -> String? {
        var reading = ""
        for token in tokens[position...] {
            guard token.range.lowerBound < end else { break }
            guard let part = token.reading else { return nil }
            reading += part
        }
        return reading.isEmpty ? nil : reading
    }
}

/// A text without its whitespace, mapped back to the original: speech transcripts put
/// spaces inside sentences (歩いて 10分), and a verb chain shouldn't break on one.
private struct CompactText {
    let text: String
    private let original: String
    /// Where each character of `text` sits in `original`; nil when nothing was removed.
    private let positions: [String.Index]?
    private let compactPositions: [String.Index]

    init(_ original: String) {
        self.original = original
        guard original.contains(where: \.isWhitespace) else {
            text = original
            positions = nil
            compactPositions = []
            return
        }
        var positions: [String.Index] = []
        var compact = ""
        for index in original.indices where !original[index].isWhitespace {
            positions.append(index)
            compact.append(original[index])
        }
        text = compact
        self.positions = positions
        compactPositions = Array(compact.indices)
    }

    /// `span` with its range in the original text.
    func original(_ span: VerbSpan) -> VerbSpan {
        guard let positions else { return span }
        let lower = compactPositions.partitionPoint { $0 < span.range.lowerBound }
        let upper = compactPositions.partitionPoint { $0 < span.range.upperBound }
        let start = positions[lower]
        let end = original.index(after: positions[upper - 1])
        return VerbSpan(
            range: start..<end, surface: span.surface, status: span.status,
            candidates: span.candidates, guesses: span.guesses
        )
    }
}

private extension Array {
    /// The first index whose element fails `belongs`, for an array where every element that
    /// satisfies it comes first.
    func partitionPoint(_ belongs: (Element) -> Bool) -> Int {
        var low = 0, high = count
        while low < high {
            let mid = (low + high) / 2
            if belongs(self[mid]) { low = mid + 1 } else { high = mid }
        }
        return low
    }
}
