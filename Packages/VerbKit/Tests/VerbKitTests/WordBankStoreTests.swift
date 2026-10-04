import XCTest
@testable import VerbKit

@MainActor
final class WordBankStoreTests: XCTestCase {
    private struct Boom: Error {}

    /// An in-memory persister that counts calls and can fail.
    private final class Double: WordBankPersisting {
        var snapshot = WordBankSnapshot()
        var failing = false
        var writes = 0

        func load() throws -> WordBankSnapshot { snapshot }
        private func write() throws { writes += 1; if failing { throw Boom() } }
        func upsert(entry: WordBankEntryValue) throws {
            try write()
            snapshot.entries.removeAll { $0.id == entry.id }
            snapshot.entries.append(entry)
        }
        func delete(entryIDs: [UUID]) throws { try write(); snapshot.entries.removeAll { entryIDs.contains($0.id) } }
        func upsert(folder: WordBankFolderValue) throws {
            try write()
            snapshot.folders.removeAll { $0.id == folder.id }
            snapshot.folders.append(folder)
        }
        func delete(folderIDs: [UUID]) throws { try write(); snapshot.folders.removeAll { folderIDs.contains($0.id) } }
        func upsert(dialectTag: DialectTagValue) throws {
            try write()
            snapshot.dialectTags.removeAll { $0.id == dialectTag.id }
            snapshot.dialectTags.append(dialectTag)
        }
        func upsert(customTag: CustomTagValue) throws {
            try write()
            snapshot.customTags.removeAll { $0.id == customTag.id }
            snapshot.customTags.append(customTag)
        }
        func delete(dialectTagIDs: [UUID], customTagIDs: [UUID]) throws {
            try write()
            snapshot.dialectTags.removeAll { dialectTagIDs.contains($0.id) }
            snapshot.customTags.removeAll { customTagIDs.contains($0.id) }
        }
    }

    private var clock = Date(timeIntervalSince1970: 1_000)
    private var persisting: Double!
    private var store: WordBankStore!

    override func setUp() async throws {
        persisting = Double()
        store = WordBankStore(persisting: persisting, now: { [unowned self] in self.clock })
    }

    private func tick() { clock = clock.addingTimeInterval(60) }

    // MARK: entries

    func testLoadsWhatIsStored() {
        let entry = WordBankEntryValue(text: "おおきに")
        persisting.snapshot.entries = [entry]
        XCTAssertEqual(WordBankStore(persisting: persisting).entries, [entry])
    }

    func testSaveRejectsBlankText() {
        XCTAssertThrowsError(try store.save(WordBankEntryValue(text: "  \n"))) { error in
            XCTAssertEqual(error as? WordBankError, .blankText)
        }
        XCTAssertEqual(store.entries, [])
    }

    func testSaveTrimsAndDropsBlankSensesAndEquivalents() throws {
        let saved = try store.save(WordBankEntryValue(
            text: "  おおきに ", reading: " ",
            senses: [Sense(meaning: " thank you "), Sense(meaning: "  ")],
            equivalents: [StandardEquivalent(written: ""), StandardEquivalent(written: "ありがとう", reading: " ")],
            notes: ""
        ))
        XCTAssertEqual(saved.text, "おおきに")
        XCTAssertNil(saved.reading)
        XCTAssertNil(saved.notes)
        XCTAssertEqual(saved.senses, [Sense(meaning: "thank you")])
        XCTAssertEqual(saved.equivalents, [StandardEquivalent(written: "ありがとう")])
        XCTAssertEqual(store.entries, [saved])
        XCTAssertEqual(persisting.snapshot.entries, [saved])
    }

    func testSaveSetsDatesAndOnlyBumpsUpdatedWhenSomethingChanged() throws {
        var entry = try store.save(WordBankEntryValue(text: "おおきに", createdAt: .distantPast))
        XCTAssertEqual(entry.createdAt, clock)
        XCTAssertEqual(entry.updatedAt, clock)
        let created = clock

        tick()
        let unchanged = try store.save(entry)
        XCTAssertEqual(unchanged.updatedAt, created)

        tick()
        entry.reading = "おおきに"
        let changed = try store.save(entry)
        XCTAssertEqual(changed.createdAt, created)
        XCTAssertEqual(changed.updatedAt, clock)
    }

    func testSaveDropsUnknownFolderAndTagIDs() throws {
        let saved = try store.save(WordBankEntryValue(text: "x", folderID: UUID(), dialectTagIDs: [UUID()], customTagIDs: [UUID()]))
        XCTAssertNil(saved.folderID)
        XCTAssertEqual(saved.dialectTagIDs, [])
        XCTAssertEqual(saved.customTagIDs, [])
    }

