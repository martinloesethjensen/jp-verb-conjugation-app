import Observation

/// Owns the counters and their groups: loads the cached copy, then syncs a newer one. Like
/// `WordsStore`, every failure is silent; `counters` stays empty until data is available.
@MainActor
@Observable
public final class CountersStore {
    public private(set) var counters: [Counter] = []
    public private(set) var groups: [CounterGroup] = []

    private let syncService: CountersSyncService
    private let persisting: CountersPersisting
    private let syncStatus: DataSyncStatus?

    public init(syncService: CountersSyncService, persisting: CountersPersisting, syncStatus: DataSyncStatus? = nil) {
        self.syncService = syncService
        self.persisting = persisting
        self.syncStatus = syncStatus
    }

    public func start() async {
        if let cached = try? persisting.loadCounters() {
            apply(cached)
        }
        await sync()
    }

    /// Settings' Refresh data.
    public func refresh() async {
        await sync()
    }

    public func counter(id: String) -> Counter? {
        counters.first { $0.id == id }
    }

    public func group(id: String) -> CounterGroup? {
        groups.first { $0.id == id }
    }

    /// The counters `counter` lists as related, in its order. Unknown ids are skipped.
    public func related(to counter: Counter) -> [Counter] {
        counter.related.compactMap { self.counter(id: $0) }
    }

    private func apply(_ file: CountersDataFile) {
        counters = file.counters
        groups = file.groups
    }

    /// Persist first, then confirm, so a failed save is retried next time.
    private func sync() async {
        let result: CountersSyncResult
        do {
            result = try await syncService.sync()
        } catch {
            syncStatus?.recordFailure(.counters, error)
            return
        }
        guard case let .updated(manifest, fresh) = result else {
            syncStatus?.recordUpToDate(.counters)
            return
        }
        do {
            try persisting.replaceCounters(with: fresh)
        } catch {
            syncStatus?.recordFailure(.counters, error, whileSaving: true)
            return
        }
        syncService.confirmSynced(manifest)
        syncStatus?.recordUpdated(.counters, version: manifest.version)
        apply(fresh)
    }
}
