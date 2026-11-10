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

    /// An entry's kanji chips: the distinct kanji of its text, kanji spelling and standard forms (in
    /// that order, as `kanji(in:)`), and the one field they come from, so the page can say "From the
    /// standard form". `.mixed` when more than one field has kanji, `.text` when none does.
    public static func chips(text: String, spelling: String?, standard: [String]) -> KanjiChips {
        let fields: [(KanjiChips.Source, [String])] = [(.text, [text]), (.spelling, [spelling ?? ""]), (.standard, standard)]
        let withKanji = fields.filter { !kanji(in: $0.1).isEmpty }.map(\.0)
        let source: KanjiChips.Source = withKanji.count == 1 ? withKanji[0] : (withKanji.isEmpty ? .text : .mixed)
        return KanjiChips(kanji: kanji(in: [text, spelling ?? ""] + standard), source: source)
    }
}

/// The kanji an entry's page offers as chips, and where they come from.
public struct KanjiChips: Equatable, Sendable {
    public enum Source: Equatable, Sendable { case text, spelling, standard, mixed }
    public let kanji: [Character]
    public let source: Source
}
