import Foundation

public enum FormsSyncResult: Equatable, Sendable {
    case upToDate
    /// A verified catalogue: `data` is the exact file, kept so the cached copy can be
    /// hash-checked again on load.
    case updated(manifest: FormsManifest, data: Data)
}

/// Syncs `forms.json`, the form catalogue, under the same rules as the other data files
/// (`docs/security/data-signing.md`): the manifest is signature-checked by the fetcher, the
/// file must match its hash, a pinned `ref` is honoured, and an older version than one
/// already accepted is refused. Same contract as `WordsSyncService`: `sync()` records
/// nothing; the caller persists the file and only then calls `confirmSynced(_:)`.
///
/// A catalogue this build cannot use is refused, and the app keeps the one it has: a newer
/// major `schema` or one without the forms code relies on throws the `FormCatalogue.LoadError`
/// (shown as "needs a newer app"); anything else unreadable is `VerbSyncError.malformedData`.
public struct FormsSyncService: Sendable {
    private let fetcher: VerbDataFetching
    private let syncState: SyncStateStoring

    public init(fetcher: VerbDataFetching, syncState: SyncStateStoring) {
        self.fetcher = fetcher
        self.syncState = syncState
    }

    public func sync() async throws -> FormsSyncResult {
        guard let manifest = try await fetcher.fetchFormsManifest() else {
            return .upToDate
        }
        try rejectRollback(of: manifest.version)
        if let last = syncState.lastSyncedFormsManifest(), last == manifest {
            return .upToDate
        }

        let data = try await fetcher.fetchFormsData()
        guard sha256Hex(of: data) == manifest.sha256 else {
            throw VerbSyncError.malformedData
        }
        do {
            _ = try FormCatalogue.replacement(data: data, version: manifest.version)
        } catch FormCatalogue.LoadError.malformed {
            throw VerbSyncError.malformedData
        }
        return .updated(manifest: manifest, data: data)
    }

    /// Records `manifest` as synced. Call only after its file has been persisted.
    public func confirmSynced(_ manifest: FormsManifest) {
        syncState.saveLastSyncedFormsManifest(manifest)
        syncState.saveHighestAcceptedVersion(manifest.version, for: "forms")
    }

    /// Refuse a replayed manifest older than the highest version this device accepted.
    private func rejectRollback(of version: String) throws {
        if let highest = syncState.highestAcceptedVersion(for: "forms"),
           DataVersion.isOlder(version, than: highest) {
            throw VerbSyncError.untrusted
        }
    }
}
