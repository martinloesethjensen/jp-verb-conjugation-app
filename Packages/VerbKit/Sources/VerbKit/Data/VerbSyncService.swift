import Foundation

public enum VerbSyncResult: Equatable, Sendable {
    case upToDate
    case updated(manifest: VerbManifest, verbs: [Verb])
}

public struct VerbSyncService: Sendable {
    private let fetcher: VerbDataFetching
    private let syncState: SyncStateStoring

    public init(fetcher: VerbDataFetching, syncState: SyncStateStoring) {
        self.fetcher = fetcher
        self.syncState = syncState
    }

    /// Fetches the manifest; if unchanged from the last sync, returns
    /// `.upToDate` without ever fetching the (larger) verb data. If
    /// changed, fetches it, verifies its hash against the manifest
    /// (a mismatch is treated as corrupted/incomplete data), decodes
    /// it, and returns the verbs.
    ///
    /// This does NOT record the manifest as synced. Persisting the
    /// decoded verbs is the caller's responsibility (and can fail), so
    /// the caller must call `confirmSynced(_:)` itself, and only after
    /// persistence has actually succeeded. If `sync()` recorded the
    /// manifest as synced unconditionally, a persistence failure would
    /// be indistinguishable from "nothing changed" on the next attempt,
    /// permanently stranding the caller with no verbs and no way to
    /// trigger a re-fetch.
    public func sync() async throws -> VerbSyncResult {
        let manifest = try await fetcher.fetchManifest()
        if let last = syncState.lastSyncedManifest(), last == manifest {
            return .upToDate
        }

        let data = try await fetcher.fetchVerbData()
        guard sha256Hex(of: data) == manifest.sha256 else {
            throw VerbSyncError.malformedData
        }

        let decoded: VerbDataFile
        do {
            decoded = try JSONDecoder().decode(VerbDataFile.self, from: data)
        } catch {
            throw VerbSyncError.malformedData
        }

        return .updated(manifest: manifest, verbs: decoded.verbs)
    }

    /// Records `manifest` as the last successfully synced manifest.
    /// Callers must only call this after they have durably persisted
    /// the verbs that came with it — see `sync()`'s documentation.
    public func confirmSynced(_ manifest: VerbManifest) {
        syncState.saveLastSyncedManifest(manifest)
    }
}
