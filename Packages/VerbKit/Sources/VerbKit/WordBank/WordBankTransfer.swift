import Foundation

public enum WordBankTransferError: Error, Equatable, Sendable {
    case backupFailed
    case saveFailed
}

@MainActor
public final class WordBankTransfer {
    private let store: WordBankStore
    private let backups: WordBankBackupStore

    public init(store: WordBankStore, backups: WordBankBackupStore, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.backups = backups
    }

    public func plan(_ archive: WordBankArchive, destination: ImportDestination) -> WordBankImportPlan {
        WordBankImportPlanner.plan(archive: archive, into: store.snapshot, destination: destination)
    }

    public func perform(_ plan: WordBankImportPlan) throws {
        guard !plan.changes.isEmpty else { return }
        try backUpCurrentBank()
        try apply(plan.changes)
    }

    public func restore(_ backup: WordBankBackup) throws {
        let archive: WordBankArchive
        do { archive = try backups.archive(of: backup) } catch { throw WordBankTransferError.backupFailed }
        let target = WordBankImportPlanner.plan(archive: archive, into: WordBankSnapshot()).changes.applied(to: WordBankSnapshot())
        try backUpCurrentBank()
        try apply(WordBankChanges.replacing(store.snapshot, with: target))
    }

    private func backUpCurrentBank() throws {
        let snapshot = store.snapshot
        guard !(snapshot.entries.isEmpty && snapshot.folders.isEmpty && snapshot.dialectTags.isEmpty
            && snapshot.customTags.isEmpty && snapshot.smartFolders.isEmpty) else { return }
        do { try backups.backUp(snapshot) } catch { throw WordBankTransferError.backupFailed }
    }

    private func apply(_ changes: WordBankChanges) throws {
        do { try store.apply(changes) } catch { throw WordBankTransferError.saveFailed }
    }
}
