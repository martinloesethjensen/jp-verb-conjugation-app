import Foundation

public protocol VerbDataFetching: Sendable {
    func fetchManifest() async throws -> VerbManifest
    func fetchVerbData() async throws -> Data

    /// The manifest's `grammar` entry, or `nil` if none is published.
    func fetchGrammarManifest() async throws -> GrammarManifest?
    func fetchGrammarData() async throws -> Data

    /// The manifest's `furigana` entry, or `nil` if none is published.
    func fetchFuriganaManifest() async throws -> FuriganaManifest?
    func fetchFuriganaData() async throws -> Data
}
