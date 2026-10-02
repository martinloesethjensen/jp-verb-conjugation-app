public protocol SyncStateStoring: Sendable {
    func lastSyncedManifest() -> VerbManifest?
    func saveLastSyncedManifest(_ manifest: VerbManifest)

    func lastSyncedGrammarManifest() -> GrammarManifest?
    func saveLastSyncedGrammarManifest(_ manifest: GrammarManifest)

    func lastSyncedFuriganaManifest() -> FuriganaManifest?
    func saveLastSyncedFuriganaManifest(_ manifest: FuriganaManifest)

    /// The highest data version ever accepted for `file` ("verbs", "grammar", "furigana").
    /// Unlike the last-synced manifests this survives app updates, so an old but validly
    /// signed manifest can never roll the data back.
    func highestAcceptedVersion(for file: String) -> String?
    func saveHighestAcceptedVersion(_ version: String, for file: String)
}
