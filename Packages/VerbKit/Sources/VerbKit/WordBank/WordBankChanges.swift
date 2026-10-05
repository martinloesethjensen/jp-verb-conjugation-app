import Foundation

/// A set of writes to apply together (an import, or a restore).
public struct WordBankChanges: Equatable, Sendable {
    public var entries: [WordBankEntryValue] = []
    public var folders: [WordBankFolderValue] = []
    public var dialectTags: [DialectTagValue] = []
    public var customTags: [CustomTagValue] = []
    public var smartFolders: [WordBankSmartFolderValue] = []
    public var deletedEntryIDs: [UUID] = []
    public var deletedFolderIDs: [UUID] = []
    public var deletedDialectTagIDs: [UUID] = []
    public var deletedCustomTagIDs: [UUID] = []
    public var deletedSmartFolderIDs: [UUID] = []

    public init() {}

    public var isEmpty: Bool {
        entries.isEmpty && folders.isEmpty && dialectTags.isEmpty && customTags.isEmpty && smartFolders.isEmpty
            && deletedEntryIDs.isEmpty && deletedFolderIDs.isEmpty && deletedDialectTagIDs.isEmpty
            && deletedCustomTagIDs.isEmpty && deletedSmartFolderIDs.isEmpty
    }

    public func applied(to snapshot: WordBankSnapshot) -> WordBankSnapshot {
        func merge<T: Identifiable>(_ existing: [T], upserts: [T], deleted: [UUID]) -> [T] where T.ID == UUID {
            var result = existing.filter { !deleted.contains($0.id) }
            for item in upserts {
                if let index = result.firstIndex(where: { $0.id == item.id }) { result[index] = item } else { result.append(item) }
            }
            return result
        }
        var result = WordBankSnapshot(
            entries: merge(snapshot.entries, upserts: entries, deleted: deletedEntryIDs),
            folders: merge(snapshot.folders, upserts: folders, deleted: deletedFolderIDs),
            dialectTags: merge(snapshot.dialectTags, upserts: dialectTags, deleted: deletedDialectTagIDs),
            customTags: merge(snapshot.customTags, upserts: customTags, deleted: deletedCustomTagIDs),
            smartFolders: merge(snapshot.smartFolders, upserts: smartFolders, deleted: deletedSmartFolderIDs)
        )
        // Same order as `SwiftDataWordBankPersisting.load()`.
        result.entries.sort { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        result.folders.sort { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        result.dialectTags.sort { $0.name < $1.name }
        result.customTags.sort { $0.name < $1.name }
        result.smartFolders.sort { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        return result
    }

    public static func replacing(_ current: WordBankSnapshot, with replacement: WordBankSnapshot) -> WordBankChanges {
        func diff<T: Identifiable & Equatable>(_ old: [T], _ new: [T]) -> (upserts: [T], deleted: [UUID]) where T.ID == UUID {
            let oldByID = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let newIDs = Set(new.map(\.id))
            return (new.filter { oldByID[$0.id] != $0 }, old.map(\.id).filter { !newIDs.contains($0) })
        }
        var changes = WordBankChanges()
        (changes.entries, changes.deletedEntryIDs) = diff(current.entries, replacement.entries)
        (changes.folders, changes.deletedFolderIDs) = diff(current.folders, replacement.folders)
        (changes.dialectTags, changes.deletedDialectTagIDs) = diff(current.dialectTags, replacement.dialectTags)
        (changes.customTags, changes.deletedCustomTagIDs) = diff(current.customTags, replacement.customTags)
        (changes.smartFolders, changes.deletedSmartFolderIDs) = diff(current.smartFolders, replacement.smartFolders)
        return changes
    }
}
