import Foundation
import Observation

/// Owns the kanji data the stroke-order sheet reads. Starts from the bundled copy, so a first launch
/// works offline; uses the cached synced copy instead when it is intact and newer; then syncs a newer
/// one. Like `FormCatalogueStore`, a bad synced file never replaces a good one and never stops the app.
///
/// The file is 2.4 MB, so decoding runs off the main actor; until it finishes, `entry(for:)` is nil
/// and no stroke-order entry points show.
@MainActor
@Observable
public final class KanjiStore {
    public private(set) var version: String?
    private var entries: [Character: KanjiEntry] = [:]

    private let syncService: KanjiSyncService
    private let persisting: KanjiPersisting
    private let syncStatus: DataSyncStatus?
    private let bundled: BundledKanji?

    public init(
        syncService: KanjiSyncService, persisting: KanjiPersisting, syncStatus: DataSyncStatus? = nil,
        bundled: BundledKanji? = BundledKanji.load()
    ) {
        self.syncService = syncService
        self.persisting = persisting
        self.syncStatus = syncStatus
        self.bundled = bundled
    }

    /// Loads the cached copy when it is intact and newer than the bundled one (else the bundled
    /// one), then syncs.
    public func start() async {
        await loadInitial()
        await sync()
    }

    /// Settings' Refresh data.
    public func refresh() async {
        await sync()
    }

    public func entry(for character: Character) -> KanjiEntry? {
        entries[character]
    }

    /// The distinct kanji in `texts` that have data, in the order first seen (never 々).
    public func kanji(in texts: [String]) -> [Character] {
        KanjiExtraction.kanji(in: texts).filter { entries[$0] != nil }
    }

    private func loadInitial() async {
        var candidates: [(version: String, data: Data)] = []
        if let cached = try? persisting.loadKanji(), sha256Hex(of: cached.data) == cached.manifest.sha256,
           bundled.map({ DataVersion.isNewer(cached.manifest.version, than: $0.version) }) ?? true {
            candidates.append((cached.manifest.version, cached.data))
        }
        if let bundled {
            candidates.append((bundled.version, bundled.data))
        }
        for candidate in candidates {
            if let file = await Self.decodeOffMain(candidate.data) {
                // A sync (Settings' Refresh data) may have applied a newer file while this decoded.
                guard DataVersion.isNewer(candidate.version, than: version) else { return }
                use(file, version: candidate.version)
                return
            }
        }
    }

    /// Persist first, then confirm, so a failed save is retried next time.
    private func sync() async {
        let result: KanjiSyncResult
        do {
            result = try await syncService.sync()
        } catch {
            syncStatus?.recordFailure(.kanji, error)
            return
        }
        guard case let .updated(manifest, data, file) = result else {
            syncStatus?.recordUpToDate(.kanji)
            return
        }
        do {
            try persisting.replaceKanji(with: SyncedKanjiData(manifest: manifest, data: data))
        } catch {
            syncStatus?.recordFailure(.kanji, error, whileSaving: true)
            return
        }
        syncService.confirmSynced(manifest)
        use(file, version: manifest.version)
        syncStatus?.recordUpdated(.kanji, version: manifest.version)
    }

    private func use(_ file: KanjiDataFile, version: String) {
        entries = file.entries
        self.version = version
        syncStatus?.recordInUse(.kanji, version: version)
    }

    private nonisolated static func decodeOffMain(_ data: Data) async -> KanjiDataFile? {
        await Task.detached(priority: .userInitiated) { try? KanjiDataFile.decode(data) }.value
    }
}
