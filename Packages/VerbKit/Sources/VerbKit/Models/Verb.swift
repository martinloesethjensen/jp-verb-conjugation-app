public struct Verb: Codable, Hashable, Identifiable, Sendable {
    public var type: VerbType
    public var label: String
    public var dict: String
    public var kanji: String?
    public var meaning: String
    public var description: String
    public var notes: String?
    public var teGroup: TeGroup?
    public var forms: VerbForms
    public var examples: [VerbExample]

    public var id: String { dict }

    public init(
        type: VerbType,
        label: String,
        dict: String,
        kanji: String?,
        meaning: String,
        description: String,
        notes: String? = nil,
        teGroup: TeGroup? = nil,
        forms: VerbForms,
        examples: [VerbExample]
    ) {
        self.type = type
        self.label = label
        self.dict = dict
        self.kanji = kanji
        self.meaning = meaning
        self.description = description
        self.notes = notes
        self.teGroup = teGroup
        self.forms = forms
        self.examples = examples
    }
}
