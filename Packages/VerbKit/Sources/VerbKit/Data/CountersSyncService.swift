import Foundation

public enum CountersSyncResult: Equatable, Sendable {
    case upToDate
    case updated(manifest: CountersManifest, counters: CountersDataFile)
}

/// Mirrors `WordsSyncService` for `counters.json`, including its contract: `sync()` does
/// not record anything as synced. The caller persists the counters and only then calls
/// `confirmSynced(_:)`.
public struct CountersSyncService: Sendable {
    private let fetcher: VerbDataFetching
    private let syncState: SyncStateStoring

    public init(fetcher: VerbDataFetching, syncState: SyncStateStoring) {
        self.fetcher = fetcher
        self.syncState = syncState
    }

    /// Fetches the manifest's `counters` entry. No entry, or an entry unchanged since the last
    /// confirmed sync, returns `.upToDate`. Otherwise fetches counters.json, verifies its hash,
    /// decodes it and returns the file. Does NOT record the manifest as synced.
    public func sync() async throws -> CountersSyncResult {
        guard let manifest = try await fetcher.fetchCountersManifest() else {
            return .upToDate
        }
        try SyncVerification.rejectRollback(of: manifest.version, for: .counters, syncState: syncState)
        if let last = syncState.lastSyncedCountersManifest(), last == manifest {
            return .upToDate
        }

        let data = try await fetcher.fetchCountersData()
        let decoded = try SyncVerification.decode(CountersDataFile.self, from: data, sha256: manifest.sha256)
        return .updated(manifest: manifest, counters: decoded)
    }

    /// Records `manifest` as synced. Call only after its counters have been persisted.
    public func confirmSynced(_ manifest: CountersManifest) {
        syncState.saveLastSyncedCountersManifest(manifest)
        syncState.saveHighestAcceptedVersion(manifest.version, for: DataFile.counters.rawValue)
    }
}
