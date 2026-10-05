/// The kanji in an entry, for its Jisho kanji chips.
public enum KanjiExtraction {
    /// Distinct kanji across `texts`, in the order first seen. The iteration
    /// mark 々 is skipped: it isn't a kanji to look up.
    public static func kanji(in texts: [String]) -> [Character] {
        var seen = Set<Character>()
        var result: [Character] = []
        for character in texts.joined() where character != "々" && FuriganaDictionary.isKanji(character) {
            if seen.insert(character).inserted { result.append(character) }
        }
        return result
    }
}
