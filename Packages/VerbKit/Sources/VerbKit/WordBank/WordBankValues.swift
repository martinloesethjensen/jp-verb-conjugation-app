import Foundation

/// What an entry is. Filterable; only a `word` has a word class.
public enum EntryKind: String, Codable, CaseIterable, Sendable {
    case word, phrase, sentence
}

/// One meaning of an entry. Dialect words are often false friends, so a sense can
/// carry a note ("≠ standard 直す (fix)").
public struct Sense: Codable, Hashable, Sendable {
    public var meaning: String
    public var note: String?

    public init(meaning: String, note: String? = nil) {
        self.meaning = meaning
        self.note = note
    }
}

/// The standard Japanese an entry corresponds to: おおきに → ありがとう.
public struct StandardEquivalent: Codable, Hashable, Sendable {
    public var written: String
    public var reading: String?
    public var note: String?

    public init(written: String, reading: String? = nil, note: String? = nil) {
        self.written = written
        self.reading = reading
        self.note = note
    }
}

/// An entry as the UI and tests see it. The SwiftData entity mirrors it; tags and
/// the folder are referenced by id.
public struct WordBankEntryValue: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var text: String
    public var reading: String?
    public var kanjiSpelling: String?
    public var kind: EntryKind
    public var wordClass: WordClass?
    public var senses: [Sense]
    public var equivalents: [StandardEquivalent]
    /// `Word.id` of a curated word ("verb:いく"), and optionally a `FormID` raw value.
    /// Stored now; shown from milestone 4.
    public var linkedWordID: String?
    public var linkedFormID: String?
    /// Source and free notes ("Yuki, izakaya in Osaka").
    public var notes: String?
    public var folderID: UUID?
    public var dialectTagIDs: [UUID]
    public var customTagIDs: [UUID]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        text: String,
        reading: String? = nil,
        kanjiSpelling: String? = nil,
        kind: EntryKind = .word,
        wordClass: WordClass? = nil,
        senses: [Sense] = [],
        equivalents: [StandardEquivalent] = [],
        linkedWordID: String? = nil,
        linkedFormID: String? = nil,
        notes: String? = nil,
        folderID: UUID? = nil,
        dialectTagIDs: [UUID] = [],
        customTagIDs: [UUID] = [],
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.text = text
        self.reading = reading
        self.kanjiSpelling = kanjiSpelling
        self.kind = kind
        self.wordClass = wordClass
        self.senses = senses
        self.equivalents = equivalents
        self.linkedWordID = linkedWordID
        self.linkedFormID = linkedFormID
        self.notes = notes
        self.folderID = folderID
        self.dialectTagIDs = dialectTagIDs
        self.customTagIDs = customTagIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

/// A dialect tag: 熊本弁 in 熊本県, 九州・沖縄. A dialect spanning several
/// prefectures (関西弁) lists them all.
public struct DialectTagValue: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var romaji: String?
    public var prefectures: [Prefecture]
    public var region: Region
    /// The `DialectRecord.id` the tag was created from, if any.
    public var catalogueID: String?

    public init(
        id: UUID = UUID(), name: String, romaji: String? = nil,
        prefectures: [Prefecture] = [], region: Region, catalogueID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.romaji = romaji
        self.prefectures = prefectures
        self.region = region
        self.catalogueID = catalogueID
    }
}

/// The fixed palette custom tags choose from. Names, not colours, so the model stays
/// free of SwiftUI.
public enum CustomTagColor: String, Codable, CaseIterable, Sendable {
    case red, orange, yellow, green, teal, blue, purple, gray
}

public struct CustomTagValue: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var color: CustomTagColor

    public init(id: UUID = UUID(), name: String, color: CustomTagColor = .gray) {
        self.id = id
        self.name = name
        self.color = color
    }
}

public struct WordBankFolderValue: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// nil for a top-level folder.
    public var parentID: UUID?
    public var sortOrder: Int

    public init(id: UUID = UUID(), name: String, parentID: UUID? = nil, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.sortOrder = sortOrder
    }
}
