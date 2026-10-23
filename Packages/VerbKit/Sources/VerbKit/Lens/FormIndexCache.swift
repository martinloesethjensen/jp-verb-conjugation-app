/// Holds the `FormIndex` for the data the app has now, and rebuilds it when either input
/// changes: the verbs (`verbs.json`) or the form catalogue (`forms.json`, synced once #100
/// lands). The two can arrive separately, so the index is keyed on both versions.
public struct FormIndexCache: Sendable {
    /// The data versions an index was built from. `verbs` is the manifest version of
    /// `verbs.json`; `catalogue` is that of `forms.json`, or a fixed name for the bundled
    /// catalogue until #100 syncs it.
    public struct Key: Hashable, Sendable {
        public var verbs: String
        public var catalogue: String

        public init(verbs: String, catalogue: String) {
            self.verbs = verbs
            self.catalogue = catalogue
        }
    }

    public private(set) var key: Key?
    private var cached: FormIndex?

    public init() {}

    /// The index for `key`: the cached one when the versions match, otherwise one built
    /// from `verbs` and `catalogue`, which replaces it. Building is a single pass, cheap
    /// enough to run on load.
    public mutating func index(verbs: [Verb], catalogue: FormCatalogue, key: Key) -> FormIndex {
        if let cached, self.key == key { return cached }
        let index = FormIndex(verbs: verbs, catalogue: catalogue)
        cached = index
        self.key = key
        return index
    }
}
