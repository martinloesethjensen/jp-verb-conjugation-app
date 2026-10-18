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
    /// Set only where another verb has the same kana, for example `きる:切る`. Once shipped it
    /// never changes, even if the verb's kana or kanji is corrected.
    public var explicitID: String?

    /// What favourites, quiz history, widgets and links store: `dict`, unless a homophone
    /// needed an explicit id.
    public var id: String { explicitID ?? dict }

    enum CodingKeys: String, CodingKey {
        case type, label, dict, kanji, meaning, description, notes, teGroup, jlpt, forms, examples
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
        self.explicitID = explicitID
    }
}
