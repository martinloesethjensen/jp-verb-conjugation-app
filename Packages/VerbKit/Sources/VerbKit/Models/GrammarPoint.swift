public enum GrammarRegister: String, Codable, Hashable, Sendable {
    case polite
    case casual
    case formal
}

public struct GrammarExample: Codable, Hashable, Sendable {
    public var jp: String
    public var en: String

    public init(jp: String, en: String) {
        self.jp = jp
        self.en = en
    }
}

public struct GrammarUsage: Codable, Hashable, Sendable {
    public var heading: String
    public var explanation: String
    public var examples: [GrammarExample]

    public init(heading: String, explanation: String, examples: [GrammarExample]) {
        self.heading = heading
        self.explanation = explanation
        self.examples = examples
    }
}

/// How the ending attaches to one word class. `condition` narrows a rule
/// to part of a class (e.g. na-adjectives in the non-past affirmative
/// take なんです, but in the past take だったんです).
public struct AttachmentRule: Codable, Hashable, Sendable {
    public var wordClass: WordClass
    public var condition: String?
    public var pattern: String
    public var example: String
    public var note: String?
    /// The building blocks the pattern attaches to. Empty for a rule that is free text only.
    public var slots: [GrammarSlot]
    /// For な-adjectives and nouns in the `plain` slot: だ becomes な (しずかなので).
    public var daToNa: Bool
    /// What follows the slot (ので, すぎる). Nil when the rule only tags its slots.
    public var then: String?

    public init(
        wordClass: WordClass, condition: String? = nil, pattern: String, example: String, note: String? = nil,
        slots: [GrammarSlot] = [], daToNa: Bool = false, then: String? = nil
    ) {
        self.wordClass = wordClass
        self.condition = condition
        self.pattern = pattern
        self.example = example
        self.note = note
        self.slots = slots
        self.daToNa = daToNa
        self.then = then
    }

    enum CodingKeys: String, CodingKey {
        case wordClass = "word_class"
        case condition
        case pattern
        case example
        case note
        case slots
        case daToNa = "da_to_na"
        case then
    }

    /// The new fields may be absent, so lessons published before slots still decode.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        wordClass = try c.decode(WordClass.self, forKey: .wordClass)
        condition = try c.decodeIfPresent(String.self, forKey: .condition)
        pattern = try c.decode(String.self, forKey: .pattern)
        example = try c.decode(String.self, forKey: .example)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        slots = try c.decodeIfPresent([GrammarSlot].self, forKey: .slots) ?? []
        daToNa = try c.decodeIfPresent(Bool.self, forKey: .daToNa) ?? false
        then = try c.decodeIfPresent(String.self, forKey: .then)
    }

    /// The pattern built for `word` in `slot` (しずか + なので), or nil when the rule is for
    /// another class, does not list the slot, has no ending, or the word lacks the form.
    public func build(_ word: SlotSource, slot: GrammarSlot) -> String? {
        guard word.wordClass == wordClass, slots.contains(slot), let then,
              let form = word.form(for: slot, daToNa: daToNa) else { return nil }
        return form + then
    }
}

/// "Don't confuse with": a pattern learners mix this one up with, and how they differ.
public struct GrammarContrast: Codable, Hashable, Sendable {
    public var pattern: String
    /// Another lesson's id, when the pattern has one.
    public var id: String?
    public var explanation: String
    public var examples: [GrammarExample]

    public init(pattern: String, id: String? = nil, explanation: String, examples: [GrammarExample] = []) {
        self.pattern = pattern
        self.id = id
        self.explanation = explanation
        self.examples = examples
    }

    enum CodingKeys: String, CodingKey {
        case pattern, id, explanation, examples
    }

    /// `id` and `examples` may be omitted from the JSON.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pattern = try c.decode(String.self, forKey: .pattern)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        explanation = try c.decode(String.self, forKey: .explanation)
        examples = try c.decodeIfPresent([GrammarExample].self, forKey: .examples) ?? []
    }
}

