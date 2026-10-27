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
        guard let fresh = await DataFileSync.run(
            for: .furigana,
            status: syncStatus,
            fetch: {
                switch try await syncService.sync() {
                case .upToDate:
                    return nil
                case let .updated(manifest, dictionary):
                    return PendingDataFile(version: manifest.version, payload: dictionary) {
                        self.syncService.confirmSynced(manifest)
                    }
                }
            },
            persist: { try persisting.replaceFuriganaDictionary(with: $0) }
        ) else { return }
        dictionary = fresh
    }
}
