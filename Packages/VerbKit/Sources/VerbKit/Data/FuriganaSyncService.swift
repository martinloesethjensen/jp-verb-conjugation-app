import Foundation

public enum FuriganaSyncResult: Equatable, Sendable {
    case upToDate
    case updated(manifest: FuriganaManifest, dictionary: FuriganaDictionary)
}

/// Mirrors `GrammarSyncService` for `furigana.json`, including its contract:
/// `sync()` does not record anything as synced. The caller persists the
/// dictionary and only then calls `confirmSynced(_:)`, so a persistence
/// failure can't be mistaken for "nothing changed" on the next attempt.
///
/// Like every data file, this stays a concrete service: its manifest,
/// result and sync state are its own, so one file's sync cannot disturb
/// another's. The shared security rules live in `SyncVerification`.
public struct FuriganaSyncService: Sendable {
    private let fetcher: VerbDataFetching
    private let syncState: SyncStateStoring

    public init(fetcher: VerbDataFetching, syncState: SyncStateStoring) {
        self.fetcher = fetcher
        self.syncState = syncState
    }

    /// Fetches the manifest's `furigana` entry. No entry, or an entry
    /// unchanged since the last confirmed sync, returns `.upToDate` without
    /// fetching the dictionary. Otherwise fetches it, verifies its hash (a
    /// mismatch is corrupted/incomplete data), decodes it, and returns it.
    /// Does NOT record the manifest as synced.
    public func sync() async throws -> FuriganaSyncResult {
        guard let manifest = try await fetcher.fetchFuriganaManifest() else {
            return .upToDate
        }
        try SyncVerification.rejectRollback(of: manifest.version, for: .furigana, syncState: syncState)
        if let last = syncState.lastSyncedFuriganaManifest(), last == manifest {
            return .upToDate
        }

        let data = try await fetcher.fetchFuriganaData()
        let decoded = try SyncVerification.decode(FuriganaDataFile.self, from: data, sha256: manifest.sha256)

        return .updated(manifest: manifest, dictionary: FuriganaDictionary(file: decoded))
    }

    /// Records `manifest` as the last successfully synced furigana manifest.
    /// Call only after the dictionary that came with it has been durably
    /// persisted.
    public func confirmSynced(_ manifest: FuriganaManifest) {
        syncState.saveLastSyncedFuriganaManifest(manifest)
        syncState.saveHighestAcceptedVersion(manifest.version, for: DataFile.furigana.rawValue)
    }
}
