import VerbKit

/// The Search tab's wording.
enum SearchDisplay {
    static func title(_ scope: SearchScope) -> String {
        switch scope {
        case .everything: "Everything"
        case .verbs: "Verbs"
        case .grammar: "Grammar"
        case .counters: "Counters"
        case .wordBank: "Word Bank"
        }
    }

    /// "Reading nomu as のむ · 4 results", or "4 results" when the query was not read as romaji.
    static func resultsLine(query: String, readingAs: String?, count: Int) -> String {
        let results = count == 1 ? "1 result" : "\(count) results"
        guard let readingAs else { return results }
        return "Reading \(query) as \(readingAs) · \(results)"
    }

    /// "1 more in a hidden level (N3)", "3 more in hidden levels (N2, N3)".
    static func hiddenLine(count: Int, levels: [JLPTLevel]) -> String {
        let names = levels.map(\.rawValue).joined(separator: ", ")
        let suffix = names.isEmpty ? "" : " (\(names))"
        return count == 1 ? "1 more in a hidden level\(suffix)" : "\(count) more in hidden levels\(suffix)"
    }

    static func noResults(_ query: String) -> String {
        "No results for “\(query)”"
    }
}
