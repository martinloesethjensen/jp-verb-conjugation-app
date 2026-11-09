import Foundation

/// Where a lesson's pattern sits in an example sentence, so the page can underline it.
public enum GrammarHighlight {
    /// The lesson's patterns, longest first: its endings (rules' `then` and the formula's endings),
    /// its title split on ・, and its forms (〜かもしれません, かも), each without 〜. Single characters
    /// are left out: a lone な would underline every な.
    public static func patterns(of point: GrammarPoint) -> [String] {
        var candidates = point.attachment.compactMap(\.then)
        candidates += point.formula?.endings ?? []
        candidates += point.title.components(separatedBy: "・")
        candidates += point.conjugations.flatMap { $0.form.components(separatedBy: CharacterSet(charactersIn: "·/")) }
        var seen = Set<String>()
        return candidates
            .map { $0.replacingOccurrences(of: "〜", with: "").trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 2 && seen.insert($0).inserted }
            .sorted { $0.count > $1.count }
    }

    /// Character offsets of the longest pattern found in `text` (its first occurrence), or nil.
    public static func range(in text: String, patterns: [String]) -> Range<Int>? {
        for pattern in patterns.sorted(by: { $0.count > $1.count }) {
            if let found = text.range(of: pattern) {
                let start = text.distance(from: text.startIndex, to: found.lowerBound)
                return start..<(start + pattern.count)
            }
        }
        return nil
    }
}
