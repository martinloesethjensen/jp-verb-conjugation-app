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
    /// it, records the new manifest as synced, and returns the verbs.
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

        syncState.saveLastSyncedManifest(manifest)
        return .updated(manifest: manifest, verbs: decoded.verbs)
    }
}
