import Foundation

public enum ImportDestination: Equatable, Sendable {
    case root
    case folder(UUID)
}

public struct WordBankImportSummary: Equatable, Sendable {
    public var newEntries = 0
    public var combinedEntries = 0
    public var unchangedEntries = 0
    public var newFolders: [[String]] = []
    public var newDialectTags: [String] = []
    public var newCustomTags: [String] = []
    public var newSmartFolders: [String] = []
    public var skipped: [WordBankArchive.Skipped] = []

    public init() {}

    public var changesAnything: Bool {
        newEntries > 0 || combinedEntries > 0 || !newFolders.isEmpty || !newDialectTags.isEmpty
            || !newCustomTags.isEmpty || !newSmartFolders.isEmpty
    }
}

public struct WordBankImportPlan: Equatable, Sendable {
    public var changes: WordBankChanges
    public var summary: WordBankImportSummary
}

public enum WordBankImportPlanner {
    public static func plan(
        archive: WordBankArchive, into current: WordBankSnapshot, destination: ImportDestination = .root,
        now: Date = Date(), newID: @escaping () -> UUID = UUID.init, catalogue: DialectCatalogue = .bundled
    ) -> WordBankImportPlan {
        var run = Run(current: current, destination: destination, now: now, newID: newID, catalogue: catalogue)
        run.importFolders(archive.folders)
        run.importTags(archive)
        run.importSmartFolders(archive.smartFolders)
        run.importEntries(archive.entries)
        return run.finish(skipped: archive.skipped)
    }

    private enum LocalTag { case dialect(UUID), custom(UUID) }

    private struct Run {
        var snapshot: WordBankSnapshot                  // grows as things are added
        let destination: UUID?
        let destinationDepth: Int
        let now: Date
        let newID: () -> UUID
        let catalogue: DialectCatalogue
        var changes = WordBankChanges()
        var summary = WordBankImportSummary()
        var usedIDs: Set<UUID>
        var newFolderIDs: [UUID] = []
        var folderMap: [UUID: UUID] = [:]               // file id -> local id
        var dialectByFileID: [UUID: LocalTag] = [:]
        var customByFileID: [UUID: LocalTag] = [:]
        var entryIndexByID: [UUID: Int] = [:]
        var entryIndexesByText: [String: [Int]] = [:]
        var touched: [UUID: WordBankEntryValue] = [:]
        var touchedOrder: [UUID] = []

        init(current: WordBankSnapshot, destination: ImportDestination, now: Date, newID: @escaping () -> UUID, catalogue: DialectCatalogue) {
            snapshot = current
            if case .folder(let id) = destination, current.folders.contains(where: { $0.id == id }) {
                self.destination = id
                destinationDepth = FolderTree(current.folders).path(of: id).count
            } else {
                self.destination = nil
                destinationDepth = 0
            }
            self.now = now
            self.newID = newID
            self.catalogue = catalogue
            usedIDs = Set(current.entries.map(\.id) + current.folders.map(\.id) + current.dialectTags.map(\.id)
                + current.customTags.map(\.id) + current.smartFolders.map(\.id))
            for (index, entry) in current.entries.enumerated() {
                entryIndexByID[entry.id] = index
                entryIndexesByText[JapaneseNormalizer.key(entry.text), default: []].append(index)
            }
        }

        mutating func freshID(preferring id: UUID?) -> UUID {
            if let id, !usedIDs.contains(id) { usedIDs.insert(id); return id }
            var id = newID()
            while !usedIDs.insert(id).inserted { id = newID() }
            return id
        }

        // MARK: Folders

        mutating func childFolder(named rawName: String, under parent: UUID?, preferring id: UUID? = nil) -> UUID {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            let shown = name.isEmpty ? "Untitled" : name
            let key = JapaneseNormalizer.key(shown)
            if let existing = snapshot.folders.first(where: { $0.parentID == parent && JapaneseNormalizer.key($0.name) == key }) {
                return existing.id
            }
            let order = (snapshot.folders.filter { $0.parentID == parent }.map(\.sortOrder).max() ?? -1) + 1
            let folder = WordBankFolderValue(id: freshID(preferring: id), name: shown, parentID: parent, sortOrder: order)
            snapshot.folders.append(folder)
            changes.folders.append(folder)
            newFolderIDs.append(folder.id)
            return folder.id
        }

