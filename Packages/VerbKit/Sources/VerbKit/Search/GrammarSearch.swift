import Foundation

/// Matches the title, the summary, and the Japanese text of every usage
/// example, so typing なんです or 頭が痛い both find the んです lesson.
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
    return false
}
