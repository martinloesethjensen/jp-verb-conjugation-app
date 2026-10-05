import Foundation
import SwiftData

@MainActor
public final class SwiftDataWordBankPersisting: WordBankPersisting {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Entries oldest first; folders by sort order then name; tags by name.
    public func load() throws -> WordBankSnapshot {
        let entries = try modelContext.fetch(FetchDescriptor<WordBankEntryEntity>())
            .map { $0.toValue() }
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        let folders = try modelContext.fetch(FetchDescriptor<WordBankFolderEntity>())
            .map { $0.toValue() }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        let dialectTags = try modelContext.fetch(FetchDescriptor<DialectTagEntity>())
            .map { $0.toValue() }
            .sorted { $0.name < $1.name }
        let customTags = try modelContext.fetch(FetchDescriptor<CustomTagEntity>())
            .map { $0.toValue() }
            .sorted { $0.name < $1.name }
        let smartFolders = try modelContext.fetch(FetchDescriptor<WordBankSmartFolderEntity>())
            .map { $0.toValue() }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        return WordBankSnapshot(
            entries: entries, folders: folders, dialectTags: dialectTags, customTags: customTags, smartFolders: smartFolders
        )
    }

    public func upsert(entry: WordBankEntryValue) throws {
        let row = try fetch(WordBankEntryEntity.self, id: entry.id) ?? {
            let row = WordBankEntryEntity(entry)
            modelContext.insert(row)
            return row
        }()
        row.update(from: entry)
        row.folder = try entry.folderID.flatMap { try fetch(WordBankFolderEntity.self, id: $0) }
        row.dialectTags = try entry.dialectTagIDs.compactMap { try fetch(DialectTagEntity.self, id: $0) }
        row.customTags = try entry.customTagIDs.compactMap { try fetch(CustomTagEntity.self, id: $0) }
        try modelContext.save()
    }

    public func delete(entryIDs: [UUID]) throws {
        for id in entryIDs {
            if let row = try fetch(WordBankEntryEntity.self, id: id) { modelContext.delete(row) }
        }
        try modelContext.save()
    }

    public func upsert(folder: WordBankFolderValue) throws {
        let row = try fetch(WordBankFolderEntity.self, id: folder.id) ?? {
            let row = WordBankFolderEntity(id: folder.id)
            modelContext.insert(row)
            return row
        }()
        row.name = folder.name
        row.sortOrder = folder.sortOrder
        row.parent = try folder.parentID.flatMap { try fetch(WordBankFolderEntity.self, id: $0) }
        try modelContext.save()
    }

    public func delete(folderIDs: [UUID]) throws {
        for id in folderIDs {
            if let row = try fetch(WordBankFolderEntity.self, id: id) { modelContext.delete(row) }
        }
        try modelContext.save()
    }

    public func upsert(dialectTag: DialectTagValue) throws {
        if let row = try fetch(DialectTagEntity.self, id: dialectTag.id) {
            row.update(from: dialectTag)
        } else {
            modelContext.insert(DialectTagEntity(dialectTag))
        }
        try modelContext.save()
    }

    public func upsert(customTag: CustomTagValue) throws {
        if let row = try fetch(CustomTagEntity.self, id: customTag.id) {
            row.update(from: customTag)
        } else {
            modelContext.insert(CustomTagEntity(customTag))
        }
        try modelContext.save()
    }

    public func delete(dialectTagIDs: [UUID], customTagIDs: [UUID]) throws {
        for id in dialectTagIDs {
            if let row = try fetch(DialectTagEntity.self, id: id) { modelContext.delete(row) }
        }
        for id in customTagIDs {
            if let row = try fetch(CustomTagEntity.self, id: id) { modelContext.delete(row) }
        }
        try modelContext.save()
    }

