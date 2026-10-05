import Foundation
import Observation

public enum FolderDeletion: Sendable {
    /// Entries and subfolders move up to the deleted folder's parent.
    case keepContents
    /// The folder, every folder below it and all their entries are deleted.
    case deleteContents
}

public enum WordBankError: Error, Equatable, Sendable {
    case blankText
    case blankName
    case duplicateFolderName
    case invalidMove
    case duplicateTagName
    /// Writing to the store failed; the change is kept in memory.
    case saveFailed
}

/// The Word Bank in memory, with the rules the persister doesn't know: text is
/// required, folder names are unique among siblings, folders can't move into
/// themselves, and what deleting a folder or tag does to what it holds.
/// A failed write keeps the change in memory and sets `lastError`.
@MainActor
@Observable
public final class WordBankStore {
    public private(set) var entries: [WordBankEntryValue] { didSet { searchDataChanged() } }
    public private(set) var folders: [WordBankFolderValue] { didSet { searchDataChanged() } }
    public private(set) var dialectTags: [DialectTagValue] { didSet { searchDataChanged() } }
    public private(set) var customTags: [CustomTagValue] { didSet { searchDataChanged() } }
    public private(set) var smartFolders: [WordBankSmartFolderValue]
    public private(set) var lastError: WordBankError?

    @ObservationIgnored private var cachedIndex: WordBankSearchIndex?
    @ObservationIgnored private var cachedReadingKey = 0
    /// Counts changes to what search reads; the cached index is valid for one revision.
    @ObservationIgnored private(set) var searchIndexRevision = 0
    /// How many times the index was built, so tests can see the cache working.
    @ObservationIgnored private(set) var searchIndexBuilds = 0
    @ObservationIgnored private let persisting: WordBankPersisting
    @ObservationIgnored private let now: () -> Date

    public init(persisting: WordBankPersisting, now: @escaping () -> Date = Date.init) {
        self.persisting = persisting
        self.now = now
        let snapshot = (try? persisting.load()) ?? WordBankSnapshot()
        entries = snapshot.entries
        folders = snapshot.folders
        dialectTags = snapshot.dialectTags
        customTags = snapshot.customTags
        smartFolders = snapshot.smartFolders
    }

    public var tree: FolderTree { FolderTree(folders) }

    public var snapshot: WordBankSnapshot {
        WordBankSnapshot(entries: entries, folders: folders, dialectTags: dialectTags, customTags: customTags, smartFolders: smartFolders)
    }

    /// Applies the changes in one save. Memory changes only after the write worked, so a
    /// failed import leaves the bank exactly as it was.
    public func apply(_ changes: WordBankChanges) throws {
        guard !changes.isEmpty else { return }
        do { try persisting.apply(changes) } catch {
            lastError = .saveFailed
            throw WordBankError.saveFailed
        }
        let updated = changes.applied(to: snapshot)
        entries = updated.entries
        folders = updated.folders
        dialectTags = updated.dialectTags
        customTags = updated.customTags
        smartFolders = updated.smartFolders
    }

    /// The search index for the bank as it is now. Built on first use after a change and then
    /// reused, so typing in the search field doesn't rebuild it. `readingKey` names the
    /// `derivedReading` function (for example how many readings the furigana dictionary has):
    /// a different key means the readings changed, so the index is rebuilt.
    public func searchIndex(
        readingKey: Int = 0, derivedReading: (String) -> String? = { _ in nil }
    ) -> WordBankSearchIndex {
        if let cachedIndex, cachedReadingKey == readingKey { return cachedIndex }
        let index = WordBankSearchIndex(
            entries: entries, folders: folders, dialectTags: dialectTags, customTags: customTags,
            derivedReading: derivedReading
        )
        cachedIndex = index
        cachedReadingKey = readingKey
        searchIndexBuilds += 1
        return index
    }

    private func searchDataChanged() {
        cachedIndex = nil
        searchIndexRevision += 1
    }

    // MARK: - Entries

