import XCTest
@testable import VerbKit

final class WordBankExportTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)
    private var trip = WordBankFolderValue(name: "Trip 2026")
    private var takayama = WordBankFolderValue(name: "Takayama")
    private var other = WordBankFolderValue(name: "Other")
    private var hida = DialectTagValue(name: "飛騨弁", prefectures: [.gifu], region: .chubu)
    private var osaka = DialectTagValue(name: "大阪弁", prefectures: [.osaka], region: .kansai)
    private var food = CustomTagValue(name: "food", color: .orange)
    private var snapshot = WordBankSnapshot()

    override func setUp() {
        takayama.parentID = trip.id
        let inTakayama = WordBankEntryValue(text: "だちかん", folderID: takayama.id, dialectTagIDs: [hida.id], customTagIDs: [food.id], createdAt: date)
        let inOther = WordBankEntryValue(text: "おおきに", folderID: other.id, dialectTagIDs: [osaka.id], createdAt: date.addingTimeInterval(10))
        let loose = WordBankEntryValue(text: "めんこい", createdAt: date.addingTimeInterval(20))
        snapshot = WordBankSnapshot(
            entries: [inTakayama, inOther, loose], folders: [trip, takayama, other],
            dialectTags: [hida, osaka], customTags: [food, CustomTagValue(name: "unused")],
            smartFolders: [WordBankSmartFolderValue(name: "Kansai", dialectTagIDs: [osaka.id])]
        )
    }

    func testEverythingIncludesUnusedTagsFoldersAndSmartFolders() {
        let archive = WordBankArchive(snapshot: snapshot, scope: .everything, exportedAt: date)
        XCTAssertEqual(archive.entries.count, 3)
        XCTAssertEqual(archive.folders.count, 3)
        XCTAssertEqual(archive.dialectTags.count, 2)
        XCTAssertEqual(archive.customTags.map(\.name).sorted(), ["food", "unused"])
        XCTAssertEqual(archive.smartFolders, [.init(name: "Kansai", dialectTagNames: ["大阪弁"], customTagNames: [], match: .any)])
        let entry = archive.entries.first { $0.text == "だちかん" }!
        XCTAssertEqual(entry.folderPath, ["Trip 2026", "Takayama"])
        XCTAssertEqual(entry.dialectTagNames, ["飛騨弁"])
        XCTAssertEqual(entry.customTagNames, ["food"])
        XCTAssertEqual(entry.dialectTagIDs, [hida.id])
    }

    func testFolderScopeMakesThatFolderTheRootAndKeepsOnlyItsTags() {
        let archive = WordBankArchive(snapshot: snapshot, scope: .folder(takayama.id), exportedAt: date)
        XCTAssertEqual(archive.entries.map(\.text), ["だちかん"])
        XCTAssertEqual(archive.folders.map(\.name), ["Takayama"])
        XCTAssertNil(archive.folders[0].parentID)
        XCTAssertEqual(archive.entries[0].folderPath, ["Takayama"])
        XCTAssertEqual(archive.dialectTags.map(\.name), ["飛騨弁"])
        XCTAssertEqual(archive.customTags.map(\.name), ["food"])
        XCTAssertTrue(archive.smartFolders.isEmpty)
    }

    func testFolderScopeIncludesSubfolders() {
        let archive = WordBankArchive(snapshot: snapshot, scope: .folder(trip.id), exportedAt: date)
        XCTAssertEqual(Set(archive.folders.map(\.name)), ["Trip 2026", "Takayama"])
        XCTAssertEqual(archive.entries.first?.folderPath, ["Trip 2026", "Takayama"])
    }

    func testEntriesScopeKeepsPathsAndUsedTagsOnly() {
        let id = snapshot.entries.first { $0.text == "だちかん" }!.id
        let archive = WordBankArchive(snapshot: snapshot, scope: .entries([id]), exportedAt: date)
        XCTAssertEqual(archive.entries.count, 1)
        XCTAssertEqual(Set(archive.folders.map(\.name)), ["Trip 2026", "Takayama"])
        XCTAssertEqual(archive.dialectTags.map(\.name), ["飛騨弁"])
    }

    func testMissingFolderGivesAnEmptyArchive() {
        let archive = WordBankArchive(snapshot: snapshot, scope: .folder(UUID()), exportedAt: date)
        XCTAssertTrue(archive.entries.isEmpty)
        XCTAssertTrue(archive.folders.isEmpty)
    }

    func testEntriesAreSortedForStableOutput() {
        let archive = WordBankArchive(snapshot: snapshot, scope: .everything, exportedAt: date)
        XCTAssertEqual(archive.entries.map(\.text), ["だちかん", "おおきに", "めんこい"])
    }

    func testSuggestedFileNames() {
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 12))!
        XCTAssertEqual(WordBankArchive.suggestedFileName(for: .everything, in: snapshot, on: day), "Word Bank 2026-10-06")
        XCTAssertEqual(WordBankArchive.suggestedFileName(for: .folder(takayama.id), in: snapshot, on: day), "Takayama")
        XCTAssertEqual(WordBankArchive.suggestedFileName(for: .entries([]), in: snapshot, on: day), "Word Bank selection 2026-10-06")
    }

    func testFileNameDropsPathCharacters() {
        var odd = WordBankFolderValue(name: "a/b:c")
        odd.parentID = nil
        let snap = WordBankSnapshot(folders: [odd])
        XCTAssertEqual(WordBankArchive.suggestedFileName(for: .folder(odd.id), in: snap), "a-b-c")
    }
}
