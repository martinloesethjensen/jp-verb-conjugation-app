/// The mistake a wrong quiz choice represents. The raw strings are a cross-platform
/// contract (the Android app stores the same ones), so they never change once shipped:
///
///     other_form:<form id>             another form of the same verb
///     wrong_te_group:<tte|nde|ite|ide|shite>   a て-form built with the wrong group's ending
///     ru_u_confusion                   a ru-verb conjugated as a u-verb, or the reverse
///     aru_negative                     ×あらない for ない
///     passive_potential                the passive taken for the potential, or the reverse
///     causative_passive_long_short     the long causative-passive taken for the short, or the reverse
///     other_verb:<dictionary form>     the same form of another verb
///     generic                          anything else; also what an unknown raw string reads as
public enum QuizErrorTag: Hashable, Sendable, Codable {
    case otherForm(String)
    case wrongTeGroup(TeGroup)
    case ruUConfusion
    case aruNegative
    case passivePotential
    case causativePassiveLongShort
    case otherVerb(String)
    case generic

    public var rawValue: String {
        switch self {
        case .otherForm(let id): "other_form:\(id)"
        case .wrongTeGroup(let group): "wrong_te_group:\(group.rawValue)"
        case .ruUConfusion: "ru_u_confusion"
        case .aruNegative: "aru_negative"
        case .passivePotential: "passive_potential"
        case .causativePassiveLongShort: "causative_passive_long_short"
        case .otherVerb(let dict): "other_verb:\(dict)"
        case .generic: "generic"
        }
    }

    /// An unknown or malformed raw string reads as `.generic`.
    public init(rawValue: String) {
        let parts = rawValue.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let payload = parts.count > 1 ? String(parts[1]) : ""
        switch parts.first.map(String.init) ?? "" {
        case "other_form" where !payload.isEmpty: self = .otherForm(payload)
        case "wrong_te_group":
            if let group = TeGroup(rawValue: payload) { self = .wrongTeGroup(group) } else { self = .generic }
        case "ru_u_confusion": self = .ruUConfusion
        case "aru_negative": self = .aruNegative
        case "passive_potential": self = .passivePotential
        case "causative_passive_long_short": self = .causativePassiveLongShort
        case "other_verb" where !payload.isEmpty: self = .otherVerb(payload)
        default: self = .generic
        }
    }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// A coarse category for grouping in Progress later: the tag without its payload.
    public var category: String { rawValue.split(separator: ":").first.map(String.init) ?? "generic" }

    /// Whether the verb guide (て-form rules, verb types) explains this mistake.
    public var opensVerbGuide: Bool {
        switch self {
        case .wrongTeGroup, .ruUConfusion: true
        default: false
        }
    }

    /// One line on what the chosen wrong answer was, for the feedback after an answer.
    /// `verb` and `form` are the question's.
    public func explanation(verb: Verb, form: QuizForm) -> String {
        let right = form.value(in: verb.forms) ?? verb.dict
        switch self {
        case .wrongTeGroup(let group):
            guard let own = verb.teGroup, let rule = TeFormRule.all.first(where: { $0.group == own }) else {
                return "Check the て-form rule for \(verb.dict): \(right)."
            }
            if group == own, let exception = rule.exception, exception.dict == verb.dict {
                return "\(verb.dict) is the exception: its て-form is \(right), not the regular \(rule.result)."
            }
            return "\(rule.endings) verbs make the て-form with \(rule.result), like \(rule.example.dict) → \(rule.example.te): \(right)."
        case .ruUConfusion:
            if verb.type == .ru {
                return "\(verb.dict) is a ru-verb: drop る and add the ending (\(right)). It does not change る to ら or り."
            }
            return "\(verb.dict) looks like a ru-verb but is a u-verb: る changes to ら or り (\(right)), it is not dropped."
        case .aruNegative:
            return "The plain negative of ある is ない, not あらない."
        case .passivePotential:
            return "The passive (it is done to someone) and the potential (can do) are easy to mix up. The question asked for \(form.label): \(right)."
        case .causativePassiveLongShort:
            return "The long and the short causative-passive are different forms. The question asked for \(form.label): \(right)."
        case .otherForm(let id):
            let label = QuizForm.all.first { $0.id == id }?.label ?? id
            return "That is the \(label) form. The question asked for \(form.label): \(right)."
        case .otherVerb(let dict):
            return "That is the \(form.label) form of \(dict), not of \(verb.dict): \(right)."
        case .generic:
            return "Not the \(form.label) form of \(verb.dict): \(right)."
        }
    }
}
