public protocol SyncStateStoring: Sendable {
    func lastSyncedManifest() -> VerbManifest?
    func saveLastSyncedManifest(_ manifest: VerbManifest)

    func lastSyncedGrammarManifest() -> GrammarManifest?
    func saveLastSyncedGrammarManifest(_ manifest: GrammarManifest)

    func lastSyncedFuriganaManifest() -> FuriganaManifest?
    func saveLastSyncedFuriganaManifest(_ manifest: FuriganaManifest)

    func lastSyncedWordsManifest() -> WordsManifest?
    func saveLastSyncedWordsManifest(_ manifest: WordsManifest)

    func lastSyncedCountersManifest() -> CountersManifest?
    func saveLastSyncedCountersManifest(_ manifest: CountersManifest)

    func lastSyncedFormsManifest() -> FormsManifest?
    func saveLastSyncedFormsManifest(_ manifest: FormsManifest)

    func lastSyncedKanjiManifest() -> KanjiManifest?
    func saveLastSyncedKanjiManifest(_ manifest: KanjiManifest)

    /// The highest data version ever accepted for `file` ("verbs", "grammar", "furigana", "words", "counters", "forms", "kanji").
    /// Unlike the last-synced manifests this survives app updates, so an old but validly
    /// signed manifest can never roll the data back.
    func highestAcceptedVersion(for file: String) -> String?
    func saveHighestAcceptedVersion(_ version: String, for file: String)
}
