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

    /// The manifest's `words` entry, or `nil` if none is published.
    func fetchWordsManifest() async throws -> WordsManifest?
    func fetchWordsData() async throws -> Data

    /// The manifest's `counters` entry, or `nil` if none is published.
    func fetchCountersManifest() async throws -> CountersManifest?
    func fetchCountersData() async throws -> Data

    /// The manifest's `forms` entry (the form catalogue), or `nil` if none is published.
    func fetchFormsManifest() async throws -> FormsManifest?
    func fetchFormsData() async throws -> Data
}
