/// An example sentence for a verb, tagged with the form it shows. The tag is a `FormID`, so an
/// example may show any form in the catalogue (`tai`, `teiru`), not only the nine `FormKey`
/// forms; an id this build does not know still decodes, and the view falls back to the id.
public struct VerbExample: Codable, Hashable, Sendable {
    public var form: FormID
    public var jp: String
    public var en: String

    public init(form: FormID, jp: String, en: String) {
        self.form = form
        self.jp = jp
        self.en = en
    }
}
