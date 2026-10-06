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
        try rejectRollback(of: manifest.version)
        if let last = syncState.lastSyncedWordsManifest(), last == manifest {
            return .upToDate
        }

        let data = try await fetcher.fetchWordsData()
        guard sha256Hex(of: data) == manifest.sha256 else {
            throw VerbSyncError.malformedData
        }

        let decoded: WordsDataFile
        do {
            decoded = try JSONDecoder().decode(WordsDataFile.self, from: data)
        } catch {
            throw VerbSyncError.malformedData
        }
        return .updated(manifest: manifest, words: decoded.words)
    }

    /// Records `manifest` as synced. Call only after its words have been persisted.
    public func confirmSynced(_ manifest: WordsManifest) {
        syncState.saveLastSyncedWordsManifest(manifest)
        syncState.saveHighestAcceptedVersion(manifest.version, for: "words")
    }

    /// Refuse a replayed manifest older than the highest version this device accepted.
    private func rejectRollback(of version: String) throws {
        if let highest = syncState.highestAcceptedVersion(for: "words"),
           DataVersion.isOlder(version, than: highest) {
            throw VerbSyncError.untrusted
        }
    }
}
