import XCTest
@testable import VerbKit

final class WordBankArchiveTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    func testRoundTripKeepsEverything() throws {
        let folderID = UUID(), tagID = UUID(), entryID = UUID()
        let archive = WordBankArchive(
            exportedAt: date,
            folders: [.init(id: folderID, name: "Trip 2026", parentID: nil)],
            dialectTags: [.init(id: tagID, name: "大阪弁", romaji: "Osaka-ben", prefectures: [.osaka], region: .kansai, catalogueID: "osaka")],
            customTags: [.init(id: UUID(), name: "food", color: .orange)],
            smartFolders: [.init(name: "Kansai", dialectTagNames: ["大阪弁"], customTagNames: [], match: .any)],
            entries: [
                .init(
                    id: entryID, text: "おおきに", reading: "おおきに", kind: .phrase,
                    senses: [Sense(meaning: "thank you", note: "informal")],
                    equivalents: [StandardEquivalent(written: "ありがとう")],
                    notes: "Heard in Osaka", folderID: folderID, folderPath: ["Trip 2026"],
                    dialectTagIDs: [tagID], dialectTagNames: ["大阪弁"], createdAt: date, updatedAt: date
                )
            ]
        )
        let decoded = try WordBankArchive.decode(try archive.encoded())
        XCTAssertEqual(decoded, archive)
    }

    func testHandWrittenFileWithOnlyTextAndPathsDecodes() throws {
        let json = #"{"entries":[{"text":"おおきに","folderPath":["Trip","Osaka"],"dialectTagNames":["大阪弁"]}]}"#
        let archive = try WordBankArchive.decode(Data(json.utf8))
        XCTAssertEqual(archive.entries.count, 1)
        XCTAssertEqual(archive.entries[0].folderPath, ["Trip", "Osaka"])
        XCTAssertEqual(archive.entries[0].kind, .word)
        XCTAssertNil(archive.entries[0].id)
        XCTAssertTrue(archive.folders.isEmpty)
        XCTAssertTrue(archive.skipped.isEmpty)
    }

    func testUnknownFieldsAndEnumValuesAreTolerated() throws {
        let json = #"{"format":"word-bank","version":1,"future":true,"entries":[{"text":"x","kind":"haiku","wordClass":"adverb","surprise":1}]}"#
        let archive = try WordBankArchive.decode(Data(json.utf8))
        XCTAssertEqual(archive.entries[0].kind, .word)
        XCTAssertNil(archive.entries[0].wordClass)
    }

    func testBadRecordsAreSkippedWithReasons() throws {
        let json = #"{"entries":[{"text":"ok"},{"reading":"no text"},{"text":"   "}]}"#
        let archive = try WordBankArchive.decode(Data(json.utf8))
        XCTAssertEqual(archive.entries.map(\.text), ["ok"])
        XCTAssertEqual(archive.skipped.map(\.position), [2, 3])
        XCTAssertEqual(archive.skipped.map(\.section), ["entries", "entries"])
        XCTAssertFalse(archive.skipped[0].reason.isEmpty)
    }

    func testNewerVersionIsRefused() {
        let json = #"{"format":"word-bank","version":2,"entries":[]}"#
        XCTAssertThrowsError(try WordBankArchive.decode(Data(json.utf8))) {
            XCTAssertEqual($0 as? WordBankArchive.ArchiveError, .newerVersion(2))
        }
    }

    func testOtherFormatsAndGarbageAreRefused() {
        for json in [#"{"format":"something-else","entries":[]}"#, "not json", "[]", #"{"hello":1}"#] {
            XCTAssertThrowsError(try WordBankArchive.decode(Data(json.utf8)), json) {
                XCTAssertEqual($0 as? WordBankArchive.ArchiveError, .notAWordBank)
            }
        }
    }

    func testOversizedFileIsRefused() {
        XCTAssertThrowsError(try WordBankArchive.decode(Data(count: WordBankArchive.maxBytes + 1))) {
            XCTAssertEqual($0 as? WordBankArchive.ArchiveError, .tooLarge)
        }
    }

    func testReadingAnOversizedFileStopsAtTheLimit() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wordbank")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(count: WordBankArchive.maxBytes + 1).write(to: url)
        XCTAssertThrowsError(try WordBankArchive.read(contentsOf: url)) {
            XCTAssertEqual($0 as? WordBankArchive.ArchiveError, .tooLarge)
        }
    }

    func testReadingAFileDecodesIt() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wordbank")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"entries":[{"text":"おおきに"}]}"#.utf8).write(to: url)
        XCTAssertEqual(try WordBankArchive.read(contentsOf: url).entries.map(\.text), ["おおきに"])
    }

    func testTooManyRecordsIsRefused() {
        let entries = Array(repeating: #"{"text":"x"}"#, count: WordBankArchive.maxRecords + 1).joined(separator: ",")
        XCTAssertThrowsError(try WordBankArchive.decode(Data(#"{"entries":[\#(entries)]}"#.utf8))) {
            XCTAssertEqual($0 as? WordBankArchive.ArchiveError, .tooManyRecords)
        }
    }

    func testEntryWithOverlongFieldIsSkipped() throws {
        let long = String(repeating: "あ", count: WordBankArchive.maxFieldLength + 1)
        let json = #"{"entries":[{"text":"ok"},{"text":"x","notes":"\#(long)"}]}"#
        let archive = try WordBankArchive.decode(Data(json.utf8))
        XCTAssertEqual(archive.entries.map(\.text), ["ok"])
        XCTAssertEqual(archive.skipped.map(\.reason), ["Text too long"])
    }

    func testEncodedFileStartsWithHeader() throws {
        let text = String(decoding: try WordBankArchive(exportedAt: date).encoded(), as: UTF8.self)
        XCTAssertTrue(text.contains(#""format" : "word-bank""#))
        XCTAssertTrue(text.contains(#""version" : 1"#))
    }
}
