/// The id of a conjugation form: the snake_case key used in a `forms` object
/// (`masu_pos`, `pot_te`). An open set rather than an enum, so an id the app
/// does not know decodes instead of failing; the `FormCatalogue` says which ids
/// exist and what they mean.
public struct FormID: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

// Coded as a bare string. Written by hand: the compiler would otherwise
// synthesize a `{"rawValue": ...}` object for a struct.
extension FormID: Codable {
    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public extension FormID {
    // The nine forms every verb is guaranteed to have (the catalogue's
    // `authored` forms) and the few others code names directly. Everything
    // else is reached through the catalogue.
    static let masuPos: FormID = "masu_pos"
    static let masuNeg: FormID = "masu_neg"
    static let masuPast: FormID = "masu_past"
    static let masuPastNeg: FormID = "masu_past_neg"
    static let te: FormID = "te"
    static let shortPos: FormID = "short_pos"
    static let shortNeg: FormID = "short_neg"
    static let shortPast: FormID = "short_past"
    static let shortPastNeg: FormID = "short_past_neg"
    static let potential: FormID = "potential"
}