    func testDeleteEntries() throws {
        let a = try store.save(WordBankEntryValue(text: "a"))
        let b = try store.save(WordBankEntryValue(text: "b"))
        store.delete(entryIDs: [a.id])
        XCTAssertEqual(store.entries.map(\.id), [b.id])
        XCTAssertEqual(persisting.snapshot.entries.map(\.id), [b.id])
    }

    func testMoveEntries() throws {
        let folder = try store.createFolder(named: "Trip", in: nil)
        let a = try store.save(WordBankEntryValue(text: "a"))
        store.move(entryIDs: [a.id], to: folder.id)
        XCTAssertEqual(store.entries.first?.folderID, folder.id)
        store.move(entryIDs: [a.id], to: nil)
        XCTAssertNil(store.entries.first?.folderID)
    }

    // MARK: folders

    func testCreateAndRenameRejectDuplicatesAndBlanks() throws {
        let trip = try store.createFolder(named: "Trip", in: nil)
        XCTAssertThrowsError(try store.createFolder(named: "ｔｒｉｐ", in: nil)) { XCTAssertEqual($0 as? WordBankError, .duplicateFolderName) }
        XCTAssertThrowsError(try store.createFolder(named: " ", in: nil)) { XCTAssertEqual($0 as? WordBankError, .blankName) }
        XCTAssertNoThrow(try store.createFolder(named: "Trip", in: trip.id), "same name under another parent")
        let other = try store.createFolder(named: "Other", in: nil)
        XCTAssertThrowsError(try store.rename(folder: other.id, to: "trip")) { XCTAssertEqual($0 as? WordBankError, .duplicateFolderName) }
        XCTAssertNoThrow(try store.rename(folder: trip.id, to: "TRIP"), "renaming itself")
        XCTAssertEqual(store.folders.first { $0.id == trip.id }?.name, "TRIP")
    }

    func testNewFoldersGoLastAmongSiblings() throws {
        let a = try store.createFolder(named: "A", in: nil)
        let b = try store.createFolder(named: "B", in: nil)
        XCTAssertLessThan(a.sortOrder, b.sortOrder)
    }

    func testMoveFolderRules() throws {
        let trip = try store.createFolder(named: "Trip", in: nil)
        let city = try store.createFolder(named: "City", in: trip.id)
        XCTAssertThrowsError(try store.move(folder: trip.id, to: city.id)) { XCTAssertEqual($0 as? WordBankError, .invalidMove) }
        _ = try store.createFolder(named: "City", in: nil)
        XCTAssertThrowsError(try store.move(folder: city.id, to: nil)) { XCTAssertEqual($0 as? WordBankError, .duplicateFolderName) }
        let other = try store.createFolder(named: "Other", in: nil)
        try store.move(folder: city.id, to: other.id)
        XCTAssertEqual(store.folders.first { $0.id == city.id }?.parentID, other.id)
    }

    func testDeleteKeepingContentsMovesThemUp() throws {
        let trip = try store.createFolder(named: "Trip", in: nil)
        let city = try store.createFolder(named: "City", in: trip.id)
        let inTrip = try store.save(WordBankEntryValue(text: "a", folderID: trip.id))
        let inCity = try store.save(WordBankEntryValue(text: "b", folderID: city.id))

        store.delete(folder: trip.id, .keepContents)

        XCTAssertEqual(store.folders.map(\.id), [city.id])
        XCTAssertNil(store.folders.first?.parentID)
        XCTAssertNil(store.entries.first { $0.id == inTrip.id }?.folderID)
        XCTAssertEqual(store.entries.first { $0.id == inCity.id }?.folderID, city.id)
        XCTAssertEqual(persisting.snapshot.folders.map(\.id), [city.id])
    }

    func testDeleteKeepingContentsRenamesAClashingSubfolder() throws {
        _ = try store.createFolder(named: "City", in: nil)
        let trip = try store.createFolder(named: "Trip", in: nil)
        let inner = try store.createFolder(named: "City", in: trip.id)
        store.delete(folder: trip.id, .keepContents)
        XCTAssertEqual(store.folders.first { $0.id == inner.id }?.name, "City (2)")
    }