        mutating func resolve(folder id: UUID, in byID: [UUID: WordBankArchive.Folder], visiting: Set<UUID> = []) -> UUID? {
            if let done = folderMap[id] { return done }
            guard let folder = byID[id], !visiting.contains(id) else { return nil }
            let parent: UUID?
            if let parentID = folder.parentID, byID[parentID] != nil {
                parent = resolve(folder: parentID, in: byID, visiting: visiting.union([id])) ?? destination
            } else {
                parent = destination
            }
            let local: UUID
            if snapshot.folders.contains(where: { $0.id == id }) {
                local = id
            } else {
                local = childFolder(named: folder.name, under: parent, preferring: id)
            }
            folderMap[id] = local
            return local
        }

        mutating func importFolders(_ folders: [WordBankArchive.Folder]) {
            let byID = Dictionary(folders.compactMap { folder in folder.id.map { ($0, folder) } }, uniquingKeysWith: { first, _ in first })
            for folder in folders {
                if let id = folder.id { _ = resolve(folder: id, in: byID) } else {
                    _ = childFolder(named: folder.name, under: destination)
                }
            }
        }

        mutating func folder(forPath path: [String]) -> UUID? {
            var parent = destination
            for segment in path { parent = childFolder(named: segment, under: parent) }
            return parent
        }

        // MARK: Tags

        mutating func importTags(_ archive: WordBankArchive) {
            for record in archive.dialectTags { _ = dialect(record) }
            for record in archive.customTags { _ = custom(record) }
        }

        mutating func dialect(_ record: WordBankArchive.DialectTag) -> LocalTag {
            if let id = record.id, let known = dialectByFileID[id] { return known }
            let key = JapaneseNormalizer.tagKey(record.name)
            let local: LocalTag
            if let existing = snapshot.dialectTags.first(where: {
                $0.id == record.id || (record.catalogueID != nil && $0.catalogueID == record.catalogueID)
                    || JapaneseNormalizer.tagKey($0.name) == key
            }) {
                local = .dialect(existing.id)
            } else if let existing = snapshot.customTags.first(where: { JapaneseNormalizer.tagKey($0.name) == key }) {
                local = .custom(existing.id)
            } else {
                // A record with an id came from an export: only a hand-written one gets gaps filled from the catalogue.
                let known = catalogue.dialects.first {
                    $0.id == record.catalogueID || JapaneseNormalizer.tagKey($0.name) == key
                        || $0.aliases.contains { JapaneseNormalizer.tagKey($0) == key }
                }
                let prefectures = record.prefectures ?? known?.prefectures ?? []
                if let region = record.region ?? prefectures.first?.region ?? known?.region {
                    let tag = DialectTagValue(
                        id: freshID(preferring: record.id), name: record.name.trimmingCharacters(in: .whitespacesAndNewlines),
                        romaji: record.romaji ?? (record.id == nil ? known?.romaji : nil), prefectures: prefectures, region: region,
                        catalogueID: record.catalogueID ?? (record.id == nil ? known?.id : nil)
                    )
                    snapshot.dialectTags.append(tag)
                    changes.dialectTags.append(tag)
                    summary.newDialectTags.append(tag.name)
                    local = .dialect(tag.id)
                } else {
                    local = custom(WordBankArchive.CustomTag(id: record.id, name: record.name))
                }
            }
            if let id = record.id { dialectByFileID[id] = local }
            return local
        }

        mutating func custom(_ record: WordBankArchive.CustomTag) -> LocalTag {
            if let id = record.id, let known = customByFileID[id] { return known }
            let key = JapaneseNormalizer.tagKey(record.name)
            let local: LocalTag
            if let existing = snapshot.customTags.first(where: { $0.id == record.id || JapaneseNormalizer.tagKey($0.name) == key }) {
                local = .custom(existing.id)
            } else {
                let tag = CustomTagValue(
                    id: freshID(preferring: record.id), name: record.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    color: record.color ?? .gray
                )
                snapshot.customTags.append(tag)
                changes.customTags.append(tag)
                summary.newCustomTags.append(tag.name)
                local = .custom(tag.id)
            }
            if let id = record.id { customByFileID[id] = local }
            return local
        }

        // MARK: Smart folders

