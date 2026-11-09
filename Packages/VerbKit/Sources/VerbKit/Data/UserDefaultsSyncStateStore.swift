import Foundation

public final class UserDefaultsSyncStateStore: SyncStateStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let versionKey = "VerbKit.lastSyncedManifest.version"
    private let hashKey = "VerbKit.lastSyncedManifest.sha256"
    private let grammarVersionKey = "VerbKit.lastSyncedGrammarManifest.version"
    private let grammarHashKey = "VerbKit.lastSyncedGrammarManifest.sha256"
    private let furiganaVersionKey = "VerbKit.lastSyncedFuriganaManifest.version"
    private let furiganaHashKey = "VerbKit.lastSyncedFuriganaManifest.sha256"
    private let wordsVersionKey = "VerbKit.lastSyncedWordsManifest.version"
    private let wordsHashKey = "VerbKit.lastSyncedWordsManifest.sha256"
    private let countersVersionKey = "VerbKit.lastSyncedCountersManifest.version"
    private let countersHashKey = "VerbKit.lastSyncedCountersManifest.sha256"
    private let formsVersionKey = "VerbKit.lastSyncedFormsManifest.version"
    private let formsHashKey = "VerbKit.lastSyncedFormsManifest.sha256"
    private let kanjiVersionKey = "VerbKit.lastSyncedKanjiManifest.version"
    private let kanjiHashKey = "VerbKit.lastSyncedKanjiManifest.sha256"

    private let build: String

    /// `build` identifies the running app build. A manifest recorded by a different
    /// build is treated as never synced, so every update re-fetches each file once:
    /// an older build may have stored data without fields this one reads.
    public init(defaults: UserDefaults = .standard, build: String = UserDefaultsSyncStateStore.currentBuild) {
        self.defaults = defaults
        self.build = build
    }

    public static var currentBuild: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let number = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(number))"
    }

    private func isCurrent(_ versionKey: String) -> Bool {
        defaults.string(forKey: versionKey + ".build") == build
    }

    private func markCurrent(_ versionKey: String) {
        defaults.set(build, forKey: versionKey + ".build")
    }

    public func lastSyncedManifest() -> VerbManifest? {
        guard isCurrent(versionKey),
              let version = defaults.string(forKey: versionKey),
              let sha256 = defaults.string(forKey: hashKey) else { return nil }
        return VerbManifest(version: version, sha256: sha256)
    }

    public func saveLastSyncedManifest(_ manifest: VerbManifest) {
        defaults.set(manifest.version, forKey: versionKey)
        markCurrent(versionKey)
        defaults.set(manifest.sha256, forKey: hashKey)
    }

    public func lastSyncedGrammarManifest() -> GrammarManifest? {
        guard isCurrent(grammarVersionKey),
              let version = defaults.string(forKey: grammarVersionKey),
              let sha256 = defaults.string(forKey: grammarHashKey) else { return nil }
        return GrammarManifest(version: version, sha256: sha256)
    }

    public func saveLastSyncedGrammarManifest(_ manifest: GrammarManifest) {
        defaults.set(manifest.version, forKey: grammarVersionKey)
        markCurrent(grammarVersionKey)
        defaults.set(manifest.sha256, forKey: grammarHashKey)
    }

    public func lastSyncedFuriganaManifest() -> FuriganaManifest? {
        guard isCurrent(furiganaVersionKey),
              let version = defaults.string(forKey: furiganaVersionKey),
              let sha256 = defaults.string(forKey: furiganaHashKey) else { return nil }
        return FuriganaManifest(version: version, sha256: sha256)
    }

    public func saveLastSyncedFuriganaManifest(_ manifest: FuriganaManifest) {
        defaults.set(manifest.version, forKey: furiganaVersionKey)
        markCurrent(furiganaVersionKey)
        defaults.set(manifest.sha256, forKey: furiganaHashKey)
    }

    public func lastSyncedWordsManifest() -> WordsManifest? {
        guard isCurrent(wordsVersionKey),
              let version = defaults.string(forKey: wordsVersionKey),
              let sha256 = defaults.string(forKey: wordsHashKey) else { return nil }
        return WordsManifest(version: version, sha256: sha256)
    }

    public func saveLastSyncedWordsManifest(_ manifest: WordsManifest) {
        defaults.set(manifest.version, forKey: wordsVersionKey)
        markCurrent(wordsVersionKey)
        defaults.set(manifest.sha256, forKey: wordsHashKey)
    }

    public func lastSyncedCountersManifest() -> CountersManifest? {
        guard isCurrent(countersVersionKey),
              let version = defaults.string(forKey: countersVersionKey),
              let sha256 = defaults.string(forKey: countersHashKey) else { return nil }
        return CountersManifest(version: version, sha256: sha256)
    }

    public func saveLastSyncedCountersManifest(_ manifest: CountersManifest) {
        defaults.set(manifest.version, forKey: countersVersionKey)
        markCurrent(countersVersionKey)
        defaults.set(manifest.sha256, forKey: countersHashKey)
    }

    public func lastSyncedFormsManifest() -> FormsManifest? {
        guard isCurrent(formsVersionKey),
              let version = defaults.string(forKey: formsVersionKey),
              let sha256 = defaults.string(forKey: formsHashKey) else { return nil }
        return FormsManifest(version: version, sha256: sha256)
    }

    public func saveLastSyncedFormsManifest(_ manifest: FormsManifest) {
        defaults.set(manifest.version, forKey: formsVersionKey)
        markCurrent(formsVersionKey)
        defaults.set(manifest.sha256, forKey: formsHashKey)
    }

    public func lastSyncedKanjiManifest() -> KanjiManifest? {
        guard isCurrent(kanjiVersionKey),
              let version = defaults.string(forKey: kanjiVersionKey),
              let sha256 = defaults.string(forKey: kanjiHashKey) else { return nil }
        return KanjiManifest(version: version, sha256: sha256)
    }

    public func saveLastSyncedKanjiManifest(_ manifest: KanjiManifest) {
        defaults.set(manifest.version, forKey: kanjiVersionKey)
        markCurrent(kanjiVersionKey)
        defaults.set(manifest.sha256, forKey: kanjiHashKey)
    }

    /// Whether `defaults` (where the app keeps its sync state) has ever accepted verb data: an
    /// existing install. Reads the raw keys, so an app update (a new build) still counts.
    public static func hasAcceptedVerbs(in defaults: UserDefaults) -> Bool {
        defaults.string(forKey: "VerbKit.lastSyncedManifest.version") != nil
            || defaults.string(forKey: "VerbKit.highestAcceptedVersion.verbs") != nil
    }

    public func highestAcceptedVersion(for file: String) -> String? {
        defaults.string(forKey: "VerbKit.highestAcceptedVersion.\(file)")
    }

    public func saveHighestAcceptedVersion(_ version: String, for file: String) {
        defaults.set(version, forKey: "VerbKit.highestAcceptedVersion.\(file)")
    }
}
