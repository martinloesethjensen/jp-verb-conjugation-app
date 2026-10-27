import Observation

/// Owns the form catalogue in use. Starts on the bundled copy, so a first launch works
/// offline; then uses the cached synced copy, and syncs a newer one, whenever that is newer
/// than the bundled copy and passed verification (signature, hash, no rollback, a schema and
/// forms this build can use). Anything else keeps the catalogue it has: a bad synced
/// catalogue never replaces a good one, and never stops the app.
///
/// The catalogue it settles on is installed as `FormCatalogue.current`, which the quiz reads.
@MainActor
@Observable
public final class FormCatalogueStore {
    public private(set) var catalogue: FormCatalogue

    private let syncService: FormsSyncService
    private let persisting: FormCataloguePersisting
    private let syncStatus: DataSyncStatus?
    private let bundled: FormCatalogue
    private let install: @MainActor (FormCatalogue) -> Void
    private var loadedCache = false

    /// - Parameters:
    ///   - bundled: the catalogue the app ships with (`FormCatalogue.bundled`).
    ///   - install: makes a catalogue the app-wide one; `FormCatalogue.current` by default.
    public init(
        syncService: FormsSyncService,
        persisting: FormCataloguePersisting,
        syncStatus: DataSyncStatus? = nil,
        bundled: FormCatalogue = .bundled,
        install: @escaping @MainActor (FormCatalogue) -> Void = { FormCatalogue.current = $0 }
    ) {
        self.syncService = syncService
        self.persisting = persisting
        self.syncStatus = syncStatus
        self.bundled = bundled
        self.install = install
        self.catalogue = bundled
    }

    /// Loads the cached synced catalogue (if it is newer than the bundled one), then syncs.
    public func start() async {
        loadCached()
        await sync()
    }

    /// Settings' Refresh data.
    public func refresh() async {
        await sync()
    }

    /// Switches to the cached synced catalogue when it is still intact, readable by this build
    /// and newer than the bundled one; otherwise stays on the bundled one. Cheap and
    /// synchronous, so the app can call it before anything reads the catalogue. Runs once.
    public func loadCached() {
        guard !loadedCache else { return }
        loadedCache = true
        if let cached = try? persisting.loadFormCatalogue(),
           sha256Hex(of: cached.data) == cached.manifest.sha256,
           let synced = try? FormCatalogue.replacement(data: cached.data, version: cached.manifest.version) {
            use(synced)
        } else {
            use(catalogue)
        }
    }

    /// Persist first, then confirm, so a failed save is retried next time.
    private func sync() async {
        let result: FormsSyncResult
        do {
            result = try await syncService.sync()
        } catch {
            syncStatus?.recordFailure(.forms, error)
            return
        }
        guard case let .updated(manifest, data) = result else {
            syncStatus?.recordUpToDate(.forms)
            return
        }
        // The service already decoded it; this can only fail if that changes.
        guard let synced = try? FormCatalogue.replacement(data: data, version: manifest.version) else {
            syncStatus?.recordFailure(.forms, VerbSyncError.malformedData)
            return
        }
        do {
            try persisting.replaceFormCatalogue(with: SyncedFormCatalogue(manifest: manifest, data: data))
        } catch {
            syncStatus?.recordFailure(.forms, error, whileSaving: true)
            return
        }
        syncService.confirmSynced(manifest)
        use(synced)
        syncStatus?.recordUpdated(.forms, version: catalogue.version)
    }

    /// Uses `candidate` if it is newer than the bundled catalogue, else the bundled one, and
    /// installs the result. Only verified catalogues reach here.
    private func use(_ candidate: FormCatalogue) {
        let chosen = candidate.isNewer(than: bundled) ? candidate : bundled
        catalogue = chosen
        install(chosen)
        syncStatus?.recordInUse(.forms, version: chosen.version)
    }
}
