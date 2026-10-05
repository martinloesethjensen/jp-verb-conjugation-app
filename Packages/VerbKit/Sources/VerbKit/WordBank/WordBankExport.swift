import Foundation

public enum WordBankExportScope: Equatable, Sendable {
    case everything
    case folder(UUID)
    case entries([UUID])
}

extension WordBankArchive {
    public init(snapshot: WordBankSnapshot, scope: WordBankExportScope, exportedAt: Date = Date()) {
        let tree = FolderTree(snapshot.folders)
        var entries: [WordBankEntryValue]
        var folderIDs = Set<UUID>()
        var rootFolder: UUID?

        switch scope {
        case .everything:
            entries = snapshot.entries
            folderIDs = Set(snapshot.folders.map(\.id))
        case .folder(let id):
            guard tree.folder(id) != nil else {
                self.init(exportedAt: exportedAt)
                return
            }
            rootFolder = id
            folderIDs = tree.descendants(of: id).union([id])
            entries = snapshot.entries.filter { $0.folderID.map(folderIDs.contains) ?? false }
        case .entries(let ids):
            let wanted = Set(ids)
            entries = snapshot.entries.filter { wanted.contains($0.id) }
            for entry in entries {
                if let folder = entry.folderID { folderIDs.formUnion(tree.path(of: folder).map(\.id)) }
            }
        }
        entries.sort { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }

        let everything = scope == .everything
        let usedDialect = Set(entries.flatMap(\.dialectTagIDs))
        let usedCustom = Set(entries.flatMap(\.customTagIDs))
        let dialectTags = snapshot.dialectTags.filter { everything || usedDialect.contains($0.id) }
        let customTags = snapshot.customTags.filter { everything || usedCustom.contains($0.id) }
        let dialectNames = Dictionary(snapshot.dialectTags.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let customNames = Dictionary(snapshot.customTags.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

        func folderPath(_ id: UUID?) -> [String] {
            guard let id else { return [] }
            var path = tree.path(of: id)
            if let rootFolder { path = Array(path.drop { $0.id != rootFolder }) }
            return path.map(\.name)
        }

        self.init(
            exportedAt: exportedAt,
            folders: snapshot.folders.filter { folderIDs.contains($0.id) }.map {
                Folder(id: $0.id, name: $0.name, parentID: $0.id == rootFolder ? nil : $0.parentID)
            },
            dialectTags: dialectTags.map {
                DialectTag(id: $0.id, name: $0.name, romaji: $0.romaji, prefectures: $0.prefectures, region: $0.region, catalogueID: $0.catalogueID)
            },
            customTags: customTags.map { CustomTag(id: $0.id, name: $0.name, color: $0.color) },
            smartFolders: everything ? snapshot.smartFolders.map {
                SmartFolder(
                    name: $0.name,
                    dialectTagNames: $0.dialectTagIDs.compactMap { dialectNames[$0] },
                    customTagNames: $0.customTagIDs.compactMap { customNames[$0] },
                    match: $0.match
                )
            } : [],
            entries: entries.map { entry in
                Entry(
                    id: entry.id, text: entry.text, reading: entry.reading, kanjiSpelling: entry.kanjiSpelling,
                    kind: entry.kind, wordClass: entry.wordClass, senses: entry.senses, equivalents: entry.equivalents,
                    linkedWordID: entry.linkedWordID, linkedFormID: entry.linkedFormID, notes: entry.notes,
                    folderID: entry.folderID, folderPath: folderPath(entry.folderID),
                    dialectTagIDs: entry.dialectTagIDs, dialectTagNames: entry.dialectTagIDs.compactMap { dialectNames[$0] },
                    customTagIDs: entry.customTagIDs, customTagNames: entry.customTagIDs.compactMap { customNames[$0] },
                    createdAt: entry.createdAt, updatedAt: entry.updatedAt
                )
            }
        )
    }

    /// A file name without the extension.
    public static func suggestedFileName(
        for scope: WordBankExportScope, in snapshot: WordBankSnapshot, on date: Date = Date()
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: date)
        switch scope {
        case .everything:
            return "Word Bank \(day)"
        case .entries:
            return "Word Bank selection \(day)"
        case .folder(let id):
            guard let name = snapshot.folders.first(where: { $0.id == id })?.name else { return "Word Bank \(day)" }
            let cleaned = String(name.map { "/:\\".contains($0) ? "-" : $0 })
            return cleaned.isEmpty ? "Word Bank \(day)" : cleaned
        }
    }
}
