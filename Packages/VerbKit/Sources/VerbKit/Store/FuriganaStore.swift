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
    private let bundled: BundledData<FuriganaDataFile>?

    public init(
        syncService: FuriganaSyncService, persisting: FuriganaPersisting, syncStatus: DataSyncStatus? = nil,
        bundled: BundledData<FuriganaDataFile>? = nil
    ) {
        self.syncService = syncService
        self.persisting = persisting
        self.syncStatus = syncStatus
        self.bundled = bundled
    }

    public func start() async {
        installBundled()
        if let cached = try? persisting.loadFuriganaDictionary() {
            dictionary = cached
        }
        await sync()
    }

    /// Installs the bundled copy as if it had been synced, when it is newer than anything this device has
    /// accepted. Persist first and record only after the save succeeded; a failure leaves the cache as it was.
    public func installBundled() {
        guard let bundled, DataVersion.isNewer(bundled.version, than: syncService.acceptedVersion()) else { return }
        do {
            try persisting.replaceFuriganaDictionary(with: FuriganaDictionary(file: bundled.value))
        } catch {
            return
        }
        syncService.confirmSynced(FuriganaManifest(version: bundled.version, sha256: bundled.sha256))
        syncStatus?.recordBundled(.furigana, version: bundled.version)
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
