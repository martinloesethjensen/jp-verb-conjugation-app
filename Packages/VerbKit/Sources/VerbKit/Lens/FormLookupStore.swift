import Foundation
import Observation

/// Holds the matcher for the data the app has now, so "What form is this?" can look up
/// text on every keystroke without rebuilding anything. `update` runs when the verbs (or,
/// after #100, the catalogue) change; `FormIndexCache` skips the build when neither
/// version moved.
@MainActor
@Observable
public final class FormLookupStore {
    /// The catalogue key until #100 syncs `forms.json` and gives it a version.
    public nonisolated static let bundledCatalogueVersion = "bundled"

    /// False until the first `update` with verbs; the views hide their entry points until then.
    public private(set) var isReady = false

    @ObservationIgnored private var cache = FormIndexCache()
    // Observed, so a view that looked text up redraws when the data changes.
    private var matcher: VerbMatcher?
    private var lookup: FormLookup?
    @ObservationIgnored private let tokenizer: any Tokenizing
    /// How many times the index was built; for tests.
    @ObservationIgnored private(set) var builds = 0

    public init(tokenizer: any Tokenizing = SystemTokenizer()) {
        self.tokenizer = tokenizer
    }

    /// Builds the index and matcher for `verbs`, unless they're already built for these
    /// versions. `verbsVersion` is the manifest version of `verbs.json`; nil (no version
    /// recorded yet) falls back to the verb ids, so the index still follows the data.
    public func update(
        verbs: [Verb], verbsVersion: String?,
        catalogue: FormCatalogue = .bundled, catalogueVersion: String = FormLookupStore.bundledCatalogueVersion
    ) {
        guard !verbs.isEmpty else { return }
        let key = FormIndexCache.Key(
            verbs: verbsVersion ?? verbs.map(\.id).joined(separator: ","),
            catalogue: catalogueVersion
        )
        guard cache.key != key || matcher == nil else { return }
        let index = cache.index(verbs: verbs, catalogue: catalogue, key: key)
        builds += 1
        matcher = VerbMatcher(index: index, verbs: verbs, tokenizer: tokenizer)
        lookup = FormLookup(verbs: verbs, catalogue: catalogue)
        isReady = true
    }

    /// The verbs in `text`, labelled for display; empty until the store is ready.
    public func items(in text: String) -> [FormLookup.Item] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let matcher, let lookup else { return [] }
        return lookup.items(for: matcher.spans(in: trimmed))
    }
}
