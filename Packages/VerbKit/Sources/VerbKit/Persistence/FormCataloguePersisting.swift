import Foundation

/// A synced `forms.json` and the manifest entry it was verified against.
public struct SyncedFormCatalogue: Equatable, Sendable {
    public var manifest: FormsManifest
    public var data: Data

    public init(manifest: FormsManifest, data: Data) {
        self.manifest = manifest
        self.data = data
    }
}

@MainActor
public protocol FormCataloguePersisting {
    /// The cached synced catalogue, or `nil` if none has been stored yet.
    func loadFormCatalogue() throws -> SyncedFormCatalogue?
    func replaceFormCatalogue(with synced: SyncedFormCatalogue) throws
}
