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

    public init(syncService: CountersSyncService, persisting: CountersPersisting) {
        self.syncService = syncService
        self.persisting = persisting
    }

    public func start() async {
        if let cached = try? persisting.loadCounters() {
            apply(cached)
        }
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
        guard let result = try? await syncService.sync() else { return }
        guard case let .updated(manifest, fresh) = result else { return }
        do {
            try persisting.replaceCounters(with: fresh)
        } catch {
            return
        }
        syncService.confirmSynced(manifest)
        apply(fresh)
    }
}
