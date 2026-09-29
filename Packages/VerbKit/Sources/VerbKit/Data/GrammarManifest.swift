/// The optional `grammar` block of `manifest.json`. It has the same shape
/// as `VerbManifest` but is a separate type on purpose: `VerbManifest`
/// compares by whole-struct equality to decide whether verbs changed, so
/// nesting grammar inside it would make a grammar edit re-download verbs.
public struct GrammarManifest: Codable, Equatable, Sendable {
    public var version: String
    public var sha256: String

    public init(version: String, sha256: String) {
        self.version = version
        self.sha256 = sha256
    }
}