        mutating func importSmartFolders(_ folders: [WordBankArchive.SmartFolder]) {
            for folder in folders {
                let key = JapaneseNormalizer.key(folder.name)
                guard !snapshot.smartFolders.contains(where: { JapaneseNormalizer.key($0.name) == key }) else { continue }
                var dialectIDs: [UUID] = [], customIDs: [UUID] = []
                for name in folder.dialectTagNames {
                    switch dialect(.init(name: name)) { case .dialect(let id): dialectIDs.append(id); case .custom(let id): customIDs.append(id) }
                }
                for name in folder.customTagNames {
                    switch custom(.init(name: name)) { case .custom(let id), .dialect(let id): customIDs.append(id) }
                }
                guard !dialectIDs.isEmpty || !customIDs.isEmpty else { continue }
                let order = (snapshot.smartFolders.map(\.sortOrder).max() ?? -1) + 1
                let smart = WordBankSmartFolderValue(
                    id: freshID(preferring: nil), name: folder.name, dialectTagIDs: dialectIDs,
                    customTagIDs: customIDs, match: folder.match, sortOrder: order
                )
                snapshot.smartFolders.append(smart)
                changes.smartFolders.append(smart)
                summary.newSmartFolders.append(smart.name)
            }
        }

        // MARK: Entries

        mutating func importEntries(_ entries: [WordBankArchive.Entry]) {
            for record in entries { importEntry(record) }
        }

        mutating func importEntry(_ record: WordBankArchive.Entry) {
            var folderID: UUID? = destination
            if let id = record.folderID, let mapped = folderMap[id] ?? (snapshot.folders.contains { $0.id == id } ? id : nil) {
                folderID = mapped
            } else if !record.folderPath.isEmpty {
                folderID = folder(forPath: record.folderPath)
            }
            var dialectIDs: [UUID] = [], customIDs: [UUID] = []
            func add(_ tag: LocalTag) {
                switch tag {
                case .dialect(let id): if !dialectIDs.contains(id) { dialectIDs.append(id) }
                case .custom(let id): if !customIDs.contains(id) { customIDs.append(id) }
                }
            }
            for id in record.dialectTagIDs { if let known = dialectByFileID[id] { add(known) } }
            for name in record.dialectTagNames { add(dialect(.init(name: name))) }
            for id in record.customTagIDs { if let known = customByFileID[id] { add(known) } }
            for name in record.customTagNames { add(custom(.init(name: name))) }

            let created = record.createdAt ?? now
            let incoming = WordBankEntryValue(
                id: record.id ?? UUID(), text: record.text, reading: record.reading, kanjiSpelling: record.kanjiSpelling,
                kind: record.kind, wordClass: record.wordClass, senses: record.senses, equivalents: record.equivalents,
                linkedWordID: record.linkedWordID, linkedFormID: record.linkedFormID, notes: record.notes,
                folderID: folderID, dialectTagIDs: dialectIDs, customTagIDs: customIDs,
                createdAt: created, updatedAt: record.updatedAt ?? created
            ).trimmed()

            if let index = match(incoming) {
                let local = snapshot.entries[index]
                let combined = WordBankEntryCombiner.combine(
                    local: local, incoming: incoming, importedFolderID: folderID, importedOn: now, now: now
                )
                if combined.changed { summary.combinedEntries += 1 } else { summary.unchangedEntries += 1 }
                if combined.entry != local {
                    snapshot.entries[index] = combined.entry
                    touch(combined.entry)
                }
            } else {
                var entry = incoming
                entry.id = freshID(preferring: record.id)
                snapshot.entries.append(entry)
                entryIndexByID[entry.id] = snapshot.entries.count - 1
                entryIndexesByText[JapaneseNormalizer.key(entry.text), default: []].append(snapshot.entries.count - 1)
                touch(entry)
                summary.newEntries += 1
            }
        }

        func match(_ incoming: WordBankEntryValue) -> Int? {
            if let index = entryIndexByID[incoming.id] { return index }
            let candidates = entryIndexesByText[JapaneseNormalizer.key(incoming.text)] ?? []
            if let reading = incoming.reading {
                let key = JapaneseNormalizer.key(reading)
                return candidates.first { JapaneseNormalizer.key(snapshot.entries[$0].reading ?? "") == key }
            }
            return candidates.count == 1 ? candidates[0] : nil
        }

        mutating func touch(_ entry: WordBankEntryValue) {
            if touched[entry.id] == nil { touchedOrder.append(entry.id) }
            touched[entry.id] = entry
        }

        // MARK: Result

        mutating func finish(skipped: [WordBankArchive.Skipped]) -> WordBankImportPlan {
            changes.entries = touchedOrder.compactMap { touched[$0] }
            let tree = FolderTree(snapshot.folders)
            summary.newFolders = newFolderIDs.map { Array(tree.path(of: $0).dropFirst(destinationDepth).map(\.name)) }
            summary.skipped = skipped
            return WordBankImportPlan(changes: changes, summary: summary)
        }
    }
}
