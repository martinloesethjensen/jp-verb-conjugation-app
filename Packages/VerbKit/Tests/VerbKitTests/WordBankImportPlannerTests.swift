import XCTest
@testable import VerbKit

final class WordBankImportPlannerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func plan(
        _ archive: WordBankArchive, into snapshot: WordBankSnapshot = WordBankSnapshot(),
        destination: ImportDestination = .root
    ) -> WordBankImportPlan {
        WordBankImportPlanner.plan(archive: archive, into: snapshot, destination: destination, now: now)
    }

    private func result(_ plan: WordBankImportPlan, from snapshot: WordBankSnapshot = WordBankSnapshot()) -> WordBankSnapshot {
        plan.changes.applied(to: snapshot)
    }

    private func decode(_ json: String) throws -> WordBankArchive { try WordBankArchive.decode(Data(json.utf8)) }

    func testPathsCreateFoldersAndNamesCreateTags() throws {
        let archive = try decode(#"{"entries":[{"text":"おおきに","folderPath":["Trip","Osaka"],"dialectTagNames":["大阪弁"],"customTagNames":["food"]}]}"#)
        let plan = plan(archive)
        let bank = result(plan)
        XCTAssertEqual(bank.entries.count, 1)
        let folder = bank.folders.first { $0.id == bank.entries[0].folderID }
        XCTAssertEqual(folder?.name, "Osaka")
        XCTAssertEqual(bank.folders.first { $0.id == folder?.parentID }?.name, "Trip")
        XCTAssertEqual(bank.dialectTags.map(\.name), ["大阪弁"])
        XCTAssertEqual(bank.dialectTags.first?.region, .kansai)       // filled in from the catalogue
        XCTAssertEqual(bank.customTags.map(\.name), ["food"])
        XCTAssertEqual(plan.summary.newEntries, 1)
        XCTAssertEqual(plan.summary.newFolders, [["Trip"], ["Trip", "Osaka"]])
        XCTAssertEqual(plan.summary.newDialectTags, ["大阪弁"])
    }

    func testUnknownDialectWithoutRegionBecomesACustomTag() throws {
        let archive = try decode(#"{"entries":[{"text":"x","dialectTagNames":["ほげ弁"]}]}"#)
        let plan = plan(archive)
        XCTAssertTrue(plan.changes.dialectTags.isEmpty)
        XCTAssertEqual(result(plan).customTags.map(\.name), ["ほげ弁"])
        XCTAssertEqual(plan.summary.newCustomTags, ["ほげ弁"])
        XCTAssertEqual(result(plan).entries[0].customTagIDs.count, 1)
    }

    func testDestinationFolderHoldsNewFoldersAndUnfiledEntries() throws {
        let dest = WordBankFolderValue(name: "Packs")
        let snapshot = WordBankSnapshot(folders: [dest])
        let archive = try decode(#"{"entries":[{"text":"a"},{"text":"b","folderPath":["Sub"]}]}"#)
        let bank = result(plan(archive, into: snapshot, destination: .folder(dest.id)), from: snapshot)
        let a = bank.entries.first { $0.text == "a" }!, b = bank.entries.first { $0.text == "b" }!
        XCTAssertEqual(a.folderID, dest.id)
        XCTAssertEqual(bank.folders.first { $0.id == b.folderID }?.parentID, dest.id)
    }

    func testRootDestinationLeavesUnfiledEntriesUnfiled() throws {
        let bank = result(plan(try decode(#"{"entries":[{"text":"a"}]}"#)))
        XCTAssertNil(bank.entries[0].folderID)
    }

    func testSiblingFolderMatchIgnoresCaseAndWidth() throws {
        let existing = WordBankFolderValue(name: "Trip ２０２６")
        let snapshot = WordBankSnapshot(folders: [existing])
        let archive = try decode(#"{"entries":[{"text":"a","folderPath":["trip 2026"]}]}"#)
        let plan = plan(archive, into: snapshot)
        XCTAssertTrue(plan.changes.folders.isEmpty)
        XCTAssertEqual(result(plan, from: snapshot).entries[0].folderID, existing.id)
    }

    func testMatchingByIdThenByTextAndReading() throws {
        let local = WordBankEntryValue(text: "おおきに", reading: "おおきに")
        let snapshot = WordBankSnapshot(entries: [local])
        let byReading = try decode(#"{"entries":[{"text":"オオキニ","reading":"おおきに","senses":[{"meaning":"thanks"}]}]}"#)
        let plan = plan(byReading, into: snapshot)
        XCTAssertEqual(plan.summary.newEntries, 0)
        XCTAssertEqual(plan.summary.combinedEntries, 1)
        XCTAssertEqual(result(plan, from: snapshot).entries.count, 1)
        let otherReading = try decode(#"{"entries":[{"text":"おおきに","reading":"おーきに"}]}"#)
        XCTAssertEqual(self.plan(otherReading, into: snapshot).summary.newEntries, 1)
        let byID = WordBankArchive(entries: [.init(id: local.id, text: "completely different")])
        XCTAssertEqual(self.plan(byID, into: snapshot).summary.newEntries, 0)
    }

    func testTextOnlyMatchesWhenExactlyOneLocalEntryHasThatText() throws {
        let one = WordBankEntryValue(text: "かける", reading: "かける")
        let two = WordBankEntryValue(text: "かける", reading: "かける2")
        let archive = try decode(#"{"entries":[{"text":"かける"}]}"#)
        XCTAssertEqual(plan(archive, into: WordBankSnapshot(entries: [one])).summary.newEntries, 0)
        XCTAssertEqual(plan(archive, into: WordBankSnapshot(entries: [one, two])).summary.newEntries, 1)
    }

    func testCombiningNeverOverwritesAndFillsGaps() throws {
        let local = WordBankEntryValue(text: "おおきに", reading: "おおきに", kanjiSpelling: "大", notes: "mine")
        let snapshot = WordBankSnapshot(entries: [local])
        let archive = try decode(#"{"entries":[{"text":"おおきに","reading":"おおきに","kanjiSpelling":"大きに","linkedWordID":"verb:x","notes":"theirs"}]}"#)
        let entry = result(plan(archive, into: snapshot), from: snapshot).entries[0]
        XCTAssertEqual(entry.kanjiSpelling, "大")
        XCTAssertEqual(entry.linkedWordID, "verb:x")
        XCTAssertTrue(entry.notes!.hasPrefix("mine"))
        XCTAssertTrue(entry.notes!.contains("theirs"))
    }

    func testImportingTheSameFileTwiceChangesNothing() throws {
        let archive = try decode(#"{"entries":[{"text":"おおきに","folderPath":["Trip"],"dialectTagNames":["大阪弁"],"customTagNames":["food"],"notes":"n","senses":[{"meaning":"thanks"}]}],"smartFolders":[{"name":"Kansai","dialectTagNames":["大阪弁"]}]}"#)
        let first = plan(archive)
        let bank = result(first)
        let second = plan(archive, into: bank)
        XCTAssertTrue(second.changes.isEmpty)
        XCTAssertFalse(second.summary.changesAnything)
        XCTAssertEqual(second.summary.unchangedEntries, 1)
    }

    func testRoundTripThroughExportReproducesTheBank() throws {
        let folder = WordBankFolderValue(name: "Trip"), child = WordBankFolderValue(name: "Osaka", parentID: folder.id)
        let tag = DialectTagValue(name: "大阪弁", prefectures: [.osaka], region: .kansai, catalogueID: "osaka")
        let custom = CustomTagValue(name: "food", color: .orange)
        let entry = WordBankEntryValue(
            text: "おおきに", reading: "おおきに", kind: .phrase, senses: [Sense(meaning: "thanks")],
            notes: "n", folderID: child.id, dialectTagIDs: [tag.id], customTagIDs: [custom.id],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000), updatedAt: Date(timeIntervalSince1970: 1_700_000_500)
        )
        let original = WordBankSnapshot(
            entries: [entry], folders: [folder, child], dialectTags: [tag], customTags: [custom],
            smartFolders: [WordBankSmartFolderValue(name: "Kansai", dialectTagIDs: [tag.id], match: .all)]
        )
        let data = try WordBankArchive(snapshot: original, scope: .everything, exportedAt: now).encoded()
        let rebuilt = result(plan(try WordBankArchive.decode(data)))
        XCTAssertEqual(rebuilt.entries, original.entries)
        XCTAssertEqual(rebuilt.folders.map { [$0.id, $0.parentID ?? UUID(uuid: UUID_NULL)] }, original.folders.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }.map { [$0.id, $0.parentID ?? UUID(uuid: UUID_NULL)] })
        XCTAssertEqual(rebuilt.dialectTags, original.dialectTags)
        XCTAssertEqual(rebuilt.customTags, original.customTags)
        XCTAssertEqual(rebuilt.smartFolders.map(\.name), ["Kansai"])
        XCTAssertEqual(rebuilt.smartFolders.first?.dialectTagIDs, [tag.id])
        XCTAssertEqual(rebuilt.smartFolders.first?.match, .all)
    }

    func testSkippedRecordsAreReportedInTheSummary() throws {
        let archive = try decode(#"{"entries":[{"text":"ok"},{"reading":"no text"}]}"#)
        XCTAssertEqual(plan(archive).summary.skipped.count, 1)
    }

    func testBlankFolderNameBecomesUntitled() {
        let archive = WordBankArchive(folders: [.init(name: "  ")], entries: [.init(text: "a")])
        XCTAssertEqual(result(plan(archive)).folders.map(\.name), ["Untitled"])
    }

    func testFolderCycleInTheFileDoesNotHang() {
        let a = UUID(), b = UUID()
        let archive = WordBankArchive(folders: [.init(id: a, name: "A", parentID: b), .init(id: b, name: "B", parentID: a)])
        XCTAssertEqual(result(plan(archive)).folders.count, 2)
    }

    func testFiveThousandEntriesPlanQuickly() {
        let local = (0..<5000).map { WordBankEntryValue(text: "word\($0)", reading: "reading\($0)") }
        let archive = WordBankArchive(entries: (0..<5000).map { .init(text: "word\($0)", reading: "reading\($0)") })
        let started = Date()
        let plan = plan(archive, into: WordBankSnapshot(entries: local))
        XCTAssertEqual(plan.summary.unchangedEntries, 5000)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }
}