    /// Trims the entry, drops blank senses and equivalents and unknown folder or
    /// tag ids, then inserts or replaces it. A new entry gets `createdAt` now;
    /// `updatedAt` only moves when something actually changed.
    @discardableResult
    public func save(_ entry: WordBankEntryValue) throws -> WordBankEntryValue {
        var clean = cleaned(entry)
        guard !clean.text.isEmpty else { throw WordBankError.blankText }
        let timestamp = now()
        if let index = entries.firstIndex(where: { $0.id == clean.id }) {
            let existing = entries[index]
            clean.createdAt = existing.createdAt
            clean.updatedAt = existing.updatedAt
            guard clean != existing else { return existing }
            clean.updatedAt = timestamp
            entries[index] = clean
        } else {
            clean.createdAt = timestamp
            clean.updatedAt = timestamp
            entries.append(clean)
        }
        persist { try persisting.upsert(entry: clean) }
        return clean
    }

    public func delete(entryIDs: [UUID]) {
        let ids = Set(entryIDs)
        entries.removeAll { ids.contains($0.id) }
        persist { try persisting.delete(entryIDs: entryIDs) }
    }

    public func move(entryIDs: [UUID], to folder: UUID?) {
        let target = folder.flatMap { id in folders.contains { $0.id == id } ? id : nil }
        for id in entryIDs {
            guard let index = entries.firstIndex(where: { $0.id == id }), entries[index].folderID != target else { continue }
            entries[index].folderID = target
            entries[index].updatedAt = now()
            let entry = entries[index]
            persist { try persisting.upsert(entry: entry) }
        }
    }

    // MARK: - Folders

    @discardableResult
    public func createFolder(named name: String, in parent: UUID?) throws -> WordBankFolderValue {
        let name = try validFolderName(name, in: parent, ignoring: nil)
        if let parent, !folders.contains(where: { $0.id == parent }) { throw WordBankError.invalidMove }
        let folder = WordBankFolderValue(name: name, parentID: parent, sortOrder: nextSortOrder(in: parent))
        folders.append(folder)
        persist { try persisting.upsert(folder: folder) }
        return folder
    }

