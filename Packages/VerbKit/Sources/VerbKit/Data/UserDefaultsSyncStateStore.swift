import Foundation

public final class UserDefaultsSyncStateStore: SyncStateStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let versionKey = "VerbKit.lastSyncedManifest.version"
    private let hashKey = "VerbKit.lastSyncedManifest.sha256"
    private let grammarVersionKey = "VerbKit.lastSyncedGrammarManifest.version"
    private let grammarHashKey = "VerbKit.lastSyncedGrammarManifest.sha256"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func lastSyncedManifest() -> VerbManifest? {
        guard let version = defaults.string(forKey: versionKey),
              let sha256 = defaults.string(forKey: hashKey) else { return nil }
        return VerbManifest(version: version, sha256: sha256)
    }

    public func saveLastSyncedManifest(_ manifest: VerbManifest) {
        defaults.set(manifest.version, forKey: versionKey)
        defaults.set(manifest.sha256, forKey: hashKey)
    }

    public func lastSyncedGrammarManifest() -> GrammarManifest? {
        guard let version = defaults.string(forKey: grammarVersionKey),
              let sha256 = defaults.string(forKey: grammarHashKey) else { return nil }
        return GrammarManifest(version: version, sha256: sha256)
    }

    public func saveLastSyncedGrammarManifest(_ manifest: GrammarManifest) {
        defaults.set(manifest.version, forKey: grammarVersionKey)
        defaults.set(manifest.sha256, forKey: grammarHashKey)
    }
}
