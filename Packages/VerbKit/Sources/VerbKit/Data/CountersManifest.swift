/// The optional `counters` block of `manifest.json`: version and hash of counters.json.
/// Separate from `VerbManifest` for the same reason as `GrammarManifest`.
public struct CountersManifest: Codable, Equatable, Sendable {
    public var version: String
    public var sha256: String

    public init(version: String, sha256: String) {
        self.version = version
        self.sha256 = sha256
    }
}
