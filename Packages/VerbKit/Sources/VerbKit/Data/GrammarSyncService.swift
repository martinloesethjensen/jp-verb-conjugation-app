import Foundation

public enum GrammarSyncResult: Equatable, Sendable {
    case upToDate
    case updated(manifest: GrammarManifest, points: [GrammarPoint], books: [Textbook])
}

/// Mirrors `VerbSyncService` for `grammar.json`, including its contract:
/// `sync()` does not record anything as synced. The caller persists the
/// points and only then calls `confirmSynced(_:)`, so a persistence
/// failure can't be mistaken for "nothing changed" on the next attempt.
///
/// Like every data file, this stays a concrete service: its manifest,
/// result and sync state are its own, so one file's sync cannot disturb
/// another's. The shared security rules live in `SyncVerification`.
public struct GrammarSyncService: Sendable {
    private let fetcher: VerbDataFetching
    private let syncState: SyncStateStoring

    public init(fetcher: VerbDataFetching, syncState: SyncStateStoring) {
        self.fetcher = fetcher
        self.syncState = syncState
    }

    /// Fetches the manifest's `grammar` entry. No entry, or an entry
    /// unchanged since the last confirmed sync, returns `.upToDate`
    /// without fetching grammar data. Otherwise fetches it, verifies its
    /// hash (a mismatch is corrupted/incomplete data), decodes it, and
    /// returns the points. Does NOT record the manifest as synced.
    public func sync() async throws -> GrammarSyncResult {
        guard let manifest = try await fetcher.fetchGrammarManifest() else {
            return .upToDate
        }
        try SyncVerification.rejectRollback(of: manifest.version, for: .grammar, syncState: syncState)
        if let last = syncState.lastSyncedGrammarManifest(), last == manifest {
            return .upToDate
        }

        let data = try await fetcher.fetchGrammarData()
        let decoded = try SyncVerification.decode(GrammarDataFile.self, from: data, sha256: manifest.sha256)

        return .updated(manifest: manifest, points: decoded.grammar, books: decoded.books)
    }

    /// Records `manifest` as the last successfully synced grammar
    /// manifest. Call only after the points that came with it have been
    /// durably persisted.
    public func confirmSynced(_ manifest: GrammarManifest) {
        syncState.saveLastSyncedGrammarManifest(manifest)
        syncState.saveHighestAcceptedVersion(manifest.version, for: DataFile.grammar.rawValue)
    }

    /// The highest version this device has accepted, which a bundled copy must beat to be installed.
    public func acceptedVersion() -> String? {
        syncState.highestAcceptedVersion(for: DataFile.grammar.rawValue)
    }
}
