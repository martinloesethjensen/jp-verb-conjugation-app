import Foundation

/// One row of the だ / です table.
public struct CopulaRow: Hashable, Sendable {
    public let label: String
    public let plain: String
    public let plainAlt: String?
    public let polite: String
    public let politeAlt: String?
    /// Said when the plain and polite cells are the same.
    public let note: String?
}

/// The copula as a fixed table. words.json holds no copula forms and `data/` is signed, so
/// this lives in the app.
public enum Copula {
    public static let rows: [CopulaRow] = [
        CopulaRow(label: "is", plain: "だ", plainAlt: nil, polite: "です", politeAlt: nil, note: nil),
        CopulaRow(label: "is not", plain: "じゃない", plainAlt: "ではない",
                  polite: "じゃないです", politeAlt: "ではありません", note: nil),
        CopulaRow(label: "was", plain: "だった", plainAlt: nil, polite: "でした", politeAlt: nil, note: nil),
        CopulaRow(label: "was not", plain: "じゃなかった", plainAlt: "ではなかった",
                  polite: "じゃなかったです", politeAlt: "ではありませんでした", note: nil),
        CopulaRow(label: "and (て-form)", plain: "で", plainAlt: nil, polite: "で", politeAlt: nil,
                  note: "The same in both registers."),
        CopulaRow(label: "if / then", plain: "なら", plainAlt: nil, polite: "なら", politeAlt: nil,
                  note: "The same in both registers."),
        CopulaRow(label: "probably", plain: "だろう", plainAlt: nil, polite: "でしょう", politeAlt: nil, note: nil),
    ]

    /// Short notes under the table about joining the copula to other patterns.
    public static let notes: [String] = [
        "だ becomes な before ので (静かなので), not ×静かだので.",
        "かもしれない follows the bare noun or な-adjective stem (学生かもしれない), not ×学生だかもしれない.",
    ]
}

/// A plain form and its polite form.
public struct PolitePair: Hashable, Sendable {
    public let label: String
    public let plain: String
    public let polite: String
    /// The ありません spelling, for negatives.
    public let politeAlt: String?
}

/// The wrong polite forms learners produce for an い-adjective, with the right ones.
public struct PoliteTrap: Hashable, Sendable {
    public let wrong: [String]
    public let right: [String]
}

/// Polite adjective and noun forms, derived from the plain forms in the data. The plain
/// forms already carry the irregular stem (いい → よかった), so nothing is special-cased.
public enum PoliteForms {
    /// Present, negative, past and past negative with です, or nil for a verb or a word that
    /// lacks a plain form it needs.
    public static func rows(for word: SlotSource) -> [PolitePair]? {
        guard word.wordClass != .verb,
              let pos = word.slotForm("short_pos"), let neg = word.slotForm("short_neg"),
              let past = word.slotForm("short_past"), let pastNeg = word.slotForm("short_past_neg")
        else { return nil }
        if word.wordClass == .iAdjective {
            guard neg.hasSuffix("ない"), pastNeg.hasSuffix("なかった") else { return nil }
            return [
                PolitePair(label: "now", plain: pos, polite: pos + "です", politeAlt: nil),
                PolitePair(label: "not", plain: neg, polite: neg + "です",
                           politeAlt: neg.dropLast(2) + "ありません"),
                PolitePair(label: "past", plain: past, polite: past + "です", politeAlt: nil),
                PolitePair(label: "past not", plain: pastNeg, polite: pastNeg + "です",
                           politeAlt: pastNeg.dropLast(4) + "ありませんでした"),
            ]
        }
        guard pos.hasSuffix("だ"), neg.hasSuffix("じゃない"), past.hasSuffix("だった"),
              pastNeg.hasSuffix("じゃなかった") else { return nil }
        return [
            PolitePair(label: "now", plain: pos, polite: pos.dropLast() + "です", politeAlt: nil),
            PolitePair(label: "not", plain: neg, polite: neg + "です",
                       politeAlt: neg.dropLast(4) + "ではありません"),
            PolitePair(label: "past", plain: past, polite: past.dropLast(3) + "でした", politeAlt: nil),
            PolitePair(label: "past not", plain: pastNeg, polite: pastNeg + "です",
                       politeAlt: pastNeg.dropLast(6) + "ではありませんでした"),
        ]
    }

    /// ×たかいでした and ×たかくないでした, with the forms to say instead. Only い-adjectives
    /// make this mistake: です does not carry the past on an い-adjective.
    public static func trap(for word: SlotSource) -> PoliteTrap? {
        guard word.wordClass == .iAdjective,
              let pos = word.slotForm("short_pos"), let neg = word.slotForm("short_neg"),
              let rows = rows(for: word)
        else { return nil }
        return PoliteTrap(wrong: [pos + "でした", neg + "でした"], right: [rows[2].polite, rows[3].polite])
    }
}

private func + (lhs: Substring, rhs: String) -> String { String(lhs) + rhs }
