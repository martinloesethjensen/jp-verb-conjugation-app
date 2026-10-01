/// How a u-verb forms its て-form, by group. One table feeds both the filter chips
/// and the guide sheet, so the two cannot disagree.
public struct TeFormRule: Hashable, Sendable {
    public let group: TeGroup
    /// The dictionary endings the group covers, e.g. "う / つ / る".
    public let endings: String
    /// What the て-form ends in, e.g. "って".
    public let result: String
    /// A verb from the data that shows the rule, as (dictionary form, て-form).
    public let example: (dict: String, te: String)

    public static let all: [TeFormRule] = [
        TeFormRule(group: .tte, endings: "う / つ / る", result: "って", example: ("かう", "かって")),
        TeFormRule(group: .nde, endings: "む / ぶ / ぬ", result: "んで", example: ("のむ", "のんで")),
        TeFormRule(group: .ite, endings: "く", result: "いて", example: ("かく", "かいて")),
        TeFormRule(group: .ide, endings: "ぐ", result: "いで", example: ("いそぐ", "いそいで")),
        TeFormRule(group: .shite, endings: "す", result: "して", example: ("はなす", "はなして")),
    ]

    public static func == (a: TeFormRule, b: TeFormRule) -> Bool { a.group == b.group }
    public func hash(into hasher: inout Hasher) { hasher.combine(group) }
}
