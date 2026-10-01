import Foundation

/// Matches the title, the summary, and the Japanese text of every usage
/// example, so typing なんです or 頭が痛い both find the んです lesson.
/// Romaji input (ndesu, atama ga itai) is converted to hiragana and tried too.
public func matchesGrammarSearch(_ point: GrammarPoint, query: String) -> Bool {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return true }

    if point.title.contains(trimmed) { return true }
    if point.summary.localizedCaseInsensitiveContains(trimmed) { return true }
    for usage in point.usages {
        for example in usage.examples where example.jp.contains(trimmed) {
            return true
        }
    }
    if let converted = Romaji.toHiragana(trimmed) {
        let kana = converted.filter { !$0.isWhitespace }   // "atama ga itai" -> あたまがいたい
        if point.title.contains(kana) { return true }
        for usage in point.usages {
            for example in usage.examples where example.jp.contains(kana) {
                return true
            }
        }
    }
    return false
}
