import Foundation

/// Whether a smart folder needs any one of its tags or all of them.
public enum SmartFolderMatch: String, Codable, CaseIterable, Sendable {
    case any, all
}

/// A folder defined by tags instead of by filing: it shows every entry that has one of its
/// tags (`.any`) or all of them (`.all`). Entries aren't moved or copied, and deleting the
/// smart folder never touches them. A tag that is deleted drops out of the folder.
public struct WordBankSmartFolderValue: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var dialectTagIDs: [UUID]
    public var customTagIDs: [UUID]
    public var match: SmartFolderMatch
    public var sortOrder: Int

    public init(
        id: UUID = UUID(), name: String, dialectTagIDs: [UUID] = [], customTagIDs: [UUID] = [],
        match: SmartFolderMatch = .any, sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.dialectTagIDs = dialectTagIDs
        self.customTagIDs = customTagIDs
        self.match = match
        self.sortOrder = sortOrder
    }

    public var tagCount: Int { dialectTagIDs.count + customTagIDs.count }

    /// A folder with no tags matches nothing.
    public func matches(_ entry: WordBankEntryValue) -> Bool {
        guard tagCount > 0 else { return false }
        let dialect = Set(dialectTagIDs), custom = Set(customTagIDs)
        let hasDialect = Set(entry.dialectTagIDs), hasCustom = Set(entry.customTagIDs)
        switch match {
        case .any: return !dialect.isDisjoint(with: hasDialect) || !custom.isDisjoint(with: hasCustom)
        case .all: return dialect.isSubset(of: hasDialect) && custom.isSubset(of: hasCustom)
        }
    }
}
