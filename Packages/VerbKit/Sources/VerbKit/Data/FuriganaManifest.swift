/// The optional `furigana` block of `manifest.json`. Same shape as
/// `GrammarManifest` but a separate type, like it, so each file's sync state
/// compares on its own.
public struct FuriganaManifest: Codable, Equatable, Sendable {
    public var version: String
    public var sha256: String

    public init(version: String, sha256: String) {
        self.version = version
        self.sha256 = sha256
    }
}
