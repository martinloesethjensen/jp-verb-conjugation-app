/// Turns text into drawable units, putting readings above the kanji it knows.
///
/// Matching scans left to right. At each kanji it takes the longest key that
/// matches the text from there: the key's kanji part can be any prefix of the
/// kanji run (so 毎日学校 splits into 毎日 and 学校), and it may be followed by
/// up to `maxOkuriganaInKey` kana that disambiguate the reading. The reading
/// covers the kanji part only; the kana stay plain text, but the piece of kana
/// right after a read kanji is glued to it (the okurigana), so a line never
/// breaks between 食 and べる.
public struct FuriganaDictionary: Equatable, Sendable {
    public let readings: [String: String]

    /// Plain (non-kanji) text is cut into pieces of at most this many
    /// characters, so a line can break almost anywhere, as Japanese allows.
    static let plainChunkSize = 3
    static let maxOkuriganaInKey = 3

    public static let empty = FuriganaDictionary(readings: [:])

    public init(readings: [String: String]) {
        self.readings = readings
    }

    public init(file: FuriganaDataFile) {
        self.init(readings: file.readings)
    }

    // MARK: character classes

    /// CJK ideographs plus the iteration mark 々.
    public static func isKanji(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) || scalar.value == 0x3005
        }
    }

    private static let closingPunctuation: Set<Character> = [
        "。", "、", "，", "．", "」", "』", "）", "！", "？", "…",
        ".", ",", ";", ":", "!", "?", ")",
    ]

    private static func isClosing(_ character: Character) -> Bool {
        closingPunctuation.contains(character)
    }

    private static func isHiragana(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { (0x3041...0x3096).contains($0.value) }
    }

    /// Part of an English word: ASCII, not a space, not closing punctuation.
    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isASCII && !character.isWhitespace && !isClosing(character)
    }

    // MARK: queries

    public func containsKanji(_ text: String) -> Bool {
        text.contains(where: Self.isKanji)
    }

    /// True if some kanji in `text` has no reading in this dictionary.
    public func hasUnreadKanji(in text: String) -> Bool {
        units(for: text).contains { unit in
            unit.reading == nil && unit.text.contains(where: Self.isKanji)
        }
    }

    /// `text` with every kanji the dictionary knows replaced by its reading, so
    /// 頭が痛いんです becomes あたまがいたいんです. Unknown kanji stay as they are.
    public func reading(of text: String) -> String {
        units(for: text).map { $0.reading ?? $0.text }.joined()
    }

    // MARK: segmentation

    public func units(for text: String) -> [TextUnit] {
        let chars = Array(text)
        var units: [TextUnit] = []
        var i = 0

        while i < chars.count {
            let c = chars[i]

            if Self.isKanji(c) {
                if let match = longestMatch(in: chars, at: i) {
                    units.append(TextUnit(text: String(chars[i..<(i + match.kanjiLength)]), reading: match.reading))
                    i += match.kanjiLength
                } else {
                    units.append(TextUnit(text: String(c)))
                    i += 1
                }
            } else if Self.isClosing(c) && !units.isEmpty {
                units.append(TextUnit(text: String(c), glueToPrevious: true))
                i += 1
            } else if Self.isWordCharacter(c) {
                var j = i
                while j < chars.count, Self.isWordCharacter(chars[j]) { j += 1 }
                while j < chars.count, chars[j].isWhitespace { j += 1 }
                units.append(TextUnit(text: String(chars[i..<j])))
                i = j
            } else {
                var j = i
                while j < chars.count,
                      j - i < Self.plainChunkSize,
                      !Self.isKanji(chars[j]),
                      !Self.isWordCharacter(chars[j]),
                      !(Self.isClosing(chars[j]) && j > i) {
                    j += 1
                }
                if j == i { j = i + 1 }
                let afterRuby = units.last?.reading != nil
                units.append(TextUnit(text: String(chars[i..<j]), glueToPrevious: afterRuby && Self.isHiragana(chars[i])))
                i = j
            }
        }
        return units
    }

    private func longestMatch(in chars: [Character], at start: Int) -> (kanjiLength: Int, reading: String)? {
        var runEnd = start
        while runEnd < chars.count, Self.isKanji(chars[runEnd]) { runEnd += 1 }

        var best: (total: Int, kanjiLength: Int, reading: String)?
        for kanjiLength in stride(from: runEnd - start, through: 1, by: -1) {
            let kanjiEnd = start + kanjiLength
            // Kana can only follow the kanji part when it ends the whole run.
            let maxSuffix = kanjiEnd == runEnd ? min(Self.maxOkuriganaInKey, chars.count - kanjiEnd) : 0
            for suffix in stride(from: maxSuffix, through: 0, by: -1) {
                let key = String(chars[start..<(kanjiEnd + suffix)])
                guard let reading = readings[key] else { continue }
                let total = kanjiLength + suffix
                if best == nil || total > best!.total {
                    best = (total, kanjiLength, reading)
                }
            }
        }
        return best.map { ($0.kanjiLength, $0.reading) }
    }
}