/// A common mistake or nuance worth calling out ("Watch out" on the
/// detail page). Same shape as a usage, but examples may be empty.
public struct GrammarPitfall: Codable, Hashable, Sendable {
    public var heading: String
    public var explanation: String
    public var examples: [GrammarExample]

    public init(heading: String, explanation: String, examples: [GrammarExample] = []) {
        self.heading = heading
        self.explanation = explanation
        self.examples = examples
    }

    enum CodingKeys: String, CodingKey {
        case heading, explanation, examples
    }

    /// `examples` may be omitted from the JSON.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        heading = try container.decode(String.self, forKey: .heading)
        explanation = try container.decode(String.self, forKey: .explanation)
        examples = try container.decodeIfPresent([GrammarExample].self, forKey: .examples) ?? []
    }
}

public struct GrammarConjugation: Codable, Hashable, Sendable {
    public var form: String
    public var register: GrammarRegister
    public var note: String?

    public init(form: String, register: GrammarRegister, note: String? = nil) {
        self.form = form
        self.register = register
        self.note = note
    }
}

public struct GrammarPoint: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var summary: String
    public var jlpt: JLPTLevel?
    public var usages: [GrammarUsage]
    public var attachment: [AttachmentRule]
    public var conjugations: [GrammarConjugation]
    public var pitfalls: [GrammarPitfall]
    public var related: [String]
    /// Patterns this one is often confused with. Empty for most lessons.
    public var contrasts: [GrammarContrast]

    /// The id verb detail pages link to for the んです lesson.
    public static let nDesuID = "n-desu"

    /// The id verb detail pages link to for the potential-form lesson.
    public static let potentialID = "potential"

    /// True when the lesson has an attachment rule for verbs. The verb page's
    /// Grammar section lists exactly these lessons.
    public var attachesToVerbs: Bool {
        attachment.contains { $0.wordClass == .verb }
    }

    public init(
        id: String,
        title: String,
        summary: String,
        jlpt: JLPTLevel? = nil,
        usages: [GrammarUsage],
        attachment: [AttachmentRule],
        conjugations: [GrammarConjugation],
        pitfalls: [GrammarPitfall],
        related: [String],
        contrasts: [GrammarContrast] = []
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.jlpt = jlpt
        self.usages = usages
        self.attachment = attachment
        self.conjugations = conjugations
        self.pitfalls = pitfalls
        self.related = related
        self.contrasts = contrasts
    }

    enum CodingKeys: String, CodingKey {
        case id, title, summary, jlpt, usages, attachment, conjugations, pitfalls, related, contrasts
    }

    /// `contrasts` may be omitted from the JSON.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decode(String.self, forKey: .summary)
        jlpt = try c.decodeIfPresent(JLPTLevel.self, forKey: .jlpt)
        usages = try c.decode([GrammarUsage].self, forKey: .usages)
        attachment = try c.decode([AttachmentRule].self, forKey: .attachment)
        conjugations = try c.decode([GrammarConjugation].self, forKey: .conjugations)
        pitfalls = try c.decode([GrammarPitfall].self, forKey: .pitfalls)
        related = try c.decode([String].self, forKey: .related)
        contrasts = try c.decodeIfPresent([GrammarContrast].self, forKey: .contrasts) ?? []
    }
}

public struct GrammarDataFile: Codable, Sendable {
    public var version: String
    public var description: String
    public var grammar: [GrammarPoint]

    public init(version: String, description: String, grammar: [GrammarPoint]) {
        self.version = version
        self.description = description
        self.grammar = grammar
    }
}

public extension Sequence where Element == GrammarPoint {
    /// The lessons that attach to verbs, in the order given (the Grammar tab's
    /// order). Empty until grammar has synced, so callers can hide on empty.
    var attachingToVerbs: [GrammarPoint] {
        filter(\.attachesToVerbs)
    }
}
