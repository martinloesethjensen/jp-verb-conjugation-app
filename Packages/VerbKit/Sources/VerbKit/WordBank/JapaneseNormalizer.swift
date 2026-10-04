import Foundation

/// The one normalisation used by Word Bank search, tag suggestions and import
/// merging, so "オオキニ", "ｵｵｷﾆ" and "おおきに" compare equal everywhere.
public enum JapaneseNormalizer {
    /// NFKC (full and half width), katakana → hiragana, Latin lowercased with
    /// diacritics folded (ō → o), whitespace trimmed and collapsed to one space.
    /// Dakuten are kept: が and か stay different.
    public static func key(_ text: String) -> String {
        var out = ""
        for character in text.precomposedStringWithCompatibilityMapping {
            if isLatin(character) {
                out += String(character).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            } else {
                out.unicodeScalars.append(contentsOf: character.unicodeScalars.map(hiragana))
            }
        }
        return out.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// `key`, then ー removed and long vowels folded: a vowel kana that only
    /// lengthens the kana before it is dropped (おおきに → おきに, せんせい → せんせ,
    /// こうこう → ここ). Used as a fallback when an exact match finds nothing.
    public static func looseKey(_ text: String) -> String {
        var out: [Character] = []
        for character in key(text) where character != "ー" {
            if let last = out.last, let vowel = vowel(of: last), lengthens(character, after: vowel) {
                continue
            }
            out.append(character)
        }
        return String(out)
    }

    /// Key for comparing tag names: `key` without spaces and hyphens, without a
    /// dialect suffix (弁, べん, ben, 方言, ほうげん, hogen, ことば, 言葉), romaji converted to kana,
    /// and long vowels folded. "Osaka-ben", "osaka ben", "Ōsaka" and "おおさかべん"
    /// share one key; kanji is not converted, so "大阪弁" matches "大阪" only.
    public static func tagKey(_ text: String) -> String {
        var name = key(text).filter { $0 != " " && $0 != "-" && $0 != "‐" }
        for suffix in tagSuffixes where name.hasSuffix(suffix) && name.count > suffix.count {
            name.removeLast(suffix.count)
            break
        }
        if name.contains(where: isASCIILetter), let kana = Romaji.toHiragana(name) {
            name = kana
        }
        return looseKey(name)
    }

    /// The kana a Latin query stands for ("ookini" → おおきに), or nil when the
    /// text has no Latin letter.
    public static func kanaForm(_ text: String) -> String? {
        let trimmed = text.precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains(where: isASCIILetter) else { return nil }
        return Romaji.toHiragana(trimmed)
    }

    // MARK: - Helpers

    private static let tagSuffixes = ["ほうげん", "ことば", "方言", "言葉", "hogen", "べん", "ben", "弁"]

    private static func isASCIILetter(_ character: Character) -> Bool {
        character.isASCII && character.isLetter
    }

    /// Latin script, including accented letters (ō, ü, é).
    private static func isLatin(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        return scalar.value <= 0x024F || (0x1E00...0x1EFF).contains(scalar.value)
    }

    /// Katakana ァ–ヶ and the iteration marks ヽヾ map onto hiragana.
    private static func hiragana(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        guard (0x30A1...0x30F6).contains(scalar.value) || (0x30FD...0x30FE).contains(scalar.value),
              let mapped = Unicode.Scalar(scalar.value - 0x60) else { return scalar }
        return mapped
    }

    private static let vowelRows: [Character: Character] = {
        var rows: [Character: Character] = [:]
        let spec: [(Character, String)] = [
            ("a", "あかがさざただなはばぱまやらわゃぁゎ"),
            ("i", "いきぎしじちぢにひびぴみりぃ"),
            ("u", "うくぐすずつづぬふぶぷむゆるゅぅゔ"),
            ("e", "えけげせぜてでねへべぺめれぇ"),
            ("o", "おこごそぞとどのほぼぽもよろをょぉ"),
        ]
        for (vowel, kana) in spec {
            for character in kana { rows[character] = vowel }
        }
        return rows
    }()

    private static func vowel(of character: Character) -> Character? { vowelRows[character] }

    /// Whether `character` only lengthens a kana ending in `vowel`.
    private static func lengthens(_ character: Character, after vowel: Character) -> Bool {
        switch character {
        case "あ": return vowel == "a"
        case "い": return vowel == "i" || vowel == "e"
        case "う": return vowel == "u" || vowel == "o"
        case "え": return vowel == "e"
        case "お": return vowel == "o"
        default: return false
        }
    }
}
