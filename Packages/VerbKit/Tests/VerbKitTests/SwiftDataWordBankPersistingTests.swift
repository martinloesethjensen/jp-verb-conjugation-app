import XCTest
import SwiftData
@testable import VerbKit

@MainActor
final class SwiftDataWordBankPersistingTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var persisting: SwiftDataWordBankPersisting!

    override func setUp() async throws {
        container = try VerbModelContainer.makeInMemory()
        context = ModelContext(container)
        persisting = SwiftDataWordBankPersisting(modelContext: context)
    }

    private let created = Date(timeIntervalSince1970: 1_000)
    private let updated = Date(timeIntervalSince1970: 2_000)

    private func fullEntry(folder: UUID?, dialect: [UUID], custom: [UUID]) -> WordBankEntryValue {
        WordBankEntryValue(
            text: "おおきに", reading: "おおきに", kanjiSpelling: "大きに", kind: .word, wordClass: .noun,
            senses: [Sense(meaning: "thank you", note: "Kansai"), Sense(meaning: "very much")],
            equivalents: [StandardEquivalent(written: "ありがとう", reading: "ありがとう", note: "standard")],
            linkedWordID: "verb:いく", linkedFormID: "short_neg", notes: "from Yuki",
            folderID: folder, dialectTagIDs: dialect, customTagIDs: custom,
            createdAt: created, updatedAt: updated
        )
    }

    func testEmptyBankLoadsEmpty() throws {
        XCTAssertEqual(try persisting.load(), WordBankSnapshot(entries: [], folders: [], dialectTags: [], customTags: []))
    }

    func testEveryEntryFieldRoundTrips() throws {
        let folder = WordBankFolderValue(name: "Trip", sortOrder: 2)
        let kansai = DialectTagValue(name: "関西弁", romaji: "Kansai-ben", prefectures: [.osaka, .kyoto], region: .kansai, catalogueID: "kansai-ben")
        let food = CustomTagValue(name: "food", color: .orange)
        try persisting.upsert(folder: folder)
        try persisting.upsert(dialectTag: kansai)
        try persisting.upsert(customTag: food)
        let entry = fullEntry(folder: folder.id, dialect: [kansai.id], custom: [food.id])
        try persisting.upsert(entry: entry)

        let snapshot = try persisting.load()
        XCTAssertEqual(snapshot.entries, [entry])
        XCTAssertEqual(snapshot.folders, [folder])
        XCTAssertEqual(snapshot.dialectTags, [kansai])
        XCTAssertEqual(snapshot.customTags, [food])
    }

    func testNilOptionalsRoundTrip() throws {
        let entry = WordBankEntryValue(text: "だんだん", kind: .phrase, createdAt: created)
        try persisting.upsert(entry: entry)
        XCTAssertEqual(try persisting.load().entries, [entry])
    }

    func testUpdatingAnEntryReplacesItsTagsAndFolder() throws {
        let a = DialectTagValue(name: "大阪弁", region: .kansai)
        let b = DialectTagValue(name: "京都弁", region: .kansai)
        let folder = WordBankFolderValue(name: "Kansai")
        try persisting.upsert(dialectTag: a)
        try persisting.upsert(dialectTag: b)
        try persisting.upsert(folder: folder)
        var entry = WordBankEntryValue(text: "おおきに", folderID: folder.id, dialectTagIDs: [a.id], createdAt: created)
        try persisting.upsert(entry: entry)

        entry.dialectTagIDs = [b.id]
        entry.folderID = nil
        entry.text = "おおきにー"
        try persisting.upsert(entry: entry)

        let loaded = try persisting.load().entries
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.dialectTagIDs, [b.id])
        XCTAssertNil(loaded.first?.folderID)
        XCTAssertEqual(loaded.first?.text, "おおきにー")
    }

    func testDeletingATagRemovesItFromEntriesButKeepsThem() throws {
        let tag = CustomTagValue(name: "slang")
        try persisting.upsert(customTag: tag)
        let entry = WordBankEntryValue(text: "めっちゃ", customTagIDs: [tag.id], createdAt: created)
        try persisting.upsert(entry: entry)

        try persisting.delete(dialectTagIDs: [], customTagIDs: [tag.id])

        let snapshot = try persisting.load()
        XCTAssertEqual(snapshot.customTags, [])
        XCTAssertEqual(snapshot.entries.map(\.customTagIDs), [[]])
    }

    func testDeletingAFolderRowUnfilesItsEntries() throws {
        let folder = WordBankFolderValue(name: "Trip")
        try persisting.upsert(folder: folder)
        try persisting.upsert(entry: WordBankEntryValue(text: "なんでやねん", folderID: folder.id, createdAt: created))

        try persisting.delete(folderIDs: [folder.id])

        let snapshot = try persisting.load()
        XCTAssertEqual(snapshot.folders, [])
        XCTAssertEqual(snapshot.entries.map(\.folderID), [nil])
    }

    func testNestedFoldersKeepTheirParent() throws {
        let trip = WordBankFolderValue(name: "Trip 2026")
        let takayama = WordBankFolderValue(name: "Takayama", parentID: trip.id, sortOrder: 1)
        try persisting.upsert(folder: trip)
        try persisting.upsert(folder: takayama)
        let folders = try persisting.load().folders
        XCTAssertEqual(Set(folders), [trip, takayama])
    }

    func testDeleteEntries() throws {
        let keep = WordBankEntryValue(text: "keep", createdAt: created)
        let drop = WordBankEntryValue(text: "drop", createdAt: created)
        try persisting.upsert(entry: keep)
        try persisting.upsert(entry: drop)
        try persisting.delete(entryIDs: [drop.id])
        XCTAssertEqual(try persisting.load().entries, [keep])
    }

    func testCorruptedSensesLoadAsEmpty() throws {
        let entry = WordBankEntryValue(text: "おおきに", senses: [Sense(meaning: "thanks")], createdAt: created)
        try persisting.upsert(entry: entry)
        let row = try XCTUnwrap(try context.fetch(FetchDescriptor<WordBankEntryEntity>()).first)
        row.sensesData = Data("not json".utf8)
        try context.save()
        XCTAssertEqual(try persisting.load().entries.first?.senses, [])
    }

    func testUnknownRawValuesFallBackToDefaults() throws {
        try persisting.upsert(dialectTag: DialectTagValue(name: "x弁", prefectures: [.gifu], region: .chubu))
        try persisting.upsert(customTag: CustomTagValue(name: "y", color: .blue))
        try persisting.upsert(entry: WordBankEntryValue(text: "z", kind: .sentence, wordClass: .verb, createdAt: created))
        try XCTUnwrap(try context.fetch(FetchDescriptor<DialectTagEntity>()).first).regionRaw = "atlantis"
        try XCTUnwrap(try context.fetch(FetchDescriptor<DialectTagEntity>()).first).prefecturesRaw = "gifu,nowhere"
        try XCTUnwrap(try context.fetch(FetchDescriptor<CustomTagEntity>()).first).colorRaw = "plaid"
        let row = try XCTUnwrap(try context.fetch(FetchDescriptor<WordBankEntryEntity>()).first)
        row.kindRaw = "poem"
        row.wordClassRaw = "adverb"
        try context.save()

        let snapshot = try persisting.load()
        XCTAssertEqual(snapshot.dialectTags.first?.region, .hokkaido)
        XCTAssertEqual(snapshot.dialectTags.first?.prefectures, [.gifu])
        XCTAssertEqual(snapshot.customTags.first?.color, .gray)
        XCTAssertEqual(snapshot.entries.first?.kind, .word)
        XCTAssertNil(snapshot.entries.first?.wordClass)
    }

    func testApplyWritesAFolderTreeTagsAndEntriesInOneGo() throws {
        let parent = WordBankFolderValue(name: "Trip"), child = WordBankFolderValue(name: "Takayama", parentID: parent.id)
        let tag = DialectTagValue(name: "飛騨弁", region: .chubu), custom = CustomTagValue(name: "food")
        let entry = WordBankEntryValue(text: "だちかん", folderID: child.id, dialectTagIDs: [tag.id], customTagIDs: [custom.id])
        var changes = WordBankChanges()
        changes.folders = [child, parent]               // child first on purpose: parents may arrive later
        changes.dialectTags = [tag]; changes.customTags = [custom]; changes.entries = [entry]
        changes.smartFolders = [WordBankSmartFolderValue(name: "Hida", dialectTagIDs: [tag.id])]
        try persisting.apply(changes)
        let loaded = try persisting.load()
        XCTAssertEqual(loaded.entries.first?.folderID, child.id)
        XCTAssertEqual(loaded.entries.first?.dialectTagIDs, [tag.id])
        XCTAssertEqual(Set(loaded.folders.map(\.name)), ["Trip", "Takayama"])
        XCTAssertEqual(loaded.folders.first { $0.id == child.id }?.parentID, parent.id)
        XCTAssertEqual(loaded.smartFolders.count, 1)
    }

    func testApplyDeletesAndUpdates() throws {
        let entry = WordBankEntryValue(text: "a"), gone = WordBankEntryValue(text: "b")
        try persisting.upsert(entry: entry); try persisting.upsert(entry: gone)
        var edited = entry
        edited.reading = "え"
        var changes = WordBankChanges()
        changes.entries = [edited]; changes.deletedEntryIDs = [gone.id]
        try persisting.apply(changes)
        let loaded = try persisting.load()
        XCTAssertEqual(loaded.entries.map(\.id), [entry.id])
        XCTAssertEqual(loaded.entries.first?.reading, "え")
    }
}
