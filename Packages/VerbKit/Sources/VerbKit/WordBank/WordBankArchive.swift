import Foundation

/// The `.wordbank` file: JSON with a header, then folders, tags, smart folders and entries.
/// Reading is lenient (only `text` is required, so a hand-written or generated file with no
/// ids still imports); writing always writes everything.
public struct WordBankArchive: Equatable, Sendable {
    public static let formatName = "word-bank"
    public static let currentVersion = 1
    public static let maxBytes = 20 * 1024 * 1024
    /// Folders, tags, smart folders and entries together. A real bank is far smaller; this keeps a
    /// crafted file under `maxBytes` from freezing the import preview and planner.
    public static let maxRecords = 50_000
    /// An entry whose text, reading, kanji spelling or notes is longer than this is skipped.
    public static let maxFieldLength = 10_000

    public struct Folder: Codable, Equatable, Sendable {
        public var id: UUID?
        public var name: String
        public var parentID: UUID?
        public init(id: UUID? = nil, name: String, parentID: UUID? = nil) {
            self.id = id; self.name = name; self.parentID = parentID
        }
    }

    public struct DialectTag: Codable, Equatable, Sendable {
        public var id: UUID?
        public var name: String
        public var romaji: String?
        public var prefectures: [Prefecture]?
        public var region: Region?
        public var catalogueID: String?
        public init(
            id: UUID? = nil, name: String, romaji: String? = nil, prefectures: [Prefecture]? = nil,
            region: Region? = nil, catalogueID: String? = nil
        ) {
            self.id = id; self.name = name; self.romaji = romaji; self.prefectures = prefectures
            self.region = region; self.catalogueID = catalogueID
        }

