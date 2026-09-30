public struct VerbForms: Codable, Hashable, Sendable {
    public var masuPos: String
    public var masuNeg: String
    public var masuPast: String
    public var masuPastNeg: String
    public var te: String
    public var shortPos: String
    public var shortNeg: String
    public var shortPast: String
    public var shortPastNeg: String

    public var potential: String?
    public var volitional: String?
    public var passive: String?
    public var causative: String?
    public var causativePassive: String?
    public var conditionalBa: String?
    public var conditionalTara: String?
    public var imperative: String?
    public var tai: String?

    // んです forms (grammar point `n-desu`): the plain forms + んです/んだ.
    public var ndPos: String?
    public var ndNeg: String?
    public var ndPast: String?
    public var ndPastNeg: String?
    public var ndCasualPos: String?
    public var ndCasualNeg: String?
    public var ndCasualPast: String?
    public var ndCasualPastNeg: String?

    /// True when at least one んです form is populated.
    public var hasNdForms: Bool {
        [ndPos, ndNeg, ndPast, ndPastNeg, ndCasualPos, ndCasualNeg, ndCasualPast, ndCasualPastNeg]
            .contains { $0 != nil }
    }

    // The potential verb's own conjugations (grammar point `potential`).
    // `potential` above is the base (plain, present, affirmative) form; these
    // eight complete the verb's polite / plain / て-form grid.
    public var potMasuPos: String?
    public var potMasuNeg: String?
    public var potMasuPast: String?
    public var potMasuPastNeg: String?
    public var potTe: String?
    public var potShortNeg: String?
    public var potShortPast: String?
    public var potShortPastNeg: String?

    /// True when at least one of the nine potential forms (the base
    /// `potential` included) is populated.
    public var hasPotentialForms: Bool {
        [potential, potMasuPos, potMasuNeg, potMasuPast, potMasuPastNeg,
         potTe, potShortNeg, potShortPast, potShortPastNeg]
            .contains { $0 != nil }
    }

    public init(
        masuPos: String,
        masuNeg: String,
        masuPast: String,
        masuPastNeg: String,
        te: String,
        shortPos: String,
        shortNeg: String,
        shortPast: String,
        shortPastNeg: String,
        potential: String? = nil,
        volitional: String? = nil,
        passive: String? = nil,
        causative: String? = nil,
        causativePassive: String? = nil,
        conditionalBa: String? = nil,
        conditionalTara: String? = nil,
        imperative: String? = nil,
        tai: String? = nil,
        ndPos: String? = nil,
        ndNeg: String? = nil,
        ndPast: String? = nil,
        ndPastNeg: String? = nil,
        ndCasualPos: String? = nil,
        ndCasualNeg: String? = nil,
        ndCasualPast: String? = nil,
        ndCasualPastNeg: String? = nil,
        potMasuPos: String? = nil,
        potMasuNeg: String? = nil,
        potMasuPast: String? = nil,
        potMasuPastNeg: String? = nil,
        potTe: String? = nil,
        potShortNeg: String? = nil,
        potShortPast: String? = nil,
        potShortPastNeg: String? = nil
    ) {
        self.masuPos = masuPos
        self.masuNeg = masuNeg
        self.masuPast = masuPast
        self.masuPastNeg = masuPastNeg
        self.te = te
        self.shortPos = shortPos
        self.shortNeg = shortNeg
        self.shortPast = shortPast
        self.shortPastNeg = shortPastNeg
        self.potential = potential
        self.volitional = volitional
        self.passive = passive
        self.causative = causative
        self.causativePassive = causativePassive
        self.conditionalBa = conditionalBa
        self.conditionalTara = conditionalTara
        self.imperative = imperative
        self.tai = tai
        self.ndPos = ndPos
        self.ndNeg = ndNeg
        self.ndPast = ndPast
        self.ndPastNeg = ndPastNeg
        self.ndCasualPos = ndCasualPos
        self.ndCasualNeg = ndCasualNeg
        self.ndCasualPast = ndCasualPast
        self.ndCasualPastNeg = ndCasualPastNeg
        self.potMasuPos = potMasuPos
        self.potMasuNeg = potMasuNeg
        self.potMasuPast = potMasuPast
        self.potMasuPastNeg = potMasuPastNeg
        self.potTe = potTe
        self.potShortNeg = potShortNeg
        self.potShortPast = potShortPast
        self.potShortPastNeg = potShortPastNeg
    }

    enum CodingKeys: String, CodingKey {
        case masuPos = "masu_pos"
        case masuNeg = "masu_neg"
        case masuPast = "masu_past"
        case masuPastNeg = "masu_past_neg"
        case te
        case shortPos = "short_pos"
        case shortNeg = "short_neg"
        case shortPast = "short_past"
        case shortPastNeg = "short_past_neg"
        case potential
        case volitional
        case passive
        case causative
        case causativePassive = "causative_passive"
        case conditionalBa = "conditional_ba"
        case conditionalTara = "conditional_tara"
        case imperative
        case tai
        case ndPos = "nd_pos"
        case ndNeg = "nd_neg"
        case ndPast = "nd_past"
        case ndPastNeg = "nd_past_neg"
        case ndCasualPos = "nd_casual_pos"
        case ndCasualNeg = "nd_casual_neg"
        case ndCasualPast = "nd_casual_past"
        case ndCasualPastNeg = "nd_casual_past_neg"
        case potMasuPos = "pot_masu_pos"
        case potMasuNeg = "pot_masu_neg"
        case potMasuPast = "pot_masu_past"
        case potMasuPastNeg = "pot_masu_past_neg"
        case potTe = "pot_te"
        case potShortNeg = "pot_short_neg"
        case potShortPast = "pot_short_past"
        case potShortPastNeg = "pot_short_past_neg"
    }

    public subscript(_ key: FormKey) -> String {
        switch key {
        case .masuPos: return masuPos
        case .masuNeg: return masuNeg
        case .masuPast: return masuPast
        case .masuPastNeg: return masuPastNeg
        case .te: return te
        case .shortPos: return shortPos
        case .shortNeg: return shortNeg
        case .shortPast: return shortPast
        case .shortPastNeg: return shortPastNeg
        }
    }
}
