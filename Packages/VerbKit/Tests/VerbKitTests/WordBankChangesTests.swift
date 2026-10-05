import XCTest
@testable import VerbKit

final class WordBankChangesTests: XCTestCase {
    func testAppliedUpsertsReplacesAndDeletes() {
        let keep = WordBankEntryValue(text: "keep"), drop = WordBankEntryValue(text: "drop")
        var edited = keep
        edited.reading = "きーぷ"
        let added = WordBankEntryValue(text: "new")
        var changes = WordBankChanges()
        changes.entries = [edited, added]
        changes.deletedEntryIDs = [drop.id]
        let result = changes.applied(to: WordBankSnapshot(entries: [keep, drop]))
        XCTAssertEqual(Set(result.entries.map(\.text)), ["keep", "new"])
        XCTAssertEqual(result.entries.first { $0.id == keep.id }?.reading, "きーぷ")
    }

    func testIsEmpty() {
        XCTAssertTrue(WordBankChanges().isEmpty)
        var changes = WordBankChanges()
        changes.deletedFolderIDs = [UUID()]
        XCTAssertFalse(changes.isEmpty)
    }

    func testReplacingTurnsOneBankIntoAnother() {
        let folder = WordBankFolderValue(name: "Old")
        let oldEntry = WordBankEntryValue(text: "old", folderID: folder.id)
        let tag = DialectTagValue(name: "大阪弁", region: .kansai)
        let current = WordBankSnapshot(entries: [oldEntry], folders: [folder], dialectTags: [tag])
        let newEntry = WordBankEntryValue(text: "new")
        let replacement = WordBankSnapshot(entries: [newEntry])
        let changes = WordBankChanges.replacing(current, with: replacement)
        XCTAssertEqual(changes.deletedEntryIDs, [oldEntry.id])
        XCTAssertEqual(changes.deletedFolderIDs, [folder.id])
        XCTAssertEqual(changes.deletedDialectTagIDs, [tag.id])
        XCTAssertEqual(changes.entries, [newEntry])
        XCTAssertEqual(changes.applied(to: current), replacement)
    }

    func testReplacingWithTheSameBankIsEmpty() {
        let snap = WordBankSnapshot(entries: [WordBankEntryValue(text: "a")], folders: [WordBankFolderValue(name: "f")])
        XCTAssertTrue(WordBankChanges.replacing(snap, with: snap).isEmpty)
    }
}
