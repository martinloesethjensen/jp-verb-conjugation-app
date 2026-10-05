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
        func upsert(smartFolder: WordBankSmartFolderValue) throws {
            try write()
            snapshot.smartFolders.removeAll { $0.id == smartFolder.id }
            snapshot.smartFolders.append(smartFolder)
        }
        func delete(smartFolderIDs: [UUID]) throws { try write(); snapshot.smartFolders.removeAll { smartFolderIDs.contains($0.id) } }
        func apply(_ changes: WordBankChanges) throws {
            try write()
            snapshot = changes.applied(to: snapshot)
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

    // MARK: smart folders

    func testSmartFolderCreateRenameAndDuplicateNames() throws {
        let kansai = try store.createDialectTag(DialectTagValue(name: "関西弁", region: .kansai))
        let food = try store.createCustomTag(named: "food", color: .orange)
        let folder = try store.createSmartFolder(named: "  Kansai food ", dialectTagIDs: [kansai.id], customTagIDs: [food.id], match: .all)
        XCTAssertEqual(folder.name, "Kansai food")
        XCTAssertEqual(persisting.snapshot.smartFolders, [folder])
        XCTAssertThrowsError(try store.createSmartFolder(named: "kansai FOOD", dialectTagIDs: [kansai.id], customTagIDs: [], match: .any)) {
            XCTAssertEqual($0 as? WordBankError, .duplicateFolderName)
        }
        XCTAssertThrowsError(try store.createSmartFolder(named: " ", dialectTagIDs: [kansai.id], customTagIDs: [], match: .any)) {
            XCTAssertEqual($0 as? WordBankError, .blankName)
        }
        var edited = folder
        edited.name = "Kansai"
        edited.match = .any
        try store.update(smartFolder: edited)
        XCTAssertEqual(store.smartFolders, [edited])
    }

    func testSmartFolderIgnoresUnknownTagsAndNewOnesGoLast() throws {
        let tag = try store.createCustomTag(named: "slang", color: .purple)
        let a = try store.createSmartFolder(named: "A", dialectTagIDs: [UUID()], customTagIDs: [tag.id], match: .any)
        let b = try store.createSmartFolder(named: "B", dialectTagIDs: [], customTagIDs: [tag.id], match: .any)
        XCTAssertEqual(a.dialectTagIDs, [])
        XCTAssertLessThan(a.sortOrder, b.sortOrder)
    }

    func testEntriesInASmartFolder() throws {
        let kansai = try store.createDialectTag(DialectTagValue(name: "関西弁", region: .kansai))
        let hida = try store.createDialectTag(DialectTagValue(name: "飛騨弁", region: .chubu))
        let first = try store.save(WordBankEntryValue(text: "おおきに", dialectTagIDs: [kansai.id]))
        _ = try store.save(WordBankEntryValue(text: "だんだん"))
        let third = try store.save(WordBankEntryValue(text: "あんな", dialectTagIDs: [hida.id]))
        let folder = try store.createSmartFolder(named: "Both", dialectTagIDs: [kansai.id, hida.id], customTagIDs: [], match: .any)
        XCTAssertEqual(Set(store.entries(in: folder).map(\.id)), [first.id, third.id])
    }

    func testDeletingATagTakesItOutOfSmartFolders() throws {
        let a = try store.createCustomTag(named: "a", color: .red)
        let b = try store.createCustomTag(named: "b", color: .blue)
        let folder = try store.createSmartFolder(named: "AB", dialectTagIDs: [], customTagIDs: [a.id, b.id], match: .all)
        store.delete(customTag: a.id)
        XCTAssertEqual(store.smartFolders.first?.customTagIDs, [b.id])
        XCTAssertEqual(persisting.snapshot.smartFolders.first?.customTagIDs, [b.id])
        XCTAssertEqual(store.smartFolders.first?.id, folder.id)
    }

    func testDeleteASmartFolderKeepsEntries() throws {
        let tag = try store.createCustomTag(named: "a", color: .red)
        _ = try store.save(WordBankEntryValue(text: "x", customTagIDs: [tag.id]))
        let folder = try store.createSmartFolder(named: "A", dialectTagIDs: [], customTagIDs: [tag.id], match: .any)
        store.delete(smartFolder: folder.id)
        XCTAssertEqual(store.smartFolders, [])
        XCTAssertEqual(persisting.snapshot.smartFolders, [])
        XCTAssertEqual(store.entries.count, 1)
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

    // MARK: search index

    func testTheSearchIndexFollowsTheBank() throws {
        XCTAssertEqual(store.searchIndex().search(WordBankQuery(text: "ookini")).count, 0)
        let saved = try store.save(WordBankEntryValue(text: "おおきに"))
        XCTAssertEqual(store.searchIndex().search(WordBankQuery(text: "ookini")).map(\.entry.id), [saved.id])

        var edited = saved
        edited.text = "ありがとう"
        try store.save(edited)
        XCTAssertEqual(store.searchIndex().search(WordBankQuery(text: "ookini")).count, 0)

        let tag = try store.createCustomTag(named: "food", color: .orange)
        XCTAssertEqual(store.searchIndex().suggestedTokens(for: "foo", excluding: []).count, 0, "no entry has it yet")
        edited.customTagIDs = [tag.id]
        try store.save(edited)
        XCTAssertEqual(store.searchIndex().suggestedTokens(for: "foo", excluding: []), [.customTag(tag.id)])

        store.delete(entryIDs: [saved.id])
        XCTAssertEqual(store.searchIndex().search(WordBankQuery(text: "ありがとう")).count, 0)
    }

    func testTheSearchIndexIsReusedUntilSomethingChanges() throws {
        try store.save(WordBankEntryValue(text: "おおきに"))
        let first = store.searchIndexRevision
        _ = store.searchIndex()
        _ = store.searchIndex()
        XCTAssertEqual(store.searchIndexBuilds, 1)
        XCTAssertEqual(store.searchIndexRevision, first)
        try store.save(WordBankEntryValue(text: "だんだん"))
        _ = store.searchIndex()
        XCTAssertEqual(store.searchIndexBuilds, 2)
    }

    func testADifferentReadingFunctionRebuildsTheIndex() throws {
        try store.save(WordBankEntryValue(text: "頭"))
        XCTAssertEqual(store.searchIndex().search(WordBankQuery(text: "atama")).count, 0)
        let derived = store.searchIndex(readingKey: 1) { $0 == "頭" ? "あたま" : nil }
        XCTAssertEqual(derived.search(WordBankQuery(text: "atama")).count, 1)
        XCTAssertEqual(store.searchIndex(readingKey: 1) { _ in nil }.search(WordBankQuery(text: "atama")).count, 1, "same key reuses the cache")
    }

    // MARK: persistence failures

    func testAFailingPersisterKeepsMemoryAndSetsLastError() throws {
        persisting.failing = true
        let saved = try store.save(WordBankEntryValue(text: "おおきに"))
        XCTAssertEqual(store.entries, [saved])
        XCTAssertEqual(store.lastError, .saveFailed)
    }

    func testApplyUpdatesMemoryAfterAGoodWrite() throws {
        var changes = WordBankChanges()
        changes.entries = [WordBankEntryValue(text: "a")]
        try store.apply(changes)
        XCTAssertEqual(store.entries.map(\.text), ["a"])
        XCTAssertEqual(persisting.snapshot.entries.count, 1)
    }

    func testFailedApplyThrowsAndLeavesMemoryUntouched() {
        persisting.failing = true
        var changes = WordBankChanges()
        changes.entries = [WordBankEntryValue(text: "a")]
        XCTAssertThrowsError(try store.apply(changes)) { XCTAssertEqual($0 as? WordBankError, .saveFailed) }
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(store.lastError, .saveFailed)
    }
}
