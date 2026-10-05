import XCTest
@testable import VerbKit

final class WordBankEntryCombinerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let early = Date(timeIntervalSince1970: 1_000_000_000)
    private let late = Date(timeIntervalSince1970: 1_500_000_000)

    private func combine(_ local: WordBankEntryValue, _ incoming: WordBankEntryValue, folder: UUID? = nil) -> WordBankEntryCombiner.Result {
        WordBankEntryCombiner.combine(local: local, incoming: incoming, importedFolderID: folder, importedOn: now, now: now)
    }

    func testFillsEmptyFieldsAndKeepsFilledOnes() {
        let local = WordBankEntryValue(text: "おおきに", kind: .phrase, createdAt: late)
        let incoming = WordBankEntryValue(text: "おおきに", reading: "おおきに", kanjiSpelling: "大きに", kind: .word, linkedWordID: "verb:x", createdAt: late)
        let result = combine(local, incoming)
        XCTAssertEqual(result.entry.reading, "おおきに")
        XCTAssertEqual(result.entry.kanjiSpelling, "大きに")
        XCTAssertEqual(result.entry.kind, .phrase)
        XCTAssertEqual(result.entry.linkedWordID, "verb:x")
        XCTAssertTrue(result.changed)
        XCTAssertEqual(result.entry.updatedAt, now)
    }

    func testFilledLocalFieldsAreNeverOverwritten() {
        let local = WordBankEntryValue(text: "a", reading: "あ", kanjiSpelling: "亜", createdAt: late)
        let incoming = WordBankEntryValue(text: "a", reading: "い", kanjiSpelling: "伊", createdAt: late)
        let result = combine(local, incoming)
        XCTAssertEqual(result.entry.reading, "あ")
        XCTAssertEqual(result.entry.kanjiSpelling, "亜")
        XCTAssertFalse(result.changed)
    }

    func testSensesAndEquivalentsAreUnionedWithoutDuplicates() {
        let local = WordBankEntryValue(
            text: "a", senses: [Sense(meaning: "Thank you")], equivalents: [StandardEquivalent(written: "ありがとう")], createdAt: late
        )
        let incoming = WordBankEntryValue(
            text: "a", senses: [Sense(meaning: "thank you"), Sense(meaning: "cheers")],
            equivalents: [StandardEquivalent(written: "アリガトウ"), StandardEquivalent(written: "どうも")], createdAt: late
        )
        let result = combine(local, incoming)
        XCTAssertEqual(result.entry.senses.map(\.meaning), ["Thank you", "cheers"])
        XCTAssertEqual(result.entry.equivalents.map(\.written), ["ありがとう", "どうも"])
    }

    func testTagsAreUnioned() {
        let a = UUID(), b = UUID(), c = UUID()
        let local = WordBankEntryValue(text: "x", dialectTagIDs: [a], customTagIDs: [c], createdAt: late)
        let incoming = WordBankEntryValue(text: "x", dialectTagIDs: [a, b], customTagIDs: [c], createdAt: late)
        let result = combine(local, incoming)
        XCTAssertEqual(result.entry.dialectTagIDs, [a, b])
        XCTAssertEqual(result.entry.customTagIDs, [c])
    }

    func testNotesAreAppendedOnceUnderAnImportedHeading() {
        let local = WordBankEntryValue(text: "x", notes: "Heard at the izakaya", createdAt: late)
        let incoming = WordBankEntryValue(text: "x", notes: "From Yuki", createdAt: late)
        let once = combine(local, incoming).entry
        XCTAssertTrue(once.notes!.hasPrefix("Heard at the izakaya\n\nImported "))
        XCTAssertTrue(once.notes!.hasSuffix(": From Yuki"))
        XCTAssertFalse(combine(once, incoming).changed)
    }

    func testNotesAlreadyContainedAreNotAppendedAndEmptyNotesAreFilledPlainly() {
        let local = WordBankEntryValue(text: "x", notes: "Heard at the izakaya in Osaka", createdAt: late)
        XCTAssertFalse(combine(local, WordBankEntryValue(text: "x", notes: "izakaya", createdAt: late)).changed)
        let empty = WordBankEntryValue(text: "x", createdAt: late)
        XCTAssertEqual(combine(empty, WordBankEntryValue(text: "x", notes: "From Yuki", createdAt: late)).entry.notes, "From Yuki")
    }

    func testUnfiledEntryMovesToImportedFolderButFiledOneStays() {
        let target = UUID(), kept = UUID()
        let unfiled = WordBankEntryValue(text: "x", createdAt: late)
        XCTAssertEqual(combine(unfiled, unfiled, folder: target).entry.folderID, target)
        let filed = WordBankEntryValue(text: "x", folderID: kept, createdAt: late)
        XCTAssertEqual(combine(filed, unfiled, folder: target).entry.folderID, kept)
    }

    func testCreatedAtBecomesTheEarlierAndAloneDoesNotCountAsAChange() {
        let local = WordBankEntryValue(text: "x", createdAt: late, updatedAt: late)
        let incoming = WordBankEntryValue(text: "x", createdAt: early)
        let result = combine(local, incoming)
        XCTAssertEqual(result.entry.createdAt, early)
        XCTAssertEqual(result.entry.updatedAt, late)
        XCTAssertFalse(result.changed)
    }

    func testTrimmedCleansTextFields() {
        let entry = WordBankEntryValue(
            text: "  おおきに \n", reading: "  ", kanjiSpelling: " 大 ", kind: .phrase, wordClass: .noun,
            senses: [Sense(meaning: "  "), Sense(meaning: " thanks ", note: " ")],
            equivalents: [StandardEquivalent(written: " ありがとう ", reading: "")], notes: "\n"
        ).trimmed()
        XCTAssertEqual(entry.text, "おおきに")
        XCTAssertNil(entry.reading)
        XCTAssertEqual(entry.kanjiSpelling, "大")
        XCTAssertNil(entry.wordClass)
        XCTAssertEqual(entry.senses, [Sense(meaning: "thanks", note: nil)])
        XCTAssertEqual(entry.equivalents, [StandardEquivalent(written: "ありがとう")])
        XCTAssertNil(entry.notes)
    }
}
