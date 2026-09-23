public struct VerbExample: Codable, Hashable, Sendable {
    public var form: FormKey
    public var jp: String
    public var en: String

    public init(form: FormKey, jp: String, en: String) {
        self.form = form
        self.jp = jp
        self.en = en
    }
}
