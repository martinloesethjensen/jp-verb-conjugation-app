public struct Verb: Codable, Hashable, Identifiable, Sendable {
    public var type: VerbType
    public var label: String
    public var dict: String
    public var kanji: String?
    public var meaning: String
    public var description: String
    public var notes: String?
    public var teGroup: TeGroup?
    public var jlpt: JLPTLevel?
    public var forms: VerbForms
    public var examples: [VerbExample]
    /// Common chunks the verb is used in (シャワーを浴びる). Optional in verbs.json, so data
    /// published before collocations existed decodes with none.
    public var collocations: [VerbCollocation]
    /// Set only where a homophone's `dict` would collide with another verb's, as `dict:kanji`
    /// (`きる:切る`). Once shipped it never changes, even if the verb's spelling is corrected.
    /// See docs/superpowers/specs/2026-10-17-verb-id-scheme-design.md.
    public var explicitID: String?

    /// The stable identity that favourites, quiz history, widget configuration and links use:
    /// the explicit id when there is one, otherwise the dictionary form.
    public var id: String { explicitID ?? dict }

    /// The title shown in widgets, Spotlight, intents and lists: the dictionary form,
    /// with the kanji in parentheses when the verb has one.
    public var displayTitle: String { kanji.map { "\(dict) (\($0))" } ?? dict }

    enum CodingKeys: String, CodingKey {
        case type, label, dict, kanji, meaning, description, notes, teGroup, jlpt, forms, examples, collocations
        case explicitID = "id"
    }

    public init(
        type: VerbType,
        label: String,
        dict: String,
        kanji: String?,
        meaning: String,
        description: String,
        notes: String? = nil,
        teGroup: TeGroup? = nil,
        jlpt: JLPTLevel? = nil,
        forms: VerbForms,
        examples: [VerbExample],
        collocations: [VerbCollocation] = [],
        id explicitID: String? = nil
    ) {
        self.type = type
        self.label = label
        self.dict = dict
        self.kanji = kanji
        self.meaning = meaning
        self.description = description
        self.notes = notes
        self.teGroup = teGroup
        self.jlpt = jlpt
        self.forms = forms
        self.examples = examples
        self.collocations = collocations
        self.explicitID = explicitID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(VerbType.self, forKey: .type)
        label = try container.decode(String.self, forKey: .label)
        dict = try container.decode(String.self, forKey: .dict)
        kanji = try container.decodeIfPresent(String.self, forKey: .kanji)
        meaning = try container.decode(String.self, forKey: .meaning)
        description = try container.decode(String.self, forKey: .description)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        teGroup = try container.decodeIfPresent(TeGroup.self, forKey: .teGroup)
        jlpt = try container.decodeIfPresent(JLPTLevel.self, forKey: .jlpt)
        forms = try container.decode(VerbForms.self, forKey: .forms)
        examples = try container.decode([VerbExample].self, forKey: .examples)
        collocations = try container.decodeIfPresent([VerbCollocation].self, forKey: .collocations) ?? []
        explicitID = try container.decodeIfPresent(String.self, forKey: .explicitID)
    }
}
