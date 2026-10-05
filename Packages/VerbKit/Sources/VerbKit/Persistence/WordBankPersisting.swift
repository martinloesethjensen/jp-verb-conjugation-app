import Foundation

/// Everything in the Word Bank, as plain values.
public struct WordBankSnapshot: Equatable, Sendable {
    public var entries: [WordBankEntryValue]
    public var folders: [WordBankFolderValue]
    public var dialectTags: [DialectTagValue]
    public var customTags: [CustomTagValue]
    public var smartFolders: [WordBankSmartFolderValue]

    public init(
        entries: [WordBankEntryValue] = [], folders: [WordBankFolderValue] = [],
        dialectTags: [DialectTagValue] = [], customTags: [CustomTagValue] = [],
        smartFolders: [WordBankSmartFolderValue] = []
    ) {
        self.entries = entries
        self.folders = folders
        self.dialectTags = dialectTags
        self.customTags = customTags
        self.smartFolders = smartFolders
    }
}

/// Storage for the Word Bank. Rules (blank text, folder moves, what deleting a
/// folder does to its contents) live in `WordBankStore`; this only reads and writes.
@MainActor
public protocol WordBankPersisting {
    func load() throws -> WordBankSnapshot
    /// Inserts or replaces the entry with this id, including its folder and tags.
    /// Ids of folders or tags that don't exist are ignored.
    func upsert(entry: WordBankEntryValue) throws
    func delete(entryIDs: [UUID]) throws
    func upsert(folder: WordBankFolderValue) throws
    /// Folders only: the caller has already moved or deleted their contents.
    func delete(folderIDs: [UUID]) throws
    func upsert(dialectTag: DialectTagValue) throws
    func upsert(customTag: CustomTagValue) throws
    func delete(dialectTagIDs: [UUID], customTagIDs: [UUID]) throws
    func upsert(smartFolder: WordBankSmartFolderValue) throws
    func delete(smartFolderIDs: [UUID]) throws
    /// Writes everything in `changes` in one save. If it throws, nothing was written.
    func apply(_ changes: WordBankChanges) throws
}
