/// The 9 conjugation forms every verb is guaranteed to have.
/// (The 9 additional advanced forms on `VerbForms` are optional and don't
/// have `FormKey` cases yet — quiz generation and search only need the
/// guaranteed set. See the spec's data-layer section for why.)
public enum FormKey: String, CaseIterable, Codable, Equatable, Sendable {
    case masuPos = "masu_pos"
    case masuNeg = "masu_neg"
    case masuPast = "masu_past"
    case masuPastNeg = "masu_past_neg"
    case te
    case shortPos = "short_pos"
    case shortNeg = "short_neg"
    case shortPast = "short_past"
    case shortPastNeg = "short_past_neg"
}
