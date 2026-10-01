/// Word classes a grammar ending can attach to. Deliberately separate
/// from `VerbType`, which classifies verbs only.
public enum WordClass: String, Codable, Hashable, Sendable {
    case verb
    case iAdjective = "i-adjective"
    case naAdjective = "na-adjective"
    case noun
}

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

    public init(wordClass: WordClass, condition: String? = nil, pattern: String, example: String, note: String? = nil) {
        self.wordClass = wordClass
        self.condition = condition
        self.pattern = pattern
        self.example = example
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case wordClass = "word_class"
        case condition
        case pattern
        case example
        case note
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
        related: [String]
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
