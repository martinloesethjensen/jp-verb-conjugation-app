import Foundation

/// The Word Bank's recently used tag ids, newest first, eight kept, on this device only (standard
/// `UserDefaults` under `key`, newline-separated). Views keep the raw string in `@AppStorage(key)`
/// so they update; these read and write it.
enum RecentTags {
    static let key = "wordBank.recentTags"
    static let limit = 8

    static func ids(from raw: String) -> [UUID] {
        raw.split(separator: "\n").compactMap { UUID(uuidString: String($0)) }
    }

    /// `raw` with `id` moved to the front.
    static func recording(_ id: UUID, in raw: String) -> String {
        ([id] + ids(from: raw).filter { $0 != id }).prefix(limit).map(\.uuidString).joined(separator: "\n")
    }
}
