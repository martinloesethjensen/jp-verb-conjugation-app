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
    /// A verb filed in this group that breaks its rule, as (dictionary form, て-form): いく → いって.
    public let exception: (dict: String, te: String)?

    public init(
        group: TeGroup, endings: String, result: String,
        example: (dict: String, te: String), exception: (dict: String, te: String)? = nil
    ) {
        self.group = group
        self.endings = endings
        self.result = result
        self.example = example
        self.exception = exception
    }

    public static let all: [TeFormRule] = [
        TeFormRule(group: .tte, endings: "う / つ / る", result: "って", example: ("かう", "かって")),
        TeFormRule(group: .nde, endings: "む / ぶ / ぬ", result: "んで", example: ("のむ", "のんで")),
        TeFormRule(group: .ite, endings: "く", result: "いて", example: ("かく", "かいて"),
                   exception: ("いく", "いって")),
        TeFormRule(group: .ide, endings: "ぐ", result: "いで", example: ("いそぐ", "いそいで")),
        TeFormRule(group: .shite, endings: "す", result: "して", example: ("はなす", "はなして")),
    ]

    public static func == (a: TeFormRule, b: TeFormRule) -> Bool { a.group == b.group }
    public func hash(into hasher: inout Hasher) { hasher.combine(group) }
}

/// U-verbs in the data that end in -iru or -eru, so look like ru-verbs, as (kana, kanji).
/// The kanji tells 切る (to cut, a u-verb) from 着る (to wear, a ru-verb).
/// A test checks this list against the data.
public enum RuLookalike {
    public static let all: [(kana: String, kanji: String)] = [
        ("はいる", "入る"), ("かえる", "帰る"), ("しる", "知る"), ("はしる", "走る"), ("きる", "切る"),
    ]
}
