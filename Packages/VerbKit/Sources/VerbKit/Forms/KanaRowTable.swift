import Foundation

/// A vowel row of the kana table. A u-verb's last kana moves along its column to one of these:
/// あ before ない, い before ます, う in the dictionary form, え for the potential and ば, お for
/// the volitional. Published as `kana_row` on an attachment rule ("a" … "o").
public enum KanaRow: String, Codable, CaseIterable, Hashable, Sendable {
    case a, i, u, e, o
}

/// The nine endings a u-verb (godan verb) can have, and the kana each becomes in every row.
public enum GodanEnding {
    /// The columns, keyed by dictionary ending, in kana-table order. う takes わ in the あ-row
    /// (買わない), the one column that does not follow the plain table.
    private static let columns: [(ending: Character, kana: [Character])] = [
        ("う", ["わ", "い", "う", "え", "お"]),
        ("く", ["か", "き", "く", "け", "こ"]),
        ("ぐ", ["が", "ぎ", "ぐ", "げ", "ご"]),
        ("す", ["さ", "し", "す", "せ", "そ"]),
        ("つ", ["た", "ち", "つ", "て", "と"]),
        ("ぬ", ["な", "に", "ぬ", "ね", "の"]),
        ("ぶ", ["ば", "び", "ぶ", "べ", "ぼ"]),
        ("む", ["ま", "み", "む", "め", "も"]),
        ("る", ["ら", "り", "る", "れ", "ろ"]),
    ]

    /// う く ぐ す つ ぬ ぶ む る.
    public static let endings: [Character] = columns.map(\.ending)

    /// The kana `ending` becomes in `row` (く, .e → け), or nil when it is no u-verb ending.
    public static func kana(_ ending: Character, in row: KanaRow) -> Character? {
        guard let column = columns.first(where: { $0.ending == ending }),
              let index = KanaRow.allCases.firstIndex(of: row) else { return nil }
        return column.kana[index]
    }

    /// The row and column a kana sits in (け → .e, く; わ → .a, う), or nil when it is in none.
    public static func position(of kana: Character) -> (row: KanaRow, ending: Character)? {
        for column in columns {
            if let index = column.kana.firstIndex(of: kana) {
                return (KanaRow.allCases[index], column.ending)
            }
        }
        return nil
    }
}

/// The kana-row table for an attachment rule with a `kanaRow`: one row per example pair of the
/// rule (飲む → 飲める), with that verb's ending in all five rows and the target row marked.
public struct KanaRowTable: Hashable, Sendable {
    public struct Row: Hashable, Sendable {
        public var base: String
        public var built: String
        /// The dictionary ending (む).
        public var ending: Character
        /// The ending in each row, あ to お (ま み む め も).
        public var kana: [Character]
    }

    public var target: KanaRow
    public var rows: [Row]

    /// Nil when the rule has no `kanaRow`, or none of its examples is a u-verb pair. A pair
    /// counts when the built form starts with the verb's stem and its ending moved to the target
    /// row (飲む → 飲め…), so 勉強する → 勉強できる is left out though it ends in る.
    public init?(rule: AttachmentRule) {
        guard let target = rule.kanaRow else { return nil }
        let rows: [Row] = rule.example.components(separatedBy: " / ").compactMap { pair in
            let sides = pair.components(separatedBy: " → ")
            guard sides.count == 2,
                  let ending = sides[0].last,
                  let moved = GodanEnding.kana(ending, in: target),
                  sides[1].hasPrefix(String(sides[0].dropLast()) + String(moved)) else { return nil }
            let kana = KanaRow.allCases.compactMap { GodanEnding.kana(ending, in: $0) }
            return Row(base: sides[0], built: sides[1], ending: ending, kana: kana)
        }
        guard !rows.isEmpty else { return nil }
        self.target = target
        self.rows = rows
    }
}
