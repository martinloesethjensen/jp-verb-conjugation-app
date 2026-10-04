/// The word classes the app covers. Grammar endings attach to them, and every
/// conjugation form applies to some of them. Deliberately separate from
/// `VerbType`, which classifies verbs only.
public enum WordClass: String, Codable, Hashable, CaseIterable, Sendable {
    case verb
    case iAdjective = "i-adjective"
    case naAdjective = "na-adjective"
    case noun
}
