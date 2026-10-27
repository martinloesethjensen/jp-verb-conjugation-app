import Foundation

/// The checks every data-file sync performs before it returns a payload.
///
/// These stay functions rather than a generic `ManifestSyncService`: each file keeps its own
/// concrete service, manifest type, result type and sync-state entry, so syncing one file can
/// never disturb another's. What must not drift between the six services are the security
/// rules — a replayed manifest is refused and a downloaded file must match its manifest — so
/// they live here once.
enum SyncVerification {
    /// Refuse a validly signed manifest that is older than the highest version this device
    /// already accepted (a replay). A newer or equal manifest is left to the caller.
    static func rejectRollback(
        of version: String,
        for file: DataFile,
        syncState: SyncStateStoring
    ) throws {
        if let highest = syncState.highestAcceptedVersion(for: file.rawValue),
           DataVersion.isOlder(version, than: highest) {
            throw VerbSyncError.untrusted
        }
    }

    /// Confirms `data` matches the manifest's hash. A mismatch means the download was
    /// corrupted or incomplete.
    static func verify(_ data: Data, sha256: String) throws {
        guard sha256Hex(of: data) == sha256 else {
            throw VerbSyncError.malformedData
        }
    }

    /// Verifies `data` and decodes it. An undecodable file is as unusable as a corrupted one.
    static func decode<T: Decodable>(_ type: T.Type, from data: Data, sha256: String) throws -> T {
        try verify(data, sha256: sha256)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw VerbSyncError.malformedData
        }
    }
}
