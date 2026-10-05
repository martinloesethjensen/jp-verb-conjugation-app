import Foundation
import SwiftData

// The Word Bank's SwiftData models. They live in their own configuration and file
// (WordBank.sqlite), so the synced verb data and the user's notebook never share a
// store. They already follow CloudKit's rules for a later iCloud milestone: no
// unique attributes, every property defaulted or optional, every relationship
// optional with an inverse, identity in a `UUID` property. Enums are stored as raw
// strings; unknown raw values fall back to a default on load.

@Model
public final class WordBankEntryEntity {
    public var id: UUID = UUID()
    public var text: String = ""
    public var reading: String?
    public var kanjiSpelling: String?
    public var kindRaw: String = EntryKind.word.rawValue
    public var wordClassRaw: String?
    /// `[Sense]` and `[StandardEquivalent]` as JSON, like `VerbEntity.formsData`.
    var sensesData: Data = Data()
    var equivalentsData: Data = Data()
    public var linkedWordID: String?
    public var linkedFormID: String?
    public var notes: String?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var folder: WordBankFolderEntity?
    public var dialectTags: [DialectTagEntity]? = []
    public var customTags: [CustomTagEntity]? = []

    public init(_ value: WordBankEntryValue) {
        id = value.id
        update(from: value)
    }

    /// Copies every scalar field; relationships are set by the persister.
    func update(from value: WordBankEntryValue) {
        text = value.text
        reading = value.reading
        kanjiSpelling = value.kanjiSpelling
        kindRaw = value.kind.rawValue
        wordClassRaw = value.wordClass?.rawValue
        sensesData = (try? JSONEncoder().encode(value.senses)) ?? Data()
        equivalentsData = (try? JSONEncoder().encode(value.equivalents)) ?? Data()
        linkedWordID = value.linkedWordID
        linkedFormID = value.linkedFormID
        notes = value.notes
        createdAt = value.createdAt
        updatedAt = value.updatedAt
    }

    func toValue() -> WordBankEntryValue {
        WordBankEntryValue(
            id: id, text: text, reading: reading, kanjiSpelling: kanjiSpelling,
            kind: EntryKind(rawValue: kindRaw) ?? .word,
            wordClass: wordClassRaw.flatMap(WordClass.init(rawValue:)),
            senses: (try? JSONDecoder().decode([Sense].self, from: sensesData)) ?? [],
            equivalents: (try? JSONDecoder().decode([StandardEquivalent].self, from: equivalentsData)) ?? [],
            linkedWordID: linkedWordID, linkedFormID: linkedFormID, notes: notes,
            folderID: folder?.id,
            dialectTagIDs: (dialectTags ?? []).map(\.id).sorted { $0.uuidString < $1.uuidString },
            customTagIDs: (customTags ?? []).map(\.id).sorted { $0.uuidString < $1.uuidString },
            createdAt: createdAt, updatedAt: updatedAt
        )
    }
}

@Model
public final class WordBankFolderEntity {
    public var id: UUID = UUID()
    public var name: String = ""
    public var sortOrder: Int = 0
    public var parent: WordBankFolderEntity?
    @Relationship(deleteRule: .nullify, inverse: \WordBankFolderEntity.parent)
    public var children: [WordBankFolderEntity]? = []
    @Relationship(deleteRule: .nullify, inverse: \WordBankEntryEntity.folder)
    public var entries: [WordBankEntryEntity]? = []

    public init(id: UUID = UUID(), name: String = "", sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
    }

    func toValue() -> WordBankFolderValue {
        WordBankFolderValue(id: id, name: name, parentID: parent?.id, sortOrder: sortOrder)
    }
}

@Model
public final class DialectTagEntity {
    public var id: UUID = UUID()
    public var name: String = ""
    public var romaji: String?
    /// Prefecture raw values, comma-joined.
    public var prefecturesRaw: String = ""
    public var regionRaw: String = Region.hokkaido.rawValue
    public var catalogueID: String?
    @Relationship(deleteRule: .nullify, inverse: \WordBankEntryEntity.dialectTags)
    public var entries: [WordBankEntryEntity]? = []

    public init(_ value: DialectTagValue) {
        id = value.id
        update(from: value)
    }

    func update(from value: DialectTagValue) {
        name = value.name
        romaji = value.romaji
        prefecturesRaw = value.prefectures.map(\.rawValue).joined(separator: ",")
        regionRaw = value.region.rawValue
        catalogueID = value.catalogueID
    }

    func toValue() -> DialectTagValue {
        DialectTagValue(
            id: id, name: name, romaji: romaji,
            prefectures: prefecturesRaw.split(separator: ",").compactMap { Prefecture(rawValue: String($0)) },
            region: Region(rawValue: regionRaw) ?? .hokkaido,
            catalogueID: catalogueID
        )
    }
}

/// A tag-defined folder. Tag ids are kept as text, not relationships: a deleted tag simply
/// stops matching, and nothing here can cascade into entries or tags.
@Model
public final class WordBankSmartFolderEntity {
    public var id: UUID = UUID()
    public var name: String = ""
    public var sortOrder: Int = 0
    /// UUID strings, comma-joined.
    public var dialectTagIDsRaw: String = ""
    public var customTagIDsRaw: String = ""
    public var matchRaw: String = SmartFolderMatch.any.rawValue

    public init(_ value: WordBankSmartFolderValue) {
        id = value.id
        update(from: value)
    }

    func update(from value: WordBankSmartFolderValue) {
        name = value.name
        sortOrder = value.sortOrder
        dialectTagIDsRaw = value.dialectTagIDs.map(\.uuidString).joined(separator: ",")
        customTagIDsRaw = value.customTagIDs.map(\.uuidString).joined(separator: ",")
        matchRaw = value.match.rawValue
    }

    func toValue() -> WordBankSmartFolderValue {
        func ids(_ raw: String) -> [UUID] { raw.split(separator: ",").compactMap { UUID(uuidString: String($0)) } }
        return WordBankSmartFolderValue(
            id: id, name: name, dialectTagIDs: ids(dialectTagIDsRaw), customTagIDs: ids(customTagIDsRaw),
            match: SmartFolderMatch(rawValue: matchRaw) ?? .any, sortOrder: sortOrder
        )
    }
}

@Model
public final class CustomTagEntity {
    public var id: UUID = UUID()
    public var name: String = ""
    public var colorRaw: String = CustomTagColor.gray.rawValue
    @Relationship(deleteRule: .nullify, inverse: \WordBankEntryEntity.customTags)
    public var entries: [WordBankEntryEntity]? = []

    public init(_ value: CustomTagValue) {
        id = value.id
        update(from: value)
    }

    func update(from value: CustomTagValue) {
        name = value.name
        colorRaw = value.color.rawValue
    }

    func toValue() -> CustomTagValue {
        CustomTagValue(id: id, name: name, color: CustomTagColor(rawValue: colorRaw) ?? .gray)
    }
}
