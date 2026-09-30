import Observation

/// Owns the furigana dictionary: loads the cached copy, then syncs a newer one
/// in the background. Separate from `VerbStore` on purpose: furigana is an
/// enhancement, so nothing here can affect the verb list or first launch, and
/// every failure is silent. `dictionary` stays `nil` until one is available,
/// which the app treats as "show no furigana".
@MainActor
@Observable
public final class FuriganaStore {
    public private(set) var dictionary: FuriganaDictionary?

    private let syncService: FuriganaSyncService
    private let persisting: FuriganaPersisting

    public init(syncService: FuriganaSyncService, persisting: FuriganaPersisting) {
        self.syncService = syncService
        self.persisting = persisting
    }

    public func start() async {
        if let cached = try? persisting.loadFuriganaDictionary() {
            dictionary = cached
        }
        await sync()
    }

    /// Same contract as the verb and grammar syncs: persist first, and only
    /// then confirm the manifest, so a persistence failure leaves it
    /// unrecorded and the next attempt genuinely retries.
    private func sync() async {
        guard let result = try? await syncService.sync() else { return }
        guard case let .updated(manifest, fresh) = result else { return }
        do {
            try persisting.replaceFuriganaDictionary(with: fresh)
        } catch {
            return
        }
        syncService.confirmSynced(manifest)
        dictionary = fresh
    }
}
