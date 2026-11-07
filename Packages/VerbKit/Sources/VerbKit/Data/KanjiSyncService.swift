import Foundation

public enum KanjiSyncResult: Equatable, Sendable {
    case upToDate
    /// A verified file: `data` is the exact bytes (kept so the cached copy can be hash-checked
    /// again on load) and `file` the decoded result, so it is not decoded twice.
    case updated(manifest: KanjiManifest, data: Data, file: KanjiDataFile)
}

/// Syncs `kanji.json` (stroke order, readings and meanings) under the same rules as the other data
/// files (`docs/security/data-signing.md`): the fetcher checks the manifest's signature, the file
/// must match its hash, a pinned `ref` is honoured, and an older version than one already accepted
/// is refused. Same contract as `FormsSyncService`: `sync()` records nothing; the caller persists the
/// file and only then calls `confirmSynced(_:)`.
///
/// A file with a newer major `schema` throws `KanjiDataFile.LoadError.unsupportedSchema` (shown as
/// "needs a newer app") and the app keeps what it has; anything else unreadable is
/// `VerbSyncError.malformedData`.
public struct KanjiSyncService: Sendable {
    private let fetcher: VerbDataFetching
    private let syncState: SyncStateStoring

    public init(fetcher: VerbDataFetching, syncState: SyncStateStoring) {
        self.fetcher = fetcher
        self.syncState = syncState
    }

    public func sync() async throws -> KanjiSyncResult {
        guard let manifest = try await fetcher.fetchKanjiManifest() else {
            return .upToDate
        }
        try SyncVerification.rejectRollback(of: manifest.version, for: .kanji, syncState: syncState)
        if let last = syncState.lastSyncedKanjiManifest(), last == manifest {
            return .upToDate
        }

        let data = try await fetcher.fetchKanjiData()
        try SyncVerification.verify(data, sha256: manifest.sha256)
        let file: KanjiDataFile
        do {
            file = try KanjiDataFile.decode(data)
        } catch KanjiDataFile.LoadError.malformed {
            throw VerbSyncError.malformedData
        }
        return .updated(manifest: manifest, data: data, file: file)
    }

    /// Records `manifest` as synced. Call only after its file has been persisted.
    public func confirmSynced(_ manifest: KanjiManifest) {
        syncState.saveLastSyncedKanjiManifest(manifest)
        syncState.saveHighestAcceptedVersion(manifest.version, for: DataFile.kanji.rawValue)
    }

    /// The highest version this device has accepted, so a bundled copy only wins when newer.
    public func acceptedVersion() -> String? {
        syncState.highestAcceptedVersion(for: DataFile.kanji.rawValue)
    }
}
