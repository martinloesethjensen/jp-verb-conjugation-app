/// Where a verb span sits in its sentence, from the text right after it: the Sentence lens
/// (#142) changes politeness only on the verb that ends the sentence. 先週買った本 must not
/// become 先週買いました本, and a clause before 前に, から or ながら stays plain.
///
/// The rule looks at the next characters only, not at a parse: the span is final when the
/// text ends there, at sentence-ending punctuation, or after sentence-final particles (か,
/// ね, よ, よね, の…) that end the text or a sentence themselves. Anything else is
/// mid-sentence. Spaces are skipped, as the matcher skips them.
public struct SentenceContext: Hashable, Sendable {
    public enum Position: Hashable, Sendable {
        /// The verb ends the sentence: its register may change.
        case final(Ending)
        /// Something else follows (a noun, から, と, なら, が…): polarity and tense may
        /// change, the register stays.
        case midSentence
        /// A marker that fixes the verb's form follows: 前に takes the plain present, 後で
        /// the plain past, べき the dictionary form, so nothing changes.
        case fixed(marker: String)
    }

    /// How a final verb ends its sentence.
    public enum Ending: Hashable, Sendable {
        /// End of text or punctuation, possibly after ね, よ or a か that leads on to more
        /// particles (かな, かね): the span alone changes.
        case statement
        /// The question か, then the end or punctuation: 行きますか。 `range` covers the か
        /// and the punctuation after it, which a plain question replaces with ？.
        case question(range: Range<String.Index>)
        /// A question mark straight after the verb: 行く？ The polite question puts か
        /// before it.
        case questionMark
        /// The explanatory の: 行くの？ Its polite side is …んですか, more than one step.
        case explanatory
    }

    public let position: Position

    /// Punctuation that ends a sentence or a quoted one.
    static let terminators: Set<Character> = [
        "。", "．", ".", "！", "!", "？", "?", "…", "‥", "\n", "\r\n", "」", "』", "）", ")",
    ]
    static let questionMarks: Set<Character> = ["？", "?"]
    /// Punctuation a question か takes with it when a plain question drops the か.
    static let questionEnds: Set<Character> = ["。", "．", ".", "？", "?"]
    /// Sentence-final particles: any of them may start the run, which ends the sentence.
    static let finalParticles: [String] = ["か", "ね", "よ", "の"]
    /// Particles that may follow another final particle but never start the run: a plain
    /// verb + な is the negative imperative (行くな), not 行く + a softener.
    static let followingParticles: [String] = ["か", "ね", "よ", "の", "な"]
    /// Markers that fix the verb's form, longest first. 前 takes the plain present and 後
    /// the plain past (食べる前に, 食べた後で); べき takes the dictionary form (するべき); and
    /// ほうがいい pairs the past with the positive (寝たほうがいい, 寝ないほうがいい), so a
    /// one-facet flip there (寝なかったほうがいい) is wrong.
    static let fixingMarkers: [String] = [
        "前に", "まえに", "後で", "あとで", "後に", "あとに", "前", "後",
        "べき", "ほうがいい", "方がいい",
    ]

    public init(position: Position) {
        self.position = position
    }

    /// The context of the span at `range` in `text`.
    public init(span range: Range<String.Index>, in text: String) {
        let start = Self.skipSpaces(in: text, from: range.upperBound)
        let rest = text[start...]
        if let marker = Self.fixingMarkers.first(where: { rest.hasPrefix($0) }) {
            position = .fixed(marker: marker)
            return
        }
        if Self.endsSentence(text, at: start) {
            if let first = rest.first, Self.questionMarks.contains(first) {
                position = .final(.questionMark)
            } else {
                position = .final(.statement)
            }
            return
        }
        guard let first = Self.finalParticles.first(where: { rest.hasPrefix($0) }) else {
            position = .midSentence
            return
        }
        // Particles, one after another, then the end of the sentence.
        var end = text.index(start, offsetBy: first.count)
        var count = 1
        while !Self.endsSentence(text, at: Self.skipSpaces(in: text, from: end)) {
            guard let next = Self.followingParticles.first(where: { text[end...].hasPrefix($0) }) else {
                position = .midSentence
                return
            }
            end = text.index(end, offsetBy: next.count)
            count += 1
        }
        switch first {
        case "の":
            position = .final(.explanatory)
        case "か" where count == 1:
            // The か and the punctuation right after it, if any.
            let after = Self.skipSpaces(in: text, from: end)
            var questionEnd = end
            if after < text.endIndex, Self.questionEnds.contains(text[after]) {
                questionEnd = text.index(after: after)
            }
            position = .final(.question(range: start..<questionEnd))
        default:
            position = .final(.statement)
        }
    }

    public var isFinal: Bool {
        if case .final = position { return true }
        return false
    }

    private static func endsSentence(_ text: String, at index: String.Index) -> Bool {
        index == text.endIndex || terminators.contains(text[index])
    }

    private static func skipSpaces(in text: String, from index: String.Index) -> String.Index {
        var index = index
        while index < text.endIndex, text[index].isWhitespace, !terminators.contains(text[index]) {
            index = text.index(after: index)
        }
        return index
    }
}
