/// How a verb's potential form is built, so the Potential page can explain it.
/// The wording is a UI concern and lives in the app.
public enum PotentialPattern: Equatable, Sendable {
    /// Drop る, add られる (たべる → たべられる).
    case ru
    /// Final u-sound to e-sound, add る (のむ → のめる).
    case u
    /// する → できる, also in compounds (べんきょうする → べんきょうできる).
    case suru
    /// くる → こられる.
    case kuru

    /// Nil when the verb has no potential form (ある), or is an irregular verb that ends in
    /// neither する nor くる.
    public init?(verb: Verb) {
        guard verb.forms.potential != nil else { return nil }
        switch verb.type {
        case .ru: self = .ru
        case .u: self = .u
        case .irregular:
            if verb.dict.hasSuffix("くる") {
                self = .kuru
            } else if verb.dict.hasSuffix("する") {
                self = .suru
            } else {
                return nil
            }
        }
    }
}
