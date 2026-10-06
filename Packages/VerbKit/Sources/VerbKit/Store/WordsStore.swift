import Observation

/// Owns the adjective and noun list the grammar building blocks use: loads the cached
/// copy, then syncs a newer one. Like `FuriganaStore`, every failure is silent; `words`
/// stays empty until a list is available, and verbs come from `VerbStore` as before.
@MainActor
@Observable
public final class WordsStore {
    public private(set) var words: [Word] = []

    private let syncService: WordsSyncService
    private let persisting: WordsPersisting

    public init(syncService: WordsSyncService, persisting: WordsPersisting) {
        self.syncService = syncService
        self.persisting = persisting
    }

    public func start() async {
        if let cached = try? persisting.loadWords() {
            words = cached
        }
        await sync()
    }

    /// The words of one class, in file order.
    public func words(of wordClass: WordClass) -> [Word] {
        words.filter { $0.wordClass == wordClass }
    }

    /// Persist first, then confirm, so a failed save is retried next time.
    private func sync() async {
        guard let result = try? await syncService.sync() else { return }
        guard case let .updated(manifest, fresh) = result else { return }
        do {
            try persisting.replaceWords(with: fresh)
        } catch {
            return
        }
        syncService.confirmSynced(manifest)
        words = fresh
    }
}