    func testDeleteEverythingRemovesDescendantsAndTheirEntries() throws {
        let trip = try store.createFolder(named: "Trip", in: nil)
        let city = try store.createFolder(named: "City", in: trip.id)
        _ = try store.save(WordBankEntryValue(text: "a", folderID: trip.id))
        _ = try store.save(WordBankEntryValue(text: "b", folderID: city.id))
        let kept = try store.save(WordBankEntryValue(text: "c"))

        store.delete(folder: trip.id, .deleteContents)

        XCTAssertEqual(store.folders, [])
        XCTAssertEqual(store.entries.map(\.id), [kept.id])
        XCTAssertEqual(persisting.snapshot.entries.map(\.id), [kept.id])
    }

    // MARK: tags

    func testCreateDialectTagFromARecord() throws {
        let record = DialectCatalogue.bundled.dialects.first { $0.id == "hida-ben" }!
        let tag = try store.createDialectTag(from: record)
        XCTAssertEqual(tag.name, "飛騨弁")
        XCTAssertEqual(tag.romaji, "Hida-ben")
        XCTAssertEqual(tag.prefectures, [.gifu])
        XCTAssertEqual(tag.region, .chubu)
        XCTAssertEqual(tag.catalogueID, "hida-ben")
        XCTAssertThrowsError(try store.createDialectTag(from: record)) { XCTAssertEqual($0 as? WordBankError, .duplicateTagName) }
        XCTAssertThrowsError(try store.createDialectTag(DialectTagValue(name: "ひだべん", region: .chubu))) {
            XCTAssertEqual($0 as? WordBankError, .duplicateTagName)
        }
    }

    func testCustomTagDuplicatesAndBlanks() throws {
        _ = try store.createCustomTag(named: "Food", color: .orange)
        XCTAssertThrowsError(try store.createCustomTag(named: "food", color: .red)) { XCTAssertEqual($0 as? WordBankError, .duplicateTagName) }
        XCTAssertThrowsError(try store.createCustomTag(named: " ", color: .red)) { XCTAssertEqual($0 as? WordBankError, .blankName) }
    }

    func testUpdatingATagChecksOtherTagsOnly() throws {
        let food = try store.createCustomTag(named: "food", color: .orange)
        _ = try store.createCustomTag(named: "slang", color: .purple)
        var renamed = food
        renamed.name = "Slang"
        XCTAssertThrowsError(try store.update(customTag: renamed)) { XCTAssertEqual($0 as? WordBankError, .duplicateTagName) }
        renamed.name = "FOOD"
        renamed.color = .green
        try store.update(customTag: renamed)
        XCTAssertEqual(store.customTags.first { $0.id == food.id }, renamed)
    }

    func testDeletingATagRemovesItFromEntries() throws {
        let tag = try store.createCustomTag(named: "slang", color: .purple)
        let dialect = try store.createDialectTag(DialectTagValue(name: "大阪弁", region: .kansai))
        _ = try store.save(WordBankEntryValue(text: "めっちゃ", dialectTagIDs: [dialect.id], customTagIDs: [tag.id]))
        store.delete(customTag: tag.id)
        store.delete(dialectTag: dialect.id)
        XCTAssertEqual(store.entries.first?.customTagIDs, [])
        XCTAssertEqual(store.entries.first?.dialectTagIDs, [])
        XCTAssertEqual(store.customTags, [])
        XCTAssertEqual(store.dialectTags, [])
    }

    // MARK: lookups

    func testEntriesSharingAnEquivalent() throws {
        let ookini = try store.save(WordBankEntryValue(text: "おおきに", equivalents: [StandardEquivalent(written: "ありがとう")]))
        let dandan = try store.save(WordBankEntryValue(text: "だんだん", equivalents: [StandardEquivalent(written: "有難う", reading: "アリガトウ")]))
        _ = try store.save(WordBankEntryValue(text: "めんこい", equivalents: [StandardEquivalent(written: "可愛い")]))
        XCTAssertEqual(store.entries(sharingEquivalentWith: ookini).map(\.id), [dandan.id])
        XCTAssertEqual(store.entries(sharingEquivalentWith: dandan).map(\.id), [ookini.id])
    }

    func testEntryWithSameText() throws {
        let ookini = try store.save(WordBankEntryValue(text: "おおきに"))
        XCTAssertEqual(store.entryWithSameText(as: "オオキニ ", excluding: nil)?.id, ookini.id)
        XCTAssertNil(store.entryWithSameText(as: "おおきに", excluding: ookini.id))
        XCTAssertNil(store.entryWithSameText(as: "だんだん", excluding: nil))
    }

    // MARK: persistence failures

    func testAFailingPersisterKeepsMemoryAndSetsLastError() throws {
        persisting.failing = true
        let saved = try store.save(WordBankEntryValue(text: "おおきに"))
        XCTAssertEqual(store.entries, [saved])
        XCTAssertEqual(store.lastError, .saveFailed)
    }
}
