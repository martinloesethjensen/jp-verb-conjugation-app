import Foundation

/// How strongly a grammar point matches a search, best first. Learners search by what they
/// want to say ("because", "had better"), so a keyword counts as much as the title, and a hit
/// in a usage heading or an example sentence only counts after those.
public enum GrammarSearchRank: Int, Comparable, Sendable {
    /// The query is the whole title or a whole keyword ("must" for the must lesson).
    case exact
    /// The query is part of the title or of a keyword ("must" inside "must not").
    case titleOrKeyword
    /// The query is in the one-line summary.
    case summary
    /// The query is in a usage heading.
    case heading
    /// The query is in an example: its Japanese, its kana reading or its English.
    case example

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Matches the title, the keywords, the summary, the usage headings and every usage example
/// (Japanese and English), so typing なんです, 頭が痛い or "because" all find a lesson.
/// Romaji input (ndesu, atama ga itai) is converted to hiragana and tried too.
/// With a furigana dictionary, examples are also matched by their kana reading,
/// so `atama ga itai` finds 頭が痛いんです.
public func matchesGrammarSearch(
    _ point: GrammarPoint,
    query: String,
    furigana: FuriganaDictionary? = nil
) -> Bool {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return true }
    return grammarSearchRank(point, query: trimmed, furigana: furigana) != nil
}

/// The best place `query` matches in `point`, or nil when it does not match.
/// An empty query has no rank (it matches everything; see `matchesGrammarSearch`).
public func grammarSearchRank(
    _ point: GrammarPoint,
    query: String,
    furigana: FuriganaDictionary? = nil
) -> GrammarSearchRank? {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    // "atama ga itai" -> あたまがいたい
    let kana = Romaji.toHiragana(trimmed).map { $0.filter { !$0.isWhitespace } }
    func matches(_ text: String) -> Bool {
        if text.localizedCaseInsensitiveContains(trimmed) { return true }
        if let kana, text.contains(kana) { return true }
        return false
    }
    func same(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).compare(trimmed, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame
            || text == kana
    }

    let names = [point.title] + point.keywords
    if names.contains(where: same) { return .exact }
    if names.contains(where: matches) { return .titleOrKeyword }
    if point.summary.localizedCaseInsensitiveContains(trimmed) { return .summary }
    if point.usages.contains(where: { matches($0.heading) }) { return .heading }
    for usage in point.usages {
        for example in usage.examples {
            if matches(example.jp) || example.en.localizedCaseInsensitiveContains(trimmed) { return .example }
            if let furigana {
                let reading = furigana.reading(of: example.jp)
                if reading.contains(trimmed) || kana.map(reading.contains) == true { return .example }
            }
        }
    }
    return nil
}

public extension Sequence where Element == GrammarPoint {
    /// The points matching `query`, best match first; ties keep their order here (the Grammar
    /// tab's order). An empty query returns every point in order.
    func searched(for query: String, furigana: FuriganaDictionary? = nil) -> [GrammarPoint] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Array(self) }
        return enumerated()
            .compactMap { offset, point in
                grammarSearchRank(point, query: trimmed, furigana: furigana).map { (rank: $0, offset: offset, point: point) }
            }
            .sorted { ($0.rank, $0.offset) < ($1.rank, $1.offset) }
            .map(\.point)
    }
}
