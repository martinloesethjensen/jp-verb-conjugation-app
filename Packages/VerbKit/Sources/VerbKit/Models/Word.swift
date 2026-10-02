import Foundation

/// An example sentence for one form of a word.
public struct WordExample: Codable, Hashable, Sendable {
    public var form: FormID
    public var jp: String
    public var en: String

    public init(form: FormID, jp: String, en: String) {
        self.form = form
        self.jp = jp
        self.en = en
    }
}

/// What only verbs have.
public struct VerbTraits: Hashable, Sendable {
    public var type: VerbType
    /// The display label ("Ru-verb"), stored in the verb data.
    public var label: String
    public var teGroup: TeGroup?

    public init(type: VerbType, label: String, teGroup: TeGroup? = nil) {
        self.type = type
        self.label = label
        self.teGroup = teGroup
    }
}

/// A word of any class (verb, i-adjective, na-adjective, noun) with its forms.
/// Which forms exist is the `FormCatalogue`'s business; `forms` just holds them.
public struct Word: Hashable, Identifiable, Sendable {
    public var wordClass: WordClass
    /// The kana citation form: たべる, たかい, しずか, がくせい.
    public var dict: String
    public var kanji: String?
    public var meaning: String
    public var description: String
    public var notes: String?
    public var jlpt: JLPTLevel?
    public var forms: Conjugations
    /// Other accepted surfaces for a form, by form id (`しずかではありません`).
    public var alternates: [String: [String]]
    public var examples: [WordExample]
    /// Set exactly when `wordClass` is `.verb`.
    public var verb: VerbTraits?

    /// Unique across classes: the class and the citation form.
    public var id: String { "\(wordClass.rawValue):\(dict)" }

    /// The plain present affirmative form, which `FormSplit` compares other
    /// forms against; the citation form when the word has none.
    public var baseForm: String { forms[.shortPos] ?? dict }

    public init(
        wordClass: WordClass,
        dict: String,
        kanji: String? = nil,
        meaning: String,
        description: String,
        notes: String? = nil,
        jlpt: JLPTLevel? = nil,
        forms: Conjugations,
        alternates: [String: [String]] = [:],
        examples: [WordExample] = [],
        verb: VerbTraits? = nil
    ) {
        self.wordClass = wordClass
        self.dict = dict
        self.kanji = kanji
        self.meaning = meaning
        self.description = description
        self.notes = notes
        self.jlpt = jlpt
        self.forms = forms
        self.alternates = alternates
        self.examples = examples
        self.verb = verb
    }
}

extension Word: Leveled {}

public extension Word {
    /// A word from today's `Verb`, with the same forms and examples. Bridges
    /// the verb screens onto `Word` while they are migrated.
    init(_ verb: Verb) {
        // `VerbForms` encodes exactly the keys of a `forms` object in the data
        // file (nil forms are left out), so round-tripping it is the mapping.
        let encoded = (try? JSONEncoder().encode(verb.forms))
            .flatMap { try? JSONDecoder().decode(Conjugations.self, from: $0) }
        assert(encoded != nil, "VerbForms failed to round-trip for \(verb.dict)")
        self.init(
            wordClass: .verb,
            dict: verb.dict,
            kanji: verb.kanji,
            meaning: verb.meaning,
            description: verb.description,
            notes: verb.notes,
            jlpt: verb.jlpt,
            forms: encoded ?? Conjugations(),
            examples: verb.examples.map { WordExample(form: FormID(rawValue: $0.form.rawValue), jp: $0.jp, en: $0.en) },
            verb: VerbTraits(type: verb.type, label: verb.label, teGroup: verb.teGroup)
        )
    }
}

// The JSON shape of an entry in the word data files: `verbs.json` today, and
// the same fields plus `word_class` for the other classes. An entry without
// `word_class` is a verb, which is how every entry in `verbs.json` reads.
extension Word: Codable {
    enum CodingKeys: String, CodingKey {
        case wordClass = "word_class"
        case dict, kanji, meaning, description, notes, jlpt, forms
        case alternates = "alt"
        case examples
        case type, label, teGroup
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        wordClass = try c.decodeIfPresent(WordClass.self, forKey: .wordClass) ?? .verb
        dict = try c.decode(String.self, forKey: .dict)
        kanji = try c.decodeIfPresent(String.self, forKey: .kanji)
        meaning = try c.decode(String.self, forKey: .meaning)
        description = try c.decode(String.self, forKey: .description)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        jlpt = try c.decodeIfPresent(JLPTLevel.self, forKey: .jlpt)
        forms = try c.decode(Conjugations.self, forKey: .forms)
        alternates = try c.decodeIfPresent([String: [String]].self, forKey: .alternates) ?? [:]
        examples = try c.decodeIfPresent([WordExample].self, forKey: .examples) ?? []
        if wordClass == .verb {
            verb = VerbTraits(
                type: try c.decode(VerbType.self, forKey: .type),
                label: try c.decode(String.self, forKey: .label),
                teGroup: try c.decodeIfPresent(TeGroup.self, forKey: .teGroup)
            )
        } else {
            verb = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(wordClass, forKey: .wordClass)
        try c.encode(dict, forKey: .dict)
        try c.encodeIfPresent(kanji, forKey: .kanji)
        try c.encode(meaning, forKey: .meaning)
        try c.encode(description, forKey: .description)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(jlpt, forKey: .jlpt)
        try c.encode(forms, forKey: .forms)
        if !alternates.isEmpty { try c.encode(alternates, forKey: .alternates) }
        try c.encode(examples, forKey: .examples)
        if let verb {
            try c.encode(verb.type, forKey: .type)
            try c.encode(verb.label, forKey: .label)
            try c.encodeIfPresent(verb.teGroup, forKey: .teGroup)
        }
    }
}
