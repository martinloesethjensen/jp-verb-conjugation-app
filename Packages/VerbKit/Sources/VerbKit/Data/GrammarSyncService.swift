import Foundation

public enum GrammarSyncResult: Equatable, Sendable {
    case upToDate
    case updated(manifest: GrammarManifest, points: [GrammarPoint])
}

/// Mirrors `VerbSyncService` for `grammar.json`, including its contract:
/// `sync()` does not record anything as synced. The caller persists the
/// points and only then calls `confirmSynced(_:)`, so a persistence
/// failure can't be mistaken for "nothing changed" on the next attempt.
///
/// It is deliberately a second concrete service, not a generic one: with
/// two users an abstraction isn't earning its keep yet.
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
        try rejectRollback(of: manifest.version)
        if let last = syncState.lastSyncedGrammarManifest(), last == manifest {
            return .upToDate
        }

        let data = try await fetcher.fetchGrammarData()
        guard sha256Hex(of: data) == manifest.sha256 else {
            throw VerbSyncError.malformedData
        }

        let decoded: GrammarDataFile
        do {
            decoded = try JSONDecoder().decode(GrammarDataFile.self, from: data)
        } catch {
            throw VerbSyncError.malformedData
        }

        return .updated(manifest: manifest, points: decoded.grammar)
    }

    /// Records `manifest` as the last successfully synced grammar
    /// manifest. Call only after the points that came with it have been
    /// durably persisted.
    public func confirmSynced(_ manifest: GrammarManifest) {
        syncState.saveLastSyncedGrammarManifest(manifest)
        syncState.saveHighestAcceptedVersion(manifest.version, for: "grammar")
    }

    /// A validly signed manifest can still be an old one replayed. Refuse any version
    /// older than the highest this device has accepted.
    private func rejectRollback(of version: String) throws {
        if let highest = syncState.highestAcceptedVersion(for: "grammar"),
           DataVersion.isOlder(version, than: highest) {
            throw VerbSyncError.untrusted
        }
    }
}
