/// The 9 conjugation forms every verb is guaranteed to have.
/// (The other forms on `VerbForms` are optional and have no `FormKey` cases.
/// The quiz does not use this enum: it reads every form through `QuizForm`.)
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