    public func upsert(smartFolder: WordBankSmartFolderValue) throws {
        let id = smartFolder.id
        if let row = try modelContext.fetch(FetchDescriptor(predicate: #Predicate<WordBankSmartFolderEntity> { $0.id == id })).first {
            row.update(from: smartFolder)
        } else {
            modelContext.insert(WordBankSmartFolderEntity(smartFolder))
        }
        try modelContext.save()
    }

    public func delete(smartFolderIDs: [UUID]) throws {
        for id in smartFolderIDs {
            if let row = try modelContext.fetch(FetchDescriptor(predicate: #Predicate<WordBankSmartFolderEntity> { $0.id == id })).first {
                modelContext.delete(row)
            }
        }
        try modelContext.save()
    }

    public func apply(_ changes: WordBankChanges) throws {
        guard !changes.isEmpty else { return }
        do {
            var folders = Dictionary(try modelContext.fetch(FetchDescriptor<WordBankFolderEntity>()).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var dialect = Dictionary(try modelContext.fetch(FetchDescriptor<DialectTagEntity>()).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var custom = Dictionary(try modelContext.fetch(FetchDescriptor<CustomTagEntity>()).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var entries = Dictionary(try modelContext.fetch(FetchDescriptor<WordBankEntryEntity>()).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var smart = Dictionary(try modelContext.fetch(FetchDescriptor<WordBankSmartFolderEntity>()).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

            for id in changes.deletedEntryIDs { if let row = entries.removeValue(forKey: id) { modelContext.delete(row) } }
            for id in changes.deletedSmartFolderIDs { if let row = smart.removeValue(forKey: id) { modelContext.delete(row) } }
            for id in changes.deletedFolderIDs { if let row = folders.removeValue(forKey: id) { modelContext.delete(row) } }
            for id in changes.deletedDialectTagIDs { if let row = dialect.removeValue(forKey: id) { modelContext.delete(row) } }
            for id in changes.deletedCustomTagIDs { if let row = custom.removeValue(forKey: id) { modelContext.delete(row) } }

            for tag in changes.dialectTags {
                if let row = dialect[tag.id] { row.update(from: tag) } else {
                    let row = DialectTagEntity(tag); modelContext.insert(row); dialect[tag.id] = row
                }
            }
            for tag in changes.customTags {
                if let row = custom[tag.id] { row.update(from: tag) } else {
                    let row = CustomTagEntity(tag); modelContext.insert(row); custom[tag.id] = row
                }
            }
            for folder in changes.folders where folders[folder.id] == nil {
                let row = WordBankFolderEntity(id: folder.id); modelContext.insert(row); folders[folder.id] = row
            }
            for folder in changes.folders {          // second pass: every row exists, so parents resolve in any order
                guard let row = folders[folder.id] else { continue }
                row.name = folder.name
                row.sortOrder = folder.sortOrder
                row.parent = folder.parentID.flatMap { folders[$0] }
            }
            for entry in changes.entries {
                let row: WordBankEntryEntity
                if let existing = entries[entry.id] { row = existing } else {
                    row = WordBankEntryEntity(entry); modelContext.insert(row); entries[entry.id] = row
                }
                row.update(from: entry)
                row.folder = entry.folderID.flatMap { folders[$0] }
                row.dialectTags = entry.dialectTagIDs.compactMap { dialect[$0] }
                row.customTags = entry.customTagIDs.compactMap { custom[$0] }
            }
            for folder in changes.smartFolders {
                if let row = smart[folder.id] { row.update(from: folder) } else {
                    let row = WordBankSmartFolderEntity(folder); modelContext.insert(row); smart[folder.id] = row
                }
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    // MARK: - Lookup by id

    private func fetch(_ type: WordBankEntryEntity.Type, id: UUID) throws -> WordBankEntryEntity? {
        try modelContext.fetch(FetchDescriptor(predicate: #Predicate<WordBankEntryEntity> { $0.id == id })).first
    }

    private func fetch(_ type: WordBankFolderEntity.Type, id: UUID) throws -> WordBankFolderEntity? {
        try modelContext.fetch(FetchDescriptor(predicate: #Predicate<WordBankFolderEntity> { $0.id == id })).first
    }

    private func fetch(_ type: DialectTagEntity.Type, id: UUID) throws -> DialectTagEntity? {
        try modelContext.fetch(FetchDescriptor(predicate: #Predicate<DialectTagEntity> { $0.id == id })).first
    }

    private func fetch(_ type: CustomTagEntity.Type, id: UUID) throws -> CustomTagEntity? {
        try modelContext.fetch(FetchDescriptor(predicate: #Predicate<CustomTagEntity> { $0.id == id })).first
    }
}
