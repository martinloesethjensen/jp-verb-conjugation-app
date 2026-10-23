import Foundation
import SwiftData

/// The synced form catalogue as it was verified: one row with the exact `forms.json` bytes and
/// its manifest entry, so it can be hash-checked again and decoded by whichever build loads it.
/// The bundled copy is never stored here.
@Model
public final class FormCatalogueEntity {
    @Attribute(.unique) public var key: String
    private var version: String
    private var sha256: String
    private var payload: Data

    public static let rowKey = "forms"

    public init(_ synced: SyncedFormCatalogue) {
        self.key = Self.rowKey
        self.version = synced.manifest.version
        self.sha256 = synced.manifest.sha256
        self.payload = synced.data
    }

    public func toSynced() -> SyncedFormCatalogue {
        SyncedFormCatalogue(manifest: FormsManifest(version: version, sha256: sha256), data: payload)
    }
}
