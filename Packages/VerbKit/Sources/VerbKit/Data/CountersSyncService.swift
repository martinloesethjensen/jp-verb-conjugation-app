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

    /// The highest version this device has accepted, which a bundled copy must beat to be installed.
    public func acceptedVersion() -> String? {
        syncState.highestAcceptedVersion(for: "counters")
    }

    /// Fetches the manifest's `counters` entry. No entry, or an entry unchanged since the last
    /// confirmed sync, returns `.upToDate`. Otherwise fetches counters.json, verifies its hash,
    /// decodes it and returns the file. Does NOT record the manifest as synced.
    public func sync() async throws -> CountersSyncResult {
        guard let manifest = try await fetcher.fetchCountersManifest() else {
            return .upToDate
        }
        try rejectRollback(of: manifest.version)
        if let last = syncState.lastSyncedCountersManifest(), last == manifest {
            return .upToDate
        }

        let data = try await fetcher.fetchCountersData()
        guard sha256Hex(of: data) == manifest.sha256 else {
            throw VerbSyncError.malformedData
        }

        let decoded: CountersDataFile
        do {
            decoded = try JSONDecoder().decode(CountersDataFile.self, from: data)
        } catch {
            throw VerbSyncError.malformedData
        }
        return .updated(manifest: manifest, counters: decoded)
    }

    /// Records `manifest` as synced. Call only after its counters have been persisted.
    public func confirmSynced(_ manifest: CountersManifest) {
        syncState.saveLastSyncedCountersManifest(manifest)
        syncState.saveHighestAcceptedVersion(manifest.version, for: "counters")
    }

    /// Refuse a replayed manifest older than the highest version this device accepted.
    private func rejectRollback(of version: String) throws {
        if let highest = syncState.highestAcceptedVersion(for: "counters"),
           DataVersion.isOlder(version, than: highest) {
            throw VerbSyncError.untrusted
        }
    }
}
