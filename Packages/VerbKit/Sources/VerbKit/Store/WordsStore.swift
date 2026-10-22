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

    public init(syncService: WordsSyncService, persisting: WordsPersisting, syncStatus: DataSyncStatus? = nil) {
        self.syncService = syncService
        self.persisting = persisting
        self.syncStatus = syncStatus
    }

    public func start() async {
        if let cached = try? persisting.loadWords() {
            words = cached
        }
        await sync()
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
        let result: WordsSyncResult
        do {
            result = try await syncService.sync()
        } catch {
            syncStatus?.recordFailure(.words, error)
            return
        }
        guard case let .updated(manifest, fresh) = result else {
            syncStatus?.recordUpToDate(.words)
            return
        }
        do {
            try persisting.replaceWords(with: fresh)
        } catch {
            syncStatus?.recordFailure(.words, error, whileSaving: true)
            return
        }
        syncService.confirmSynced(manifest)
        syncStatus?.recordUpdated(.words, version: manifest.version)
        words = fresh
    }
}
