import Foundation

/// Which plain form a connection prompt wants, when the pattern takes more than one:
/// "negative · past". It names only what tells the forms apart, so 〜ほうがいいです asks
/// for "positive" and leaves the た-form to the learner.
public struct ConnectionCue: Equatable, Sendable {
    /// Nil when the tense doesn't tell the candidate forms apart.
    public var past: Bool?
    /// Nil when the polarity doesn't tell the candidate forms apart.
    public var negative: Bool?

    public init(past: Bool? = nil, negative: Bool? = nil) {
        self.past = past
        self.negative = negative
    }

    /// The cue for `slot` among every slot the pattern takes for this word class and ending.
    public init(for slot: GrammarSlot, among candidates: Set<GrammarSlot>) {
        guard let shape = slot.plainShape else {
            self.init()
            return
        }
        let others = candidates.subtracting([slot]).compactMap(\.plainShape)
        let polarityDiffers = others.contains { $0.negative != shape.negative }
        let tenseDiffers = others.contains { $0.negative == shape.negative && $0.past != shape.past }
        self.init(past: tenseDiffers ? shape.past : nil, negative: polarityDiffers ? shape.negative : nil)
    }

    /// "negative · past", "positive", or nil when there is nothing to tell apart.
    public var label: String? {
        let parts = [negative.map { $0 ? "negative" : "positive" }, past.map { $0 ? "past" : "present" }]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

extension GrammarSlot {
    /// Tense and polarity of a plain slot; nil for the stem and the て-form.
    var plainShape: (past: Bool, negative: Bool)? {
        switch self {
        case .plain: (false, false)
        case .plainNeg: (false, true)
        case .plainPast: (true, false)
        case .plainPastNeg: (true, true)
        case .stem, .te: nil
        }
    }
}

/// One connection question: a word and a pattern's ending, and the joined form to pick.
public struct ConnectionQuestion: Equatable, Sendable {
    public var grammarID: String
    public var grammarTitle: String
    public var wordClass: WordClass
    /// The word as the prompt shows it: its citation form (たべる, しずか).
    public var word: String
    /// What quiz history records the word under: `Verb.id` for a verb (so a homophone like
    /// きる:切る stays apart from 着る), the explicit id or citation form for another word.
    public var wordID: String
    public var kanji: String?
    public var meaning: String
    /// What follows the block (ので, すぎる).
    public var ending: String
    public var slot: GrammarSlot
    public var daToNa: Bool
    public var cue: ConnectionCue
    public var correct: String
    public var choices: [String]

    public init(
        grammarID: String, grammarTitle: String, wordClass: WordClass, word: String, kanji: String?,
        meaning: String, ending: String, slot: GrammarSlot, daToNa: Bool, cue: ConnectionCue,
        correct: String, choices: [String], wordID: String? = nil
    ) {
        self.grammarID = grammarID
        self.grammarTitle = grammarTitle
        self.wordClass = wordClass
        self.word = word
        self.wordID = wordID ?? word
        self.kanji = kanji
        self.meaning = meaning
        self.ending = ending
        self.slot = slot
        self.daToNa = daToNa
        self.cue = cue
        self.correct = correct
        self.choices = choices
    }

    /// The block the pattern needed, for the feedback after an answer:
    /// "な-adjectives take the plain form with だ → な before ので: しずかなので".
    public var explanation: String {
        let who = switch wordClass {
        case .verb: "Verbs"
        case .iAdjective: "い-adjectives"
        case .naAdjective: "な-adjectives"
        case .noun: "Nouns"
        }
        let block = switch slot {
        case .plain: daToNa ? "the plain form with だ → な" : "the plain form"
        case .plainNeg: "the plain negative (ない) form"
        case .plainPast: "the plain past (た) form"
        case .plainPastNeg: "the plain past negative (なかった) form"
        case .stem: "the stem"
        case .te: "the て-form"
        }
        return "\(who) take \(block) before \(ending): \(correct)"
    }

    /// The form id quiz history records the answer under: one per pattern and slot.
    public var attemptFormID: String { "connect:\(grammarID):\(slot.rawValue)" }
}

public extension GrammarPoint {
    /// True when some rule names its slots and an ending, so the lesson can be practised.
    var hasConnections: Bool {
        attachment.contains { $0.then != nil && !$0.slots.isEmpty }
    }
}

/// Up to `count` connection questions for the rules of `points` that have slots and an
/// ending. Each (rule, slot) is paired with the next verb or word of the rule's class from
/// a shuffled deck, cycling through the pairs so a lesson with two slots still fills a quiz
/// with other words. A verb that lacks the form a rule spells out is skipped for that rule
/// (わかる has no ましょう form, so the quiz never asks for わかりましょう).
/// No answer is asked twice. The distractors are the word's other blocks with the same
/// ending, the な form, and the dictionary form plus the ending (たかいすぎる, しずかので).
public func buildConnectionQuestions(
    points: [GrammarPoint], verbs: [Verb], words: [Word], count: Int
) -> [ConnectionQuestion] {
    guard count > 0 else { return [] }
    let sources = verbs.map(ConnectionSource.init) + words.map(ConnectionSource.init)
    let byClass = Dictionary(grouping: sources, by: \.wordClass)

    var entries: [ConnectionEntry] = []
    for point in points {
        let rules = point.attachment.filter { $0.then != nil }
        for rule in rules where byClass[rule.wordClass] != nil {
            let candidates = Set(rules.filter { $0.wordClass == rule.wordClass && $0.then == rule.then }.flatMap(\.slots))
            for slot in rule.slots {
                let excluded = rule.wordClass == .verb
                    ? Set(verbs.map(\.stableKey)).subtracting(rule.eligibleVerbs(slot, among: verbs).map(\.stableKey))
                    : []
                entries.append(ConnectionEntry(
                    point: point, rule: rule, slot: slot, candidates: candidates, excludedVerbs: excluded
                ))
            }
        }
    }
    guard !entries.isEmpty else { return [] }

    var questions: [ConnectionQuestion] = []
    var asked = Set<String>()
    var round: [ConnectionEntry] = []
    // Words are dealt from a shuffled deck per class, so every word comes up before any repeats.
    var decks: [WordClass: [ConnectionSource]] = [:]
    // Bounded: a small pool of words can run out of new answers before `count`.
    for _ in 0..<(count * 4 + entries.count) {
        guard questions.count < count else { break }
        if round.isEmpty { round = entries.shuffled() }
        let entry = round.removeLast()
        let wordClass = entry.rule.wordClass
        if decks[wordClass, default: []].isEmpty { decks[wordClass] = byClass[wordClass]?.shuffled() ?? [] }
        guard let source = decks[wordClass]?.popLast(),
              !entry.excludedVerbs.contains(source.slots.stableKey),
              let question = makeConnectionQuestion(entry, source),
              asked.insert(question.correct).inserted else { continue }
        questions.append(question)
    }
    return questions
}

private struct ConnectionEntry {
    let point: GrammarPoint
    let rule: AttachmentRule
    let slot: GrammarSlot
    /// Every slot the lesson takes for this class and ending, for the cue.
    let candidates: Set<GrammarSlot>
    /// `Verb.stableKey` of each verb that lacks the form this rule spells out in this slot.
    let excludedVerbs: Set<String>
}

/// A verb or a word, with what the prompt shows.
private struct ConnectionSource {
    let slots: SlotSource
    let wordClass: WordClass
    let kanji: String?
    let meaning: String

    init(_ verb: Verb) {
        slots = verb
        wordClass = .verb
        kanji = verb.kanji
        meaning = verb.meaning
    }

    init(_ word: Word) {
        slots = word
        wordClass = word.wordClass
        kanji = word.kanji
        meaning = word.meaning
    }
}

private func makeConnectionQuestion(_ entry: ConnectionEntry, _ source: ConnectionSource) -> ConnectionQuestion? {
    guard let then = entry.rule.then, let correct = entry.rule.build(source.slots, slot: entry.slot) else { return nil }
    // The dictionary form + ending is often grammatical as a general statement (飲むほうがいい),
    // so a lesson that picks a positive form without taking the plain one never marks it wrong.
    let skipsPlain = entry.slot.plainShape?.negative == false && !entry.candidates.contains(.plain)
    var wrong = GrammarSlot.allCases.filter { !(skipsPlain && $0 == .plain) }
        .compactMap { source.slots.form(for: $0) }.map { $0 + then }
    if !skipsPlain {
        if let na = source.slots.form(for: .plain, daToNa: true) { wrong.append(na + then) }
        wrong.append(source.slots.dict + then)
    }
    var seen: Set<String> = [correct]
    let distractors = Array(wrong.shuffled().filter { seen.insert($0).inserted }.prefix(3))
    guard !distractors.isEmpty else { return nil }
    return ConnectionQuestion(
        grammarID: entry.point.id, grammarTitle: entry.point.title, wordClass: source.wordClass,
        word: source.slots.dict, kanji: source.kanji, meaning: source.meaning, ending: then,
        slot: entry.slot, daToNa: entry.rule.daToNa,
        cue: ConnectionCue(for: entry.slot, among: entry.candidates),
        correct: correct, choices: ([correct] + distractors).shuffled(),
        wordID: source.slots.stableKey
    )
}
