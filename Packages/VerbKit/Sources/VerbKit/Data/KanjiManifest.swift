/// The optional `kanji` block of `manifest.json`: version and hash of kanji.json.
/// Separate from the other manifests for the same reason as `FormsManifest`.
public struct KanjiManifest: Codable, Equatable, Sendable {
    public var version: String
    public var sha256: String

    public init(version: String, sha256: String) {
        self.version = version
        self.sha256 = sha256
    }
}
