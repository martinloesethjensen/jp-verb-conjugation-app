import Observation

/// Owns the counters and their groups: loads the cached copy, then syncs a newer one. Like
/// `WordsStore`, every failure is silent; `counters` stays empty until data is available.
@MainActor
@Observable
public final class CountersStore {
    public private(set) var counters: [Counter] = []
    public private(set) var groups: [CounterGroup] = []
    /// The home list's headings: the file's `sections`, or one per group when it has none.
    public private(set) var sections: [CounterSection] = []

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
        sections = file.sections.isEmpty
            ? file.groups.map { CounterSection(id: $0.id, title: $0.title, counters: $0.members.map(\.counter)) }
            : file.sections
    }

    /// Persist first, then confirm, so a failed save is retried next time.
    private func sync() async {
        guard let fresh = await DataFileSync.run(
            for: .counters,
            status: syncStatus,
            fetch: {
                switch try await syncService.sync() {
                case .upToDate:
                    return nil
                case let .updated(manifest, counters):
                    return PendingDataFile(version: manifest.version, payload: counters) {
                        self.syncService.confirmSynced(manifest)
                    }
                }
            },
            persist: { try persisting.replaceCounters(with: $0) }
        ) else { return }
        apply(fresh)
    }
}
