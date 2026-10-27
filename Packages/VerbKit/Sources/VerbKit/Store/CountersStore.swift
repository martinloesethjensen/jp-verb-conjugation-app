import Observation

/// Owns the counters and their groups: starts on the bundled copy, loads the cached copy when it is
/// not older, then syncs a newer one. Like `WordsStore`, every failure is silent; `counters` stays
/// empty only when there is neither a bundled copy nor synced data.
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
    private let bundled: BundledCounters?

    /// - Parameter bundled: the copy shipped in the app (`BundledCounters.load()`), used until a synced
    ///   copy that is not older than it is available, so a first launch works offline.
    public init(
        syncService: CountersSyncService, persisting: CountersPersisting, syncStatus: DataSyncStatus? = nil,
        bundled: BundledCounters? = nil
    ) {
        self.syncService = syncService
        self.persisting = persisting
        self.syncStatus = syncStatus
        self.bundled = bundled
    }

    /// Starts on the bundled copy, switches to the cached synced copy when it is not older than the
    /// bundled one, then syncs.
    public func start() async {
        if let bundled {
            apply(bundled.file)
        }
        if let cached = try? persisting.loadCounters(), cacheIsUsable {
            apply(cached)
        }
        await sync()
    }

    /// With a bundle, the cache counts only when its recorded version is known and not older than the
    /// bundled version (after an app update a stale cache must not hide newer bundled data).
    private var cacheIsUsable: Bool {
        guard let bundled else { return true }
        guard let cachedVersion = syncService.lastSyncedVersion() else { return false }
        return !DataVersion.isOlder(cachedVersion, than: bundled.manifest.version)
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
