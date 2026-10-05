import Foundation

/// The last ten Word Bank searches, newest first. Kept on this device only (standard
/// `UserDefaults`, under `defaultsKey`); never exported or synced.
public struct RecentSearches: Sendable {
    public static let defaultsKey = "wordBank.recentSearches"
    static let limit = 10

    public private(set) var items: [WordBankQuery]

    /// Corrupt or missing data loads as an empty list.
    public init(rawValue: Data?) {
        items = rawValue.flatMap { try? JSONDecoder().decode([WordBankQuery].self, from: $0) } ?? []
    }

    public var rawValue: Data {
        (try? JSONEncoder().encode(items)) ?? Data()
    }

    /// Adds `query` at the top. A search with the same text (after normalisation)
    /// and the same tokens moves up instead of appearing twice; an empty one is ignored.
    public mutating func record(_ query: WordBankQuery) {
        guard !JapaneseNormalizer.key(query.text).isEmpty || !query.tokens.isEmpty else { return }
        items.removeAll { Self.same($0, query) }
        items.insert(query, at: 0)
        if items.count > Self.limit { items.removeLast(items.count - Self.limit) }
    }

    public mutating func remove(_ query: WordBankQuery) {
        items.removeAll { Self.same($0, query) }
    }

    public mutating func clear() {
        items = []
    }

    private static func same(_ a: WordBankQuery, _ b: WordBankQuery) -> Bool {
        JapaneseNormalizer.key(a.text) == JapaneseNormalizer.key(b.text) && Set(a.tokens) == Set(b.tokens)
    }
}
