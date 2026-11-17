import Foundation

/// One transitive/intransitive pair question (#58), built from a verb's `pair` phrase. Either the
/// verb is blanked and the choices are the two halves of the pair (会議が＿＿＿ → はじまる, not
/// はじめる), or the particle is blanked and the choices are を and が (会議＿＿＿始める → を).
public struct VerbPairQuestion: Equatable, Sendable, Identifiable {
    /// What is blanked.
    public enum Blank: String, Sendable, CaseIterable {
        case verb
        case particle
    }

    public var id: UUID
    public var blank: Blank
    /// The verb whose phrase is asked about.
    public var verbID: String
    public var verbTitle: String
    /// The verb's half of the pair, and its phrase and gloss (`ドアを開ける`, "open the door").
    public var transitivity: Transitivity
    public var phrase: String
    public var gloss: String
    /// The partner's phrase and gloss, shown after answering.
    public var partnerPhrase: String
    public var partnerGloss: String
    /// The partner's id, recorded as the mistake when its verb is picked.
    public var partnerID: String
    /// The phrase before and after the blank.
    public var before: String
    public var after: String
    public var answer: String
    /// `answer` and the one wrong choice, shuffled. For a verb blank these are the two verbs'
    /// dictionary forms in kana, so the quiz can write them in its script (`choiceVerbs`).
    public var choices: [String]
    /// For a verb blank, the verb each choice is the dictionary form of; empty for a particle blank.
    public var choiceVerbs: [String: Verb]

    public init(
        id: UUID = UUID(), blank: Blank, verbID: String, verbTitle: String, transitivity: Transitivity,
        phrase: String, gloss: String, partnerPhrase: String, partnerGloss: String, partnerID: String,
        before: String, after: String, answer: String, choices: [String], choiceVerbs: [String: Verb] = [:]
    ) {
        self.id = id
        self.blank = blank
        self.verbID = verbID
        self.verbTitle = verbTitle
        self.transitivity = transitivity
        self.phrase = phrase
        self.gloss = gloss
        self.partnerPhrase = partnerPhrase
        self.partnerGloss = partnerGloss
        self.partnerID = partnerID
        self.before = before
        self.after = after
        self.answer = answer
        self.choices = choices
        self.choiceVerbs = choiceVerbs
    }

    /// The phrase with the blank (＿＿＿) in place.
    public var blanked: String { before + QuizQuestion.blank + after }

    public func isCorrect(_ choice: String) -> Bool { choice == answer }
}

/// A pair phrase split at its particle and verb: `箱に本を入れる` → (`箱に本`, `を`, `入れる`). Nil
/// when the phrase does not end with the verb's kanji or kana spelling right after its particle
/// (the data check requires the ending and the particle, so this only drops odd phrasing).
struct PairPhraseParts: Equatable {
    var head: String
    var particle: String
    var verb: String

    init(head: String, particle: String, verb: String) {
        self.head = head
        self.particle = particle
        self.verb = verb
    }

    init?(verb: Verb, pair: VerbPair) {
        let spellings = [verb.kanji, verb.dict].compactMap { $0 }.filter { !$0.isEmpty }
        guard let spelling = spellings.first(where: { pair.jp.hasSuffix($0) }) else { return nil }
        let rest = pair.jp.dropLast(spelling.count)
        let particle = pair.transitivity.particle
        guard rest.hasSuffix(particle), rest.count > particle.count else { return nil }
        self.init(head: String(rest.dropLast(particle.count)), particle: particle, verb: spelling)
    }
}

/// Pair questions from the verbs' `pair` phrases: for each half whose partner is loaded, one
/// question with the verb blanked and one with the particle blanked. Both halves must be visible
/// under `levels`. Shuffled and capped at `count`.
public func buildVerbPairQuestions(verbs: [Verb], levels: LevelSettings = LevelSettings(), count: Int) -> [VerbPairQuestion] {
    guard count > 0 else { return [] }
    let visible = verbs.visible(in: levels)
    var questions: [VerbPairQuestion] = []
    for verb in visible {
        guard let pair = verb.pair, let partner = verb.pairPartner(in: visible), let partnerPair = partner.pair,
              let parts = PairPhraseParts(verb: verb, pair: pair),
              let partnerParts = PairPhraseParts(verb: partner, pair: partnerPair),
              verb.dict != partner.dict
        else { continue }
        func question(_ blank: VerbPairQuestion.Blank) -> VerbPairQuestion {
            let (before, after, answer, wrong): (String, String, String, String) = switch blank {
            case .verb: (parts.head + parts.particle, "", verb.dict, partner.dict)
            case .particle: (parts.head, parts.verb, parts.particle, partnerParts.particle)
            }
            return VerbPairQuestion(
                blank: blank, verbID: verb.id, verbTitle: verb.displayTitle, transitivity: pair.transitivity,
                phrase: pair.jp, gloss: pair.en, partnerPhrase: partnerPair.jp, partnerGloss: partnerPair.en,
                partnerID: partner.id, before: before, after: after, answer: answer, choices: [answer, wrong].shuffled(),
                choiceVerbs: blank == .verb ? [verb.dict: verb, partner.dict: partner] : [:]
            )
        }
        questions += VerbPairQuestion.Blank.allCases.map(question)
    }
    return Array(questions.shuffled().prefix(count))
}
