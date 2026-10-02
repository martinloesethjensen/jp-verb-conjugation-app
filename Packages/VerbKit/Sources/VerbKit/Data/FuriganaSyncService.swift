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
/// This is deliberately a third concrete copy of the pattern rather than a
/// shared abstraction: `VerbSyncService` has a different manifest shape, so a
/// generic version would not cover all three. Revisit at a fourth file.
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
        try rejectRollback(of: manifest.version)
        if let last = syncState.lastSyncedFuriganaManifest(), last == manifest {
            return .upToDate
        }

        let data = try await fetcher.fetchFuriganaData()
        guard sha256Hex(of: data) == manifest.sha256 else {
            throw VerbSyncError.malformedData
        }

        let decoded: FuriganaDataFile
        do {
            decoded = try JSONDecoder().decode(FuriganaDataFile.self, from: data)
        } catch {
            throw VerbSyncError.malformedData
        }

        return .updated(manifest: manifest, dictionary: FuriganaDictionary(file: decoded))
    }

    /// Records `manifest` as the last successfully synced furigana manifest.
    /// Call only after the dictionary that came with it has been durably
    /// persisted.
    public func confirmSynced(_ manifest: FuriganaManifest) {
        syncState.saveLastSyncedFuriganaManifest(manifest)
        syncState.saveHighestAcceptedVersion(manifest.version, for: "furigana")
    }

    /// A validly signed manifest can still be an old one replayed. Refuse any version
    /// older than the highest this device has accepted.
    private func rejectRollback(of version: String) throws {
        if let highest = syncState.highestAcceptedVersion(for: "furigana"),
           DataVersion.isOlder(version, than: highest) {
            throw VerbSyncError.untrusted
        }
    }
}
