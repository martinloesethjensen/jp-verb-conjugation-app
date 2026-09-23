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
        tai: String? = nil
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