    public func rename(folder id: UUID, to name: String) throws {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].name = try validFolderName(name, in: folders[index].parentID, ignoring: id)
        let folder = folders[index]
        persist { try persisting.upsert(folder: folder) }
    }

    public func move(folder id: UUID, to parent: UUID?) throws {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        guard folders[index].parentID != parent else { return }
        guard tree.canMove(id, to: parent) else { throw WordBankError.invalidMove }
        guard tree.nameIsFree(folders[index].name, in: parent, ignoring: id) else { throw WordBankError.duplicateFolderName }
        folders[index].sortOrder = nextSortOrder(in: parent)
        folders[index].parentID = parent
        let folder = folders[index]
        persist { try persisting.upsert(folder: folder) }
    }

    public func delete(folder id: UUID, _ mode: FolderDeletion) {
        guard let folder = folders.first(where: { $0.id == id }) else { return }
        let tree = tree
        switch mode {
        case .keepContents:
            let parent = folder.parentID
            move(entryIDs: entries.filter { $0.folderID == id }.map(\.id), to: parent)
            for child in tree.children(of: id) {
                guard let index = folders.firstIndex(where: { $0.id == child.id }) else { continue }
                folders[index].name = uniqueName(child.name, in: parent, ignoring: child.id)
                folders[index].parentID = parent
                folders[index].sortOrder = nextSortOrder(in: parent)
                let moved = folders[index]
                persist { try persisting.upsert(folder: moved) }
            }
            folders.removeAll { $0.id == id }
            persist { try persisting.delete(folderIDs: [id]) }
        case .deleteContents:
            let doomed = tree.descendants(of: id).union([id])
            let doomedEntries = entries.filter { $0.folderID.map(doomed.contains) ?? false }.map(\.id)
            entries.removeAll { doomedEntries.contains($0.id) }
            folders.removeAll { doomed.contains($0.id) }
            persist { try persisting.delete(entryIDs: doomedEntries) }
            persist { try persisting.delete(folderIDs: Array(doomed)) }
        }
    }

    // MARK: - Tags

    @discardableResult
    public func createDialectTag(_ tag: DialectTagValue) throws -> DialectTagValue {
        var tag = tag
        tag.name = tag.name.trimmingCharacters(in: .whitespacesAndNewlines)
        try checkDialectTag(tag)
        dialectTags.append(tag)
        persist { try persisting.upsert(dialectTag: tag) }
        return tag
    }

    @discardableResult
    public func createDialectTag(from record: DialectRecord) throws -> DialectTagValue {
        try createDialectTag(DialectTagValue(
            name: record.name, romaji: record.romaji, prefectures: record.prefectures,
            region: record.region, catalogueID: record.id
        ))
    }

    @discardableResult
    public func createCustomTag(named name: String, color: CustomTagColor) throws -> CustomTagValue {
        let tag = CustomTagValue(name: name.trimmingCharacters(in: .whitespacesAndNewlines), color: color)
        try checkCustomTag(tag)
        customTags.append(tag)
        persist { try persisting.upsert(customTag: tag) }
        return tag
    }

    public func update(dialectTag tag: DialectTagValue) throws {
        guard let index = dialectTags.firstIndex(where: { $0.id == tag.id }) else { return }
        var tag = tag
        tag.name = tag.name.trimmingCharacters(in: .whitespacesAndNewlines)
        try checkDialectTag(tag)
        dialectTags[index] = tag
        persist { try persisting.upsert(dialectTag: tag) }
    }

    public func update(customTag tag: CustomTagValue) throws {
        guard let index = customTags.firstIndex(where: { $0.id == tag.id }) else { return }
        var tag = tag
        tag.name = tag.name.trimmingCharacters(in: .whitespacesAndNewlines)
        try checkCustomTag(tag)
        customTags[index] = tag
        persist { try persisting.upsert(customTag: tag) }
    }

    public func delete(dialectTag id: UUID) {
        dialectTags.removeAll { $0.id == id }
        for index in entries.indices { entries[index].dialectTagIDs.removeAll { $0 == id } }
        persist { try persisting.delete(dialectTagIDs: [id], customTagIDs: []) }
        dropFromSmartFolders { $0.dialectTagIDs.removeAll { $0 == id } }
    }

    public func delete(customTag id: UUID) {
        customTags.removeAll { $0.id == id }
        for index in entries.indices { entries[index].customTagIDs.removeAll { $0 == id } }
        persist { try persisting.delete(dialectTagIDs: [], customTagIDs: [id]) }
        dropFromSmartFolders { $0.customTagIDs.removeAll { $0 == id } }
    }

    // MARK: - Smart folders

    /// A smart folder for one or more tags. Unknown tag ids are dropped; a folder with no
    /// tags is allowed (it shows nothing until tags are added), so deleting a tag never
    /// deletes the folder.
    @discardableResult
    public func createSmartFolder(
        named name: String, dialectTagIDs: [UUID], customTagIDs: [UUID], match: SmartFolderMatch
    ) throws -> WordBankSmartFolderValue {
        let name = try validSmartFolderName(name, ignoring: nil)
        var folder = WordBankSmartFolderValue(
            name: name, dialectTagIDs: dialectTagIDs, customTagIDs: customTagIDs, match: match,
            sortOrder: (smartFolders.map(\.sortOrder).max() ?? -1) + 1
        )
        folder = withKnownTags(folder)
        smartFolders.append(folder)
        persist { try persisting.upsert(smartFolder: folder) }
        return folder
    }

    public func update(smartFolder: WordBankSmartFolderValue) throws {
        guard let index = smartFolders.firstIndex(where: { $0.id == smartFolder.id }) else { return }
        var folder = withKnownTags(smartFolder)
        folder.name = try validSmartFolderName(smartFolder.name, ignoring: smartFolder.id)
        smartFolders[index] = folder
        persist { try persisting.upsert(smartFolder: folder) }
    }

    /// Never touches entries.
    public func delete(smartFolder id: UUID) {
        smartFolders.removeAll { $0.id == id }
        persist { try persisting.delete(smartFolderIDs: [id]) }
    }

    public func entries(in smartFolder: WordBankSmartFolderValue) -> [WordBankEntryValue] {
        entries.filter(smartFolder.matches)
    }

    private func validSmartFolderName(_ name: String, ignoring: UUID?) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw WordBankError.blankName }
        let key = JapaneseNormalizer.key(name)
        if smartFolders.contains(where: { $0.id != ignoring && JapaneseNormalizer.key($0.name) == key }) {
            throw WordBankError.duplicateFolderName
        }
        return name
    }

    private func withKnownTags(_ folder: WordBankSmartFolderValue) -> WordBankSmartFolderValue {
        var folder = folder
        let dialect = Set(dialectTags.map(\.id)), custom = Set(customTags.map(\.id))
        folder.dialectTagIDs = folder.dialectTagIDs.filter(dialect.contains)
        folder.customTagIDs = folder.customTagIDs.filter(custom.contains)
        return folder
    }

    private func dropFromSmartFolders(_ change: (inout WordBankSmartFolderValue) -> Void) {
        for index in smartFolders.indices {
            let before = smartFolders[index]
            change(&smartFolders[index])
            guard smartFolders[index] != before else { continue }
            let folder = smartFolders[index]
            persist { try persisting.upsert(smartFolder: folder) }
        }
    }

    // MARK: - Lookups

    /// Other entries with a standard equivalent (written or reading) in common.
    /// Groundwork for "same meaning in other dialects" (milestone 4).
    public func entries(sharingEquivalentWith entry: WordBankEntryValue) -> [WordBankEntryValue] {
        let keys = equivalentKeys(entry)
        guard !keys.isEmpty else { return [] }
        return entries.filter { $0.id != entry.id && !equivalentKeys($0).isDisjoint(with: keys) }
    }

    /// The entry whose text is `text` after normalisation, so the editor can offer
    /// it instead of a duplicate.
    public func entryWithSameText(as text: String, excluding: UUID?) -> WordBankEntryValue? {
        let key = JapaneseNormalizer.key(text)
        guard !key.isEmpty else { return nil }
        return entries.first { $0.id != excluding && JapaneseNormalizer.key($0.text) == key }
    }

    // MARK: - Helpers

    private func persist(_ write: () throws -> Void) {
        do {
            try write()
        } catch {
            lastError = .saveFailed
        }
    }

    private func cleaned(_ entry: WordBankEntryValue) -> WordBankEntryValue {
        var entry = entry.trimmed()
        if let folder = entry.folderID, !folders.contains(where: { $0.id == folder }) { entry.folderID = nil }
        let dialectIDs = Set(dialectTags.map(\.id))
        let customIDs = Set(customTags.map(\.id))
        entry.dialectTagIDs = entry.dialectTagIDs.filter(dialectIDs.contains)
        entry.customTagIDs = entry.customTagIDs.filter(customIDs.contains)
        return entry
    }

    private func validFolderName(_ name: String, in parent: UUID?, ignoring: UUID?) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw WordBankError.blankName }
        guard tree.nameIsFree(name, in: parent, ignoring: ignoring) else { throw WordBankError.duplicateFolderName }
        return name
    }

    /// `name`, or "name (2)", "name (3)"… if a sibling already has it.
    private func uniqueName(_ name: String, in parent: UUID?, ignoring: UUID) -> String {
        let tree = tree
        guard !tree.nameIsFree(name, in: parent, ignoring: ignoring) else { return name }
        var number = 2
        while !tree.nameIsFree("\(name) (\(number))", in: parent, ignoring: ignoring) { number += 1 }
        return "\(name) (\(number))"
    }

    private func nextSortOrder(in parent: UUID?) -> Int {
        (folders.filter { $0.parentID == parent }.map(\.sortOrder).max() ?? -1) + 1
    }

    private func checkDialectTag(_ tag: DialectTagValue) throws {
        guard !tag.name.isEmpty else { throw WordBankError.blankName }
        let key = JapaneseNormalizer.tagKey(tag.name)
        let clash = dialectTags.contains { other in
            other.id != tag.id && (
                JapaneseNormalizer.tagKey(other.name) == key
                    || (tag.catalogueID != nil && other.catalogueID == tag.catalogueID)
                    || catalogueKeys(other).contains(key)
            )
        }
        if clash { throw WordBankError.duplicateTagName }
    }

    /// A tag made from the catalogue also answers to its record's kana and romaji,
    /// so ひだべん can't become a second 飛騨弁.
    private func catalogueKeys(_ tag: DialectTagValue) -> Set<String> {
        guard let id = tag.catalogueID,
              let record = DialectCatalogue.bundled.dialects.first(where: { $0.id == id }) else { return [] }
        return Set(([record.kana, record.romaji] + record.aliases).map(JapaneseNormalizer.tagKey))
    }

    private func checkCustomTag(_ tag: CustomTagValue) throws {
        guard !tag.name.isEmpty else { throw WordBankError.blankName }
        let key = JapaneseNormalizer.key(tag.name)
        if customTags.contains(where: { $0.id != tag.id && JapaneseNormalizer.key($0.name) == key }) {
            throw WordBankError.duplicateTagName
        }
    }

    private func equivalentKeys(_ entry: WordBankEntryValue) -> Set<String> {
        Set(entry.equivalents.flatMap { [$0.written, $0.reading].compactMap { $0 } }.map(JapaneseNormalizer.key))
    }
}
