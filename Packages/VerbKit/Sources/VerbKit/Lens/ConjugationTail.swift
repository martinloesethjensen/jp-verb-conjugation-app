/// An ending the Sentence lens recognises past what the index lists: the data has
/// 食べさせられる but not 食べさせられなかった, and 忘れて but not 忘れてしまいました.
/// The rules attach to a slot (a derived stem, a て-form, an i-adjective-like form) and
/// can lead on to another slot, so 食べ ▸ て ▸ み ▸ て ▸ ください chains.
///
/// The tails cover the forms the catalogue and the lessons teach, not Japanese at large:
/// ru-verb endings on derived stems, i-adjective endings on たい / ない / やすい stems,
/// the て + auxiliary patterns (しまう, いる, みる, おく, くれる, もらう, あげる, ください,
/// もいい, はいけない), their ちゃう contractions, and です. The tail grammar stays in code for
/// now; #142 notes it could become signed data later. #149 adds generating to recognising.
public struct ConjugationTail: Hashable, Sendable {
    /// Where a tail attaches.
    public enum Slot: Hashable, Sendable {
        /// A ru-verb-like stem: a passive, causative, potential or すぎる form without る
        /// (食べさせられ, 呼ばれ, 食べすぎ).
        case ruStem
        /// An i-adjective-like stem: a たい, ない, やすい or にくい form without い
        /// (食べた, 行けな, 書きやす).
        case adjStem
        /// After a て-form: 忘れて ▸ しまいました.
        case te
        /// A て-form without て, for the ちゃ contraction: 食べ ▸ ちゃった.
        case chaStem
        /// A で-form without で, for the じゃ contraction: 飲ん ▸ じゃった.
        case jaStem
        /// After an i-adjective-like form: 飲みたい ▸ です.
        case polite
    }

    public let surface: String
    public let kind: ChainPart.Kind
    /// The slot the tail leads on to, if any: て leads on to the auxiliaries.
    public let next: Slot?

    init(_ surface: String, _ kind: ChainPart.Kind, _ next: Slot? = nil) {
        self.surface = surface
        self.kind = kind
        self.next = next
    }

    /// The index forms that take tails as they are, and where: a て-form takes the
    /// auxiliaries, an i-adjective-like form takes です. Derived stems come from
    /// `FormIndex.stemMatches` and `VerbMatcher`'s own stems instead.
    public static let slots: [FormID: Slot] = [
        "te": .te, "neg_te": .te, "nakute": .te, "pot_te": .te, "teiru_te": .te,
        "tai": .polite, "short_neg": .polite, "pot_short_neg": .polite, "yasui": .polite,
        "nikui": .polite, "te_mo_ii": .polite, "nakute_mo_ii": .polite,
    ]

    /// The tails that attach at `slot`.
    public static func rules(at slot: Slot) -> [ConjugationTail] {
        table[slot] ?? []
    }

    // MARK: Rules

    private static let table: [Slot: [ConjugationTail]] = [
        .ruStem: ruVerbEndings,
        .adjStem: adjectiveEndings + godan("たがる", a: "がら", i: "がり", u: "がる", ta: "がっ"),
        .te: teAuxiliaries,
        .chaStem: contractions("ちゃ"),
        .jaStem: contractions("じゃ"),
        .polite: [ConjugationTail("です", .auxiliary("です"))],
    ]

    /// A ru-verb's endings, as the catalogue names them: なかった is `short_past_neg`.
    private static let ruVerbEndings: [ConjugationTail] = [
        .init("る", .form("short_pos")),
        .init("ない", .form("short_neg"), .polite),
        .init("なかった", .form("short_past_neg"), .polite),
        .init("た", .form("short_past")),
        .init("ます", .form("masu_pos")),
        .init("ません", .form("masu_neg")),
        .init("ました", .form("masu_past")),
        .init("ませんでした", .form("masu_past_neg")),
        .init("ましょう", .form("masu_volitional")),
        .init("よう", .form("volitional")),
        .init("て", .form("te"), .te),
        .init("ないで", .form("neg_te"), .te),
        .init("なくて", .form("nakute"), .te),
        .init("たい", .form("tai"), .polite),
        .init("たくない", .auxiliary("たい · negative"), .polite),
        .init("たかった", .auxiliary("たい · past"), .polite),
        .init("れば", .form("conditional_ba")),
        .init("たら", .form("conditional_tara")),
        .init("なければならない", .form("nakereba_naranai")),
        .init("なければなりません", .auxiliary("なければならない · polite")),
        .init("なければいけない", .auxiliary("なければいけない")),
        .init("なければいけません", .auxiliary("なければいけない · polite")),
        .init("なくてはいけない", .form("nakute_wa_ikenai")),
        .init("なくてはいけません", .auxiliary("なくてはいけない · polite")),
        .init("なくてもいい", .form("nakute_mo_ii"), .polite),
    ]

