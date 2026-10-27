import Foundation

public enum WordsSyncResult: Equatable, Sendable {
    case upToDate
    case updated(manifest: WordsManifest, words: [Word])
}

/// Mirrors `FuriganaSyncService` for `words.json`, including its contract: `sync()` does
/// not record anything as synced. The caller persists the words and only then calls
/// `confirmSynced(_:)`.
public struct WordsSyncService: Sendable {
    private let fetcher: VerbDataFetching
    private let syncState: SyncStateStoring

    public init(fetcher: VerbDataFetching, syncState: SyncStateStoring) {
        self.fetcher = fetcher
        self.syncState = syncState
    }

    /// Fetches the manifest's `words` entry. No entry, or an entry unchanged since the last
    /// confirmed sync, returns `.upToDate`. Otherwise fetches words.json, verifies its hash,
    /// decodes it and returns the words. Does NOT record the manifest as synced.
    public func sync() async throws -> WordsSyncResult {
        guard let manifest = try await fetcher.fetchWordsManifest() else {
            return .upToDate
        }
        try SyncVerification.rejectRollback(of: manifest.version, for: .words, syncState: syncState)
        if let last = syncState.lastSyncedWordsManifest(), last == manifest {
            return .upToDate
        }

        let data = try await fetcher.fetchWordsData()
        let decoded = try SyncVerification.decode(WordsDataFile.self, from: data, sha256: manifest.sha256)
        return .updated(manifest: manifest, words: decoded.words)
    }

    /// Records `manifest` as synced. Call only after its words have been persisted.
    public func confirmSynced(_ manifest: WordsManifest) {
        syncState.saveLastSyncedWordsManifest(manifest)
        syncState.saveHighestAcceptedVersion(manifest.version, for: DataFile.words.rawValue)
    }
}
