public protocol SyncStateStoring: Sendable {
    func lastSyncedManifest() -> VerbManifest?
    func saveLastSyncedManifest(_ manifest: VerbManifest)

    func lastSyncedGrammarManifest() -> GrammarManifest?
    func saveLastSyncedGrammarManifest(_ manifest: GrammarManifest)
}
