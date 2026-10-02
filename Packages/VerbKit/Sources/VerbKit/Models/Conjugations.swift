/// A word's forms: surface string by form id. A missing id means the word has
/// no such form (ある has no potential). Order is not kept here; the
/// `FormCatalogue` orders forms for display.
public struct Conjugations: Hashable, Sendable {
    private var values: [String: String]

    public init(_ values: [FormID: String] = [:]) {
        self.values = Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) })
    }

    public subscript(id: FormID) -> String? {
        get { values[id.rawValue] }
        set { values[id.rawValue] = newValue }
    }

    /// The ids this word has a form for, in no particular order.
    public var ids: Set<FormID> {
        Set(values.keys.map { FormID(rawValue: $0) })
    }

    public var isEmpty: Bool { values.isEmpty }
    public var count: Int { values.count }
}

// Coded as a JSON object of id to string, which is the shape of `forms` in the
// data files. Written by hand because `Dictionary` only encodes as an object
// when its key is `String` or `Int`; a `FormID` key would encode as a flat array.
extension Conjugations: Codable {
    public init(from decoder: Decoder) throws {
        values = try decoder.singleValueContainer().decode([String: String].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
}
