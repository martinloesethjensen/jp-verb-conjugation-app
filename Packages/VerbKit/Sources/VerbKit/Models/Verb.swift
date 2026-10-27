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
