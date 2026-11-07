import Foundation
import SwiftData

/// The synced kanji file as it was verified: one row with the exact `kanji.json` bytes and its
/// manifest entry, so it can be hash-checked again and decoded by whichever build loads it.
/// The bundled copy is never stored here.
@Model
public final class KanjiDataEntity {
    @Attribute(.unique) public var key: String
    private var version: String
    private var sha256: String
    @Attribute(.externalStorage) private var payload: Data

    public static let rowKey = "kanji"

    public init(_ synced: SyncedKanjiData) {
        self.key = Self.rowKey
        self.version = synced.manifest.version
        self.sha256 = synced.manifest.sha256
        self.payload = synced.data
    }

    public func toSynced() -> SyncedKanjiData {
        SyncedKanjiData(manifest: KanjiManifest(version: version, sha256: sha256), data: payload)
    }
}