    /// An i-adjective's endings, on the stem of a たい, ない, やすい or にくい form. The
    /// ければ obligations only make sense after ない, but nothing else spells them.
    private static let adjectiveEndings: [ConjugationTail] = [
        .init("くない", .auxiliary("negative"), .polite),
        .init("くなかった", .auxiliary("past negative"), .polite),
        .init("かった", .auxiliary("past"), .polite),
        .init("くありません", .auxiliary("polite negative")),
        .init("くありませんでした", .auxiliary("polite past negative")),
        .init("くて", .auxiliary("て-form"), .te),
        .init("く", .auxiliary("adverb (く)")),
        .init("ければ", .auxiliary("conditional (ば)")),
        .init("ければならない", .auxiliary("なければならない")),
        .init("ければなりません", .auxiliary("なければならない · polite")),
        .init("ければいけない", .auxiliary("なければいけない")),
        .init("ければいけません", .auxiliary("なければいけない · polite")),
        .init("くちゃ", .auxiliary("なくちゃ")),
        .init("きゃ", .auxiliary("なきゃ")),
    ]

    /// What follows a て-form.
    private static let teAuxiliaries: [ConjugationTail] =
        ichidan("ている", stem: "い") + ichidan("てみる", stem: "み")
        + ichidan("てくれる", stem: "くれ") + ichidan("てあげる", stem: "あげ")
        + ichidan("てもらえる", stem: "もらえ")
        + godan("てしまう", a: "しまわ", i: "しまい", u: "しまう", ta: "しまっ")
        + godan("ておく", a: "おか", i: "おき", u: "おく", ta: "おい")
        + godan("てもらう", a: "もらわ", i: "もらい", u: "もらう", ta: "もらっ")
        + [
            .init("ください", .auxiliary("てください")),
            .init("もいい", .auxiliary("てもいい"), .polite),
            .init("いい", .auxiliary("ていい"), .polite),
            .init("はいけない", .auxiliary("てはいけない"), .polite),
            .init("はいけません", .auxiliary("てはいけない · polite")),
            .init("はだめ", .auxiliary("てはだめ")),
        ]

    /// ちゃう / じゃう for てしまう / でしまう, and ちゃいけない, ちゃだめ.
    private static func contractions(_ cha: String) -> [ConjugationTail] {
        godan("\(cha)う (てしまう)", a: cha + "わ", i: cha + "い", u: cha + "う", ta: cha + "っ") + [
            .init(cha + "いけない", .auxiliary("\(cha)いけない (てはいけない)"), .polite),
            .init(cha + "いけません", .auxiliary("\(cha)いけない (てはいけない) · polite")),
            .init(cha + "だめ", .auxiliary("\(cha)だめ (てはだめ)")),
        ]
    }

    /// The common conjugations of a ru-verb auxiliary: いる → いる, いない, いた, います…
    private static func ichidan(_ name: String, stem: String) -> [ConjugationTail] {
        [
            ("る", nil, nil), ("ない", "negative", .polite), ("なかった", "past negative", .polite),
            ("た", "past", nil), ("ます", "polite", nil), ("ません", "polite negative", nil),
            ("ました", "polite past", nil), ("ませんでした", "polite past negative", nil),
            ("ましょう", "polite volitional", nil), ("て", "て-form", .te), ("たい", "want to", .polite),
        ].map { (ending: String, facet: String?, next: Slot?) in
            ConjugationTail(stem + ending, .auxiliary(label(name, facet)), next)
        }
    }

    /// The common conjugations of an u-verb auxiliary, from its a-, i-, u- and た stems:
    /// しまう → しまう, しまわない, しまいます, しまった…
    private static func godan(_ name: String, a: String, i: String, u: String, ta: String) -> [ConjugationTail] {
        [
            (u, nil, nil), (a + "ない", "negative", .polite), (a + "なかった", "past negative", .polite),
            (ta + "た", "past", nil), (i + "ます", "polite", nil), (i + "ません", "polite negative", nil),
            (i + "ました", "polite past", nil), (i + "ませんでした", "polite past negative", nil),
            (i + "ましょう", "polite volitional", nil), (ta + "て", "て-form", .te), (i + "たい", "want to", .polite),
        ].map { (surface: String, facet: String?, next: Slot?) in
            ConjugationTail(surface, .auxiliary(label(name, facet)), next)
        }
    }

    private static func label(_ name: String, _ facet: String?) -> String {
        facet.map { "\(name) · \($0)" } ?? name
    }

    // MARK: Recognising

    /// A way to continue past a slot: where it ends and the parts it adds.
    struct Extension {
        let end: String.Index
        let parts: [ChainPart]
    }

    /// The deepest chain: て ▸ aux ▸ て ▸ aux ▸ です (食べてみてもいいです) is four steps.
    private static let maxDepth = 4

    /// Every way the tails continue `text` from `start` at `slot`, each rule and every
    /// chain of rules after it. The caller keeps the ones that end on a word boundary
    /// and takes the longest.
    static func extensions(at slot: Slot, in text: String, from start: String.Index, depth: Int = 0) -> [Extension] {
        guard depth < maxDepth, start < text.endIndex else { return [] }
        let rest = text[start...]
        var found: [Extension] = []
        for rule in rules(at: slot) where rest.hasPrefix(rule.surface) {
            let end = text.index(start, offsetBy: rule.surface.count)
            let part = ChainPart(surface: rule.surface, kind: rule.kind, isRuleBuilt: true)
            found.append(Extension(end: end, parts: [part]))
            guard let next = rule.next else { continue }
            for more in extensions(at: next, in: text, from: end, depth: depth + 1) {
                found.append(Extension(end: more.end, parts: [part] + more.parts))
            }
        }
        return found
    }
}
