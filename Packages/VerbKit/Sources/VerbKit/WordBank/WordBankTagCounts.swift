import Foundation

/// How many entries carry a tag (dialect or custom).
public struct WordBankTagCount: Equatable, Sendable {
    public let tagID: UUID
    public let count: Int
}

/// The Word Bank list's tag chips (canvas board "Proposed: Word Bank"): the most used tags first.
public enum WordBankTagCounts {
    /// Tags by how many of `entries` carry them, most first, ties by id; at most `limit`.
    public static func top(_ entries: [WordBankEntryValue], limit: Int) -> [WordBankTagCount] {
        var counts: [UUID: Int] = [:]
        for entry in entries {
            for id in Set(entry.dialectTagIDs + entry.customTagIDs) { counts[id, default: 0] += 1 }
        }
        return counts
            .map { WordBankTagCount(tagID: $0.key, count: $0.value) }
            .sorted { ($0.count, $1.tagID.uuidString) > ($1.count, $0.tagID.uuidString) }
            .prefix(max(0, limit))
            .map { $0 }
    }
}