        enum CodingKeys: String, CodingKey { case id, name, romaji, prefectures, region, catalogueID }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = c.lenient(UUID.self, .id)
            name = try c.decode(String.self, forKey: .name)
            romaji = c.lenient(String.self, .romaji)
            prefectures = c.lenient([Prefecture].self, .prefectures)
            region = c.lenient(Region.self, .region)
            catalogueID = c.lenient(String.self, .catalogueID)
        }
    }

    public struct CustomTag: Codable, Equatable, Sendable {
        public var id: UUID?
        public var name: String
        public var color: CustomTagColor?
        public init(id: UUID? = nil, name: String, color: CustomTagColor? = nil) {
            self.id = id; self.name = name; self.color = color
        }

        enum CodingKeys: String, CodingKey { case id, name, color }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = c.lenient(UUID.self, .id)
            name = try c.decode(String.self, forKey: .name)
            color = c.lenient(CustomTagColor.self, .color)
        }
    }

    public struct SmartFolder: Codable, Equatable, Sendable {
        public var name: String
        public var dialectTagNames: [String]
        public var customTagNames: [String]
        public var match: SmartFolderMatch
        public init(name: String, dialectTagNames: [String] = [], customTagNames: [String] = [], match: SmartFolderMatch = .any) {
            self.name = name; self.dialectTagNames = dialectTagNames
            self.customTagNames = customTagNames; self.match = match
        }

        enum CodingKeys: String, CodingKey { case name, dialectTagNames, customTagNames, match }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            dialectTagNames = c.lenient([String].self, .dialectTagNames) ?? []
            customTagNames = c.lenient([String].self, .customTagNames) ?? []
            match = c.lenient(SmartFolderMatch.self, .match) ?? .any
        }
    }

    public struct Entry: Codable, Equatable, Sendable {
        public var id: UUID?
        public var text: String
        public var reading: String?
        public var kanjiSpelling: String?
        public var kind: EntryKind
        public var wordClass: WordClass?
        public var senses: [Sense]
        public var equivalents: [StandardEquivalent]
        public var linkedWordID: String?
        public var linkedFormID: String?
        public var notes: String?
        public var folderID: UUID?
        /// `["Trip 2026", "Takayama"]`: lets a file with no `folders` list still file entries.
        public var folderPath: [String]
        public var dialectTagIDs: [UUID]
        public var dialectTagNames: [String]
        public var customTagIDs: [UUID]
        public var customTagNames: [String]
        public var createdAt: Date?
        public var updatedAt: Date?

        public init(
            id: UUID? = nil, text: String, reading: String? = nil, kanjiSpelling: String? = nil,
            kind: EntryKind = .word, wordClass: WordClass? = nil, senses: [Sense] = [],
            equivalents: [StandardEquivalent] = [], linkedWordID: String? = nil, linkedFormID: String? = nil,
            notes: String? = nil, folderID: UUID? = nil, folderPath: [String] = [],
            dialectTagIDs: [UUID] = [], dialectTagNames: [String] = [],
            customTagIDs: [UUID] = [], customTagNames: [String] = [],
            createdAt: Date? = nil, updatedAt: Date? = nil
        ) {
            self.id = id; self.text = text; self.reading = reading; self.kanjiSpelling = kanjiSpelling
            self.kind = kind; self.wordClass = wordClass; self.senses = senses; self.equivalents = equivalents
            self.linkedWordID = linkedWordID; self.linkedFormID = linkedFormID; self.notes = notes
            self.folderID = folderID; self.folderPath = folderPath
            self.dialectTagIDs = dialectTagIDs; self.dialectTagNames = dialectTagNames
            self.customTagIDs = customTagIDs; self.customTagNames = customTagNames
            self.createdAt = createdAt; self.updatedAt = updatedAt
        }

        enum CodingKeys: String, CodingKey {
            case id, text, reading, kanjiSpelling, kind, wordClass, senses, equivalents, linkedWordID
            case linkedFormID, notes, folderID, folderPath, dialectTagIDs, dialectTagNames
            case customTagIDs, customTagNames, createdAt, updatedAt
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = c.lenient(UUID.self, .id)
            text = try c.decode(String.self, forKey: .text)
            reading = c.lenient(String.self, .reading)
            kanjiSpelling = c.lenient(String.self, .kanjiSpelling)
            kind = c.lenient(EntryKind.self, .kind) ?? .word
            wordClass = c.lenient(WordClass.self, .wordClass)
            senses = c.lenient([Sense].self, .senses) ?? []
            equivalents = c.lenient([StandardEquivalent].self, .equivalents) ?? []
            linkedWordID = c.lenient(String.self, .linkedWordID)
            linkedFormID = c.lenient(String.self, .linkedFormID)
            notes = c.lenient(String.self, .notes)
            folderID = c.lenient(UUID.self, .folderID)
            folderPath = c.lenient([String].self, .folderPath) ?? []
            dialectTagIDs = c.lenient([UUID].self, .dialectTagIDs) ?? []
            dialectTagNames = c.lenient([String].self, .dialectTagNames) ?? []
            customTagIDs = c.lenient([UUID].self, .customTagIDs) ?? []
            customTagNames = c.lenient([String].self, .customTagNames) ?? []
            createdAt = c.lenient(Date.self, .createdAt)
            updatedAt = c.lenient(Date.self, .updatedAt)
        }
    }

    public struct Skipped: Equatable, Sendable {
        public var section: String
        public var position: Int
        public var reason: String
        public init(section: String, position: Int, reason: String) {
            self.section = section; self.position = position; self.reason = reason
        }
    }

    public enum ArchiveError: Error, Equatable, Sendable {
        case notAWordBank
        case newerVersion(Int)
        case tooLarge
        case tooManyRecords
    }

    public var exportedAt: Date
    public var folders: [Folder]
    public var dialectTags: [DialectTag]
    public var customTags: [CustomTag]
    public var smartFolders: [SmartFolder]
    public var entries: [Entry]
    public var skipped: [Skipped]

    public init(
        exportedAt: Date = Date(), folders: [Folder] = [], dialectTags: [DialectTag] = [],
        customTags: [CustomTag] = [], smartFolders: [SmartFolder] = [], entries: [Entry] = [],
        skipped: [Skipped] = []
    ) {
        self.exportedAt = exportedAt; self.folders = folders; self.dialectTags = dialectTags
        self.customTags = customTags; self.smartFolders = smartFolders; self.entries = entries
        self.skipped = skipped
    }

    // MARK: - Writing

    private struct Output: Encodable {
        var format = WordBankArchive.formatName
        var version = WordBankArchive.currentVersion
        var exportedAt: Date
        var folders: [Folder]
        var dialectTags: [DialectTag]
        var customTags: [CustomTag]
        var smartFolders: [SmartFolder]
        var entries: [Entry]
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.dateFormatter.string(from: date))
        }
        return try encoder.encode(Output(
            exportedAt: exportedAt, folders: folders, dialectTags: dialectTags, customTags: customTags,
            smartFolders: smartFolders, entries: entries
        ))
    }

    // MARK: - Reading

    private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        let failure: String?
        init(from decoder: Decoder) throws {
            do {
                value = try T(from: decoder)
                failure = nil
            } catch {
                value = nil
                failure = "Unreadable record (missing or invalid fields)"
            }
        }
    }

    private struct Input: Decodable {
        var format: String?
        var version: Int?
        var exportedAt: Date?
        var folders: [Lossy<Folder>]?
        var dialectTags: [Lossy<DialectTag>]?
        var customTags: [Lossy<CustomTag>]?
        var smartFolders: [Lossy<SmartFolder>]?
        var entries: [Lossy<Entry>]?
    }

    /// Reads at most `maxBytes + 1` bytes, so an oversized file is refused without loading it
    /// into memory. Use this for files from outside the app (Files, AirDrop, Mail).
    public static func read(contentsOf url: URL) throws -> WordBankArchive {
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxBytes {
            throw ArchiveError.tooLarge
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try decode(try handle.read(upToCount: maxBytes + 1) ?? Data())
    }

    public static func decode(_ data: Data) throws -> WordBankArchive {
        guard data.count <= maxBytes else { throw ArchiveError.tooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = Self.dateFormatter.date(from: text) ?? Self.fractionalFormatter.date(from: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date"))
            }
            return date
        }
        guard let input = try? decoder.decode(Input.self, from: data) else { throw ArchiveError.notAWordBank }
        if let format = input.format, format != formatName { throw ArchiveError.notAWordBank }
        if input.format == nil, input.entries == nil { throw ArchiveError.notAWordBank }
        let version = input.version ?? 1
        guard version <= currentVersion else { throw ArchiveError.newerVersion(version) }
        let records = [input.folders?.count, input.dialectTags?.count, input.customTags?.count,
                       input.smartFolders?.count, input.entries?.count].reduce(0) { $0 + ($1 ?? 0) }
        guard records <= maxRecords else { throw ArchiveError.tooManyRecords }

        var skipped: [Skipped] = []
        func unwrap<T>(_ section: String, _ items: [Lossy<T>]?) -> [T] {
            var result: [T] = []
            for (index, item) in (items ?? []).enumerated() {
                if let value = item.value { result.append(value) } else {
                    skipped.append(Skipped(section: section, position: index + 1, reason: item.failure ?? "Unreadable record"))
                }
            }
            return result
        }
        var archive = WordBankArchive(exportedAt: input.exportedAt ?? Date())
        archive.folders = unwrap("folders", input.folders)
        archive.dialectTags = unwrap("dialectTags", input.dialectTags)
        archive.customTags = unwrap("customTags", input.customTags)
        archive.smartFolders = unwrap("smartFolders", input.smartFolders)
        let decodedEntries = input.entries ?? []
        for (index, item) in decodedEntries.enumerated() {
            guard let entry = item.value else {
                skipped.append(Skipped(section: "entries", position: index + 1, reason: item.failure ?? "Missing text"))
                continue
            }
            if entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                skipped.append(Skipped(section: "entries", position: index + 1, reason: "Blank text"))
            } else if [entry.text, entry.reading, entry.kanjiSpelling, entry.notes]
                .contains(where: { ($0?.count ?? 0) > maxFieldLength }) {
                skipped.append(Skipped(section: "entries", position: index + 1, reason: "Text too long"))
            } else {
                archive.entries.append(entry)
            }
        }
        archive.skipped = skipped
        return archive
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private extension KeyedDecodingContainer {
    /// The value if present and valid, otherwise nil: one bad field never loses the record.
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}
