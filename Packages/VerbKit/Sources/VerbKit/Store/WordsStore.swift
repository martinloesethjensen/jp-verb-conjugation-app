import Observation

/// Owns the adjective and noun list the grammar building blocks use: loads the cached
/// copy, then syncs a newer one. Like `FuriganaStore`, every failure is silent; `words`
/// stays empty until a list is available, and verbs come from `VerbStore` as before.
@MainActor
@Observable
public final class WordsStore {
    public private(set) var words: [Word] = []

    private let syncService: WordsSyncService
    private let persisting: WordsPersisting
    private let syncStatus: DataSyncStatus?
    private let bundled: BundledData<WordsDataFile>?

    public init(
        syncService: WordsSyncService, persisting: WordsPersisting, syncStatus: DataSyncStatus? = nil,
        bundled: BundledData<WordsDataFile>? = nil
    ) {
        self.syncService = syncService
        self.persisting = persisting
        self.syncStatus = syncStatus
        self.bundled = bundled
    }

    public func start() async {
        installBundled()
        if let cached = try? persisting.loadWords() {
            words = cached
        }
        await sync()
    }

    /// Installs the bundled copy as if it had been synced, when it is newer than anything this device has
    /// accepted. Persist first and record only after the save succeeded; a failure leaves the cache as it was.
    public func installBundled() {
        guard let bundled, DataVersion.isNewer(bundled.version, than: syncService.acceptedVersion()) else { return }
        do {
            try persisting.replaceWords(with: bundled.value.words)
        } catch {
            return
        }
        syncService.confirmSynced(WordsManifest(version: bundled.version, sha256: bundled.sha256))
        syncStatus?.recordBundled(.words, version: bundled.version)
    }

    /// Settings' Refresh data.
    public func refresh() async {
        await sync()
    }

    /// The words of one class, in file order.
    public func words(of wordClass: WordClass) -> [Word] {
        words.filter { $0.wordClass == wordClass }
    }

    /// Persist first, then confirm, so a failed save is retried next time.
    private func sync() async {
        guard let fresh = await DataFileSync.run(
            for: .words,
            status: syncStatus,
            fetch: {
                switch try await syncService.sync() {
                case .upToDate:
                    return nil
                case let .updated(manifest, words):
                    return PendingDataFile(version: manifest.version, payload: words) {
                        self.syncService.confirmSynced(manifest)
                    }
                }
            },
            persist: { try persisting.replaceWords(with: $0) }
        ) else { return }
        words = fresh
    }
}
