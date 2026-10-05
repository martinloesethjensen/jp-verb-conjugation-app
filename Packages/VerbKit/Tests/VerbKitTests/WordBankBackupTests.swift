import XCTest
@testable import VerbKit

@MainActor
final class WordBankBackupTests: XCTestCase {
    private var directory: URL!
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("wb-backups-\(UUID().uuidString)")
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    private func backupStore(keeping: Int = 3) -> WordBankBackupStore {
        WordBankBackupStore(directory: directory, keeping: keeping, now: { [unowned self] in self.clock })
    }
    private func tick() { clock = clock.addingTimeInterval(61) }

    func testBackUpWritesAReadableArchive() throws {
        let store = backupStore()
        let entry = WordBankEntryValue(text: "おおきに")
        let backup = try store.backUp(WordBankSnapshot(entries: [entry]))
        XCTAssertTrue(backup.id.hasSuffix(".wordbank"))
        XCTAssertEqual(try store.archive(of: backup).entries.map(\.text), ["おおきに"])
    }

    func testOnlyTheNewestThreeAreKeptAndListedNewestFirst() throws {
        let store = backupStore()
        var names: [String] = []
        for number in 1...5 {
            names.append(try store.backUp(WordBankSnapshot(entries: [WordBankEntryValue(text: "e\(number)")])).id)
            tick()
        }
        XCTAssertEqual(store.backups().map(\.id), Array(names.suffix(3).reversed()))
    }

    func testSameSecondBackupsDoNotOverwrite() throws {
        let store = backupStore()
        let first = try store.backUp(WordBankSnapshot()), second = try store.backUp(WordBankSnapshot())
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(store.backups().count, 2)
    }

    func testBackupsOfAMissingDirectoryIsEmpty() {
        XCTAssertTrue(backupStore().backups().isEmpty)
    }

    // MARK: Transfer

    private final class Persister: WordBankPersisting {
        var snapshot = WordBankSnapshot()
        var failing = false
        func load() throws -> WordBankSnapshot { snapshot }
        func apply(_ changes: WordBankChanges) throws {
            if failing { throw NSError(domain: "t", code: 1) }
            snapshot = changes.applied(to: snapshot)
        }
        func upsert(entry: WordBankEntryValue) throws { snapshot = { var c = WordBankChanges(); c.entries = [entry]; return c.applied(to: snapshot) }() }
        func delete(entryIDs: [UUID]) throws {}
        func upsert(folder: WordBankFolderValue) throws {}
        func delete(folderIDs: [UUID]) throws {}
        func upsert(dialectTag: DialectTagValue) throws {}
        func upsert(customTag: CustomTagValue) throws {}
        func delete(dialectTagIDs: [UUID], customTagIDs: [UUID]) throws {}
        func upsert(smartFolder: WordBankSmartFolderValue) throws {}
        func delete(smartFolderIDs: [UUID]) throws {}
    }

    private func transfer(bank: [WordBankEntryValue] = []) -> (WordBankTransfer, WordBankStore, Persister, WordBankBackupStore) {
        let persister = Persister()
        persister.snapshot = WordBankSnapshot(entries: bank)
        let store = WordBankStore(persisting: persister, now: { [unowned self] in self.clock })
        let backups = backupStore()
        return (WordBankTransfer(store: store, backups: backups, now: { [unowned self] in self.clock }), store, persister, backups)
    }

    func testImportBacksUpTheOldBankFirstThenApplies() throws {
        let old = WordBankEntryValue(text: "old")
        let (transfer, store, _, backups) = transfer(bank: [old])
        let archive = WordBankArchive(entries: [.init(text: "new")])
        try transfer.perform(transfer.plan(archive, destination: .root))
        XCTAssertEqual(Set(store.entries.map(\.text)), ["old", "new"])
        let saved = try backups.archive(of: backups.backups()[0])
        XCTAssertEqual(saved.entries.map(\.text), ["old"])
    }

    func testEmptyBankIsNotBackedUp() throws {
        let (transfer, _, _, backups) = transfer()
        try transfer.perform(transfer.plan(WordBankArchive(entries: [.init(text: "new")]), destination: .root))
        XCTAssertTrue(backups.backups().isEmpty)
    }

    func testNothingToDoMakesNoBackupAndNoWrite() throws {
        let entry = WordBankEntryValue(text: "same")
        let (transfer, _, _, backups) = transfer(bank: [entry])
        let archive = WordBankArchive(entries: [.init(id: entry.id, text: "same")])
        try transfer.perform(transfer.plan(archive, destination: .root))
        XCTAssertTrue(backups.backups().isEmpty)
    }

    func testFailedSaveThrowsAndLeavesTheBankAlone() {
        let (transfer, store, persister, _) = transfer(bank: [WordBankEntryValue(text: "old")])
        persister.failing = true
        XCTAssertThrowsError(try transfer.perform(transfer.plan(WordBankArchive(entries: [.init(text: "new")]), destination: .root))) {
            XCTAssertEqual($0 as? WordBankTransferError, .saveFailed)
        }
        XCTAssertEqual(store.entries.map(\.text), ["old"])
    }

    func testRestoreReplacesTheBankAndBacksUpTheCurrentOneFirst() throws {
        let original = WordBankEntryValue(text: "original")
        let (transfer, store, persister, backups) = transfer(bank: [original])
        let wanted = try backups.backUp(persister.snapshot)
        tick()
        try store.save(WordBankEntryValue(text: "added later"))
        tick()
        try transfer.restore(wanted)
        XCTAssertEqual(store.entries.map(\.text), ["original"])
        let newest = try backups.archive(of: backups.backups()[0])
        XCTAssertEqual(Set(newest.entries.map(\.text)), ["original", "added later"])
    }
}
