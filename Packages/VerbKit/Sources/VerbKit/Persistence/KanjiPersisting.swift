import Foundation

/// A synced `kanji.json` and the manifest entry it was verified against.
public struct SyncedKanjiData: Equatable, Sendable {
    public var manifest: KanjiManifest
    public var data: Data

    public init(manifest: KanjiManifest, data: Data) {
        self.manifest = manifest
        self.data = data
    }
}

@MainActor
public protocol KanjiPersisting {
    /// The cached synced file, or `nil` if none has been stored yet.
    func loadKanji() throws -> SyncedKanjiData?
    func replaceKanji(with synced: SyncedKanjiData) throws
}
