import Observation

/// Owns the furigana dictionary: loads the cached copy, then syncs a newer one
/// in the background. Separate from `VerbStore` on purpose: furigana is an
/// enhancement, so nothing here can affect the verb list or first launch, and
/// every failure is silent (only reported to `syncStatus`). `dictionary` stays
/// `nil` until one is available, which the app treats as "show no furigana".
@MainActor
@Observable
public final class FuriganaStore {
    public private(set) var dictionary: FuriganaDictionary?

    private let syncService: FuriganaSyncService
    private let persisting: FuriganaPersisting
    private let syncStatus: DataSyncStatus?

    public init(syncService: FuriganaSyncService, persisting: FuriganaPersisting, syncStatus: DataSyncStatus? = nil) {
        self.syncService = syncService
        self.persisting = persisting
        self.syncStatus = syncStatus
    }

    public func start() async {
        if let cached = try? persisting.loadFuriganaDictionary() {
            dictionary = cached
        }
        await sync()
    }

    /// Settings' Refresh data.
    public func refresh() async {
        await sync()
    }

    /// Same contract as the verb and grammar syncs: persist first, and only
    /// then confirm the manifest, so a persistence failure leaves it
    /// unrecorded and the next attempt genuinely retries.
    private func sync() async {
        let result: FuriganaSyncResult
        do {
            result = try await syncService.sync()
        } catch {
            syncStatus?.recordFailure(.furigana, error)
            return
        }
        guard case let .updated(manifest, fresh) = result else {
            syncStatus?.recordUpToDate(.furigana)
            return
        }
        do {
            try persisting.replaceFuriganaDictionary(with: fresh)
        } catch {
            syncStatus?.recordFailure(.furigana, error, whileSaving: true)
            return
        }
        syncService.confirmSynced(manifest)
        syncStatus?.recordUpdated(.furigana, version: manifest.version)
        dictionary = fresh
    }
}
