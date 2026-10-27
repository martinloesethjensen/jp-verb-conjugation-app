/// Words and contexts where an index surface isn't the verb it spells. Each comes from the
/// lesson sentences (#142's audit): without them, すみません is 住む, the ない of じゃない
/// is ある, and the いけません of てはいけません is 行く. Code for now, like the tail rules.
enum LensStoplist {
    /// Words that are never highlighted, whatever they contain: すみません holds 住む's
    /// すみません, どうして holds する's して.
    static let words = ["すみません", "すいません", "どうして"]

    /// The ranges of `words` in `text`; no verb starts inside one.
    static func ranges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        for word in words {
            var from = text.startIndex
            while let range = text.range(of: word, range: from..<text.endIndex) {
                ranges.append(range)
                from = range.upperBound
            }
        }
        return ranges
    }

    /// A verb reading the context rules out:
    /// - ない, ありません… are ある, but not after く, じゃ, では, しれ or ありえ, where they
    ///   negate an adjective, a noun or a grammar pattern (安っぽくない, 水じゃない,
    ///   ものではありません, かもしれない, ありえない).
    /// - いけない / いけません is 行く's potential, but not after ては, ても, ちゃ or なければ,
    ///   where it's part of the pattern (食べてはいけない, 行かなければいけません).
    /// - みたい is 見る's たい, but not after an adjective or a noun (寒いみたい, 夢みたい).
    /// - Kana み… right after て is the auxiliary てみる of a verb the app lacks
    ///   (やってみます), not 見る.
    static func excludes(verbID: String, surface: String, after before: Substring) -> Bool {
        switch verbID {
        case "ある":
            return ["く", "じゃ", "では", "しれ", "ありえ"].contains { before.hasSuffix($0) }
        case "いく" where surface.hasPrefix("いけ"):
            return ["ては", "ても", "では", "でも", "ちゃ", "じゃ", "ければ"].contains { before.hasSuffix($0) }
        case "みる" where surface.hasPrefix("み"):
            guard let last = before.last else { return false }
            if surface.hasPrefix("みたい"), last == "い" || FuriganaDictionary.isKanji(last) || last.isKatakana {
                return true
            }
            return last == "て"
        default:
            return false
        }
    }
}

extension Character {
    var isKatakana: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return (0x30A1...0x30FA).contains(scalar.value) || scalar == "ー"
    }
}
