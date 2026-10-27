import Foundation

/// A fetched data file that has not been saved yet, plus the action that records its manifest
/// as synced. `DataFileSync` only calls that action after the save succeeds.
struct PendingDataFile<Payload> {
    let version: String
    let payload: Payload
    private let confirm: () -> Void

    init(version: String, payload: Payload, confirm: @escaping () -> Void) {
        self.version = version
        self.payload = payload
        self.confirm = confirm
    }

    func confirmSynced() {
        confirm()
    }
}

/// The persist-then-confirm flow shared by `WordsStore`, `FuriganaStore` and `CountersStore`.
///
/// The sync service downloads and verifies a file but records nothing. This runner saves the
/// payload first and only then confirms the manifest, so a failed save is retried on the next
/// launch instead of looking like "nothing changed". It also reports each outcome to
/// `DataSyncStatus`.
///
/// Each concrete store keeps its own sync service (they are deliberately separate files), and
/// its own observable properties; only this ordering lives here.
enum DataFileSync {
    /// Returns the payload to apply when a newer file was saved, or `nil` when the file was
    /// already current or the sync failed (the failure is recorded on `status`).
    @MainActor
    static func run<Payload>(
        for file: DataFile,
        status: DataSyncStatus?,
        fetch: () async throws -> PendingDataFile<Payload>?,
        persist: (Payload) throws -> Void
    ) async -> Payload? {
        let pending: PendingDataFile<Payload>
        do {
            guard let result = try await fetch() else {
                status?.recordUpToDate(file)
                return nil
            }
            pending = result
        } catch {
            status?.recordFailure(file, error)
            return nil
        }

        do {
            try persist(pending.payload)
        } catch {
            status?.recordFailure(file, error, whileSaving: true)
            return nil
        }

        pending.confirmSynced()
        status?.recordUpdated(file, version: pending.version)
        return pending.payload
    }
}
