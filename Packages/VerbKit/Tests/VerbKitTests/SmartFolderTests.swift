import XCTest
import SwiftData
@testable import VerbKit

final class SmartFolderMatchTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID()

    private func entry(dialect: [UUID] = [], custom: [UUID] = []) -> WordBankEntryValue {
        WordBankEntryValue(text: "x", dialectTagIDs: dialect, customTagIDs: custom)
    }

    func testAnyMatchesEntriesWithAtLeastOneTag() {
        let folder = WordBankSmartFolderValue(name: "Kansai & Hida", dialectTagIDs: [a, b], match: .any)
        XCTAssertTrue(folder.matches(entry(dialect: [a])))
        XCTAssertTrue(folder.matches(entry(dialect: [b, c])))
        XCTAssertFalse(folder.matches(entry(dialect: [c])))
        XCTAssertFalse(folder.matches(entry()))
    }

    func testAllNeedsEveryTagAcrossBothKinds() {
        let folder = WordBankSmartFolderValue(name: "Kansai food", dialectTagIDs: [a], customTagIDs: [b], match: .all)
        XCTAssertTrue(folder.matches(entry(dialect: [a], custom: [b])))
        XCTAssertTrue(folder.matches(entry(dialect: [a, c], custom: [b])))
        XCTAssertFalse(folder.matches(entry(dialect: [a])))
        XCTAssertFalse(folder.matches(entry(custom: [b])))
    }

    func testAnyWorksAcrossBothKinds() {
        let folder = WordBankSmartFolderValue(name: "Either", dialectTagIDs: [a], customTagIDs: [b], match: .any)
        XCTAssertTrue(folder.matches(entry(custom: [b])))
        XCTAssertTrue(folder.matches(entry(dialect: [a])))
    }

    func testAFolderWithNoTagsMatchesNothing() {
        for match in SmartFolderMatch.allCases {
            XCTAssertFalse(WordBankSmartFolderValue(name: "Empty", match: match).matches(entry(dialect: [a])))
        }
    }
}

@MainActor
final class SmartFolderPersistenceTests: XCTestCase {
    func testRoundTripAndDelete() throws {
        let context = ModelContext(try VerbModelContainer.makeInMemory())
        let persisting = SwiftDataWordBankPersisting(modelContext: context)
        let folder = WordBankSmartFolderValue(
            name: "Kansai", dialectTagIDs: [UUID(), UUID()], customTagIDs: [UUID()], match: .all, sortOrder: 3
        )
        try persisting.upsert(smartFolder: folder)
        XCTAssertEqual(try persisting.load().smartFolders, [folder])

        var renamed = folder
        renamed.name = "Kansai only"
        renamed.match = .any
        renamed.dialectTagIDs = []
        try persisting.upsert(smartFolder: renamed)
        XCTAssertEqual(try persisting.load().smartFolders, [renamed])

        try persisting.delete(smartFolderIDs: [folder.id])
        XCTAssertEqual(try persisting.load().smartFolders, [])
    }

    func testAnUnknownMatchRawFallsBackToAny() throws {
        let context = ModelContext(try VerbModelContainer.makeInMemory())
        let persisting = SwiftDataWordBankPersisting(modelContext: context)
        try persisting.upsert(smartFolder: WordBankSmartFolderValue(name: "x", customTagIDs: [UUID()], match: .all))
        try XCTUnwrap(try context.fetch(FetchDescriptor<WordBankSmartFolderEntity>()).first).matchRaw = "weird"
        try context.save()
        XCTAssertEqual(try persisting.load().smartFolders.first?.match, .any)
    }
}
