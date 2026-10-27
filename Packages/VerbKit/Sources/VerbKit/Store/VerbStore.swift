import Observation

@MainActor
@Observable
public final class VerbStore {
    public private(set) var verbs: [Verb] = []
    public private(set) var firstLaunchState: FirstLaunchState = .checking
    public var hasLocalData: Bool { !verbs.isEmpty }

    /// Grammar is non-blocking: empty until its first sync succeeds, and
    /// a grammar failure never affects `verbs` or `firstLaunchState`.
    public private(set) var grammarPoints: [GrammarPoint] = []
    public var hasGrammar: Bool { !grammarPoints.isEmpty }
    /// Replaced together with `grammarPoints`.
    public private(set) var textbooks: [Textbook] = []

    private let syncService: VerbSyncService
    private let persisting: VerbPersisting
    private let networkMonitor: NetworkMonitor
    private let grammarSyncService: GrammarSyncService?
    private let grammarPersisting: GrammarPersisting?
    private let syncStatus: DataSyncStatus?
    private let bundledVerbs: BundledData<VerbDataFile>?
    private let bundledGrammar: BundledData<GrammarDataFile>?

    public init(
        syncService: VerbSyncService,
        persisting: VerbPersisting,
        networkMonitor: NetworkMonitor,
        grammarSyncService: GrammarSyncService? = nil,
        grammarPersisting: GrammarPersisting? = nil,
        syncStatus: DataSyncStatus? = nil,
        bundledVerbs: BundledData<VerbDataFile>? = nil,
        bundledGrammar: BundledData<GrammarDataFile>? = nil
    ) {
        self.syncService = syncService
        self.persisting = persisting
        self.networkMonitor = networkMonitor
        self.grammarSyncService = grammarSyncService
        self.grammarPersisting = grammarPersisting
        self.syncStatus = syncStatus
        self.bundledVerbs = bundledVerbs
        self.bundledGrammar = bundledGrammar
    }

    public func start() async {
        networkMonitor.onChange = { [weak self] connected in
            guard connected else { return }
            guard case .failed(.offline) = self?.firstLaunchState else { return }
            Task { @MainActor [weak self] in
                await self?.retryFirstLaunch()
            }
        }

        installBundledGrammar()
        loadCachedGrammar()
        installBundledVerbs()

        if let cached = try? persisting.loadAllVerbs(), !cached.isEmpty {
            verbs = cached
            await syncInBackground()
            await syncGrammar()
            return
        }

        await runFirstLaunchFetch()
    }

    public func retryFirstLaunch() async {
        await runFirstLaunchFetch()
    }

    /// Re-attempts the grammar sync, e.g. from the Grammar tab's Try Again.
    public func retryGrammarSync() async {
        await syncGrammar()
    }

    /// Settings' Refresh data: checks verbs and grammar again. Without any
    /// verbs yet this is the first-launch fetch.
    public func refresh() async {
        guard hasLocalData else {
            await runFirstLaunchFetch()
            return
        }
        await syncInBackground()
        await syncGrammar()
    }

    private func runFirstLaunchFetch() async {
        firstLaunchState = .checking
        firstLaunchState = .fetching
        do {
            let result = try await syncService.sync()
            switch result {
            case .upToDate:
                // Only reachable if a manifest was somehow already
                // recorded as synced with nothing locally persisted —
                // treat as corrupt local state rather than silently
                // leaving the user on an empty verb list forever.
                firstLaunchState = .failed(.malformedData)
                syncStatus?.recordFailure(.verbs, VerbSyncError.malformedData)
            case let .updated(manifest, fetchedVerbs):
                do {
                    try persisting.replaceAllVerbs(with: fetchedVerbs)
                } catch {
                    syncStatus?.recordFailure(.verbs, error, whileSaving: true)
                    throw error
                }
                // Only record the manifest as synced once persistence has
                // actually succeeded — otherwise a persistence failure
                // here would be caught below (leaving the manifest
                // unrecorded) and a retry could genuinely re-fetch,
                // instead of seeing `.upToDate` forever.
                syncService.confirmSynced(manifest)
                syncStatus?.recordUpdated(.verbs, version: manifest.version)
                verbs = fetchedVerbs
                firstLaunchState = .success
                // Verbs are the gate; grammar follows once they're in.
                await syncGrammar()
            }
        } catch let error as VerbSyncError {
            syncStatus?.recordFailure(.verbs, error)
            firstLaunchState = .failed(error)
        } catch {
            // Only a persistence failure, already recorded above.
            firstLaunchState = .failed(.malformedData)
        }
    }

    private func syncInBackground() async {
        let result: VerbSyncResult
        do {
            result = try await syncService.sync()
        } catch {
            syncStatus?.recordFailure(.verbs, error)
            return
        }
        guard case let .updated(manifest, fetchedVerbs) = result else {
            syncStatus?.recordUpToDate(.verbs)
            return
        }
        do {
            try persisting.replaceAllVerbs(with: fetchedVerbs)
        } catch {
            syncStatus?.recordFailure(.verbs, error, whileSaving: true)
            // Persistence failed — leave the manifest unrecorded so the
            // next sync (foreground or background) still sees this as
            // changed and retries, instead of reporting `.upToDate` with
            // nothing actually saved.
            return
        }
        syncService.confirmSynced(manifest)
        syncStatus?.recordUpdated(.verbs, version: manifest.version)
        verbs = fetchedVerbs
    }

    /// Installs the bundled verbs as if they had been synced, when they are newer than anything this device
    /// has accepted. Same contract as a sync: persist first, record only after the save succeeded, and a
    /// failure leaves the old cache and records nothing.
    private func installBundledVerbs() {
        guard let bundled = bundledVerbs,
              DataVersion.isNewer(bundled.version, than: syncService.acceptedVersion()) else { return }
        do {
            try persisting.replaceAllVerbs(with: bundled.value.verbs)
        } catch {
            return
        }
        syncService.confirmSynced(VerbManifest(version: bundled.version, sha256: bundled.sha256))
        syncStatus?.recordBundled(.verbs, version: bundled.version)
    }

    /// The grammar counterpart; it never affects the verbs.
    private func installBundledGrammar() {
        guard let bundled = bundledGrammar, let grammarSyncService, let grammarPersisting,
              DataVersion.isNewer(bundled.version, than: grammarSyncService.acceptedVersion()) else { return }
        do {
            try grammarPersisting.replaceAllGrammar(points: bundled.value.grammar, textbooks: bundled.value.books)
        } catch {
            return
        }
        grammarSyncService.confirmSynced(GrammarManifest(version: bundled.version, sha256: bundled.sha256))
        syncStatus?.recordBundled(.grammar, version: bundled.version)
    }

    private func loadCachedGrammar() {
        guard let grammarPersisting,
              let cached = try? grammarPersisting.loadAllGrammarPoints() else { return }
        grammarPoints = cached
        textbooks = (try? grammarPersisting.loadAllTextbooks()) ?? []
    }

    /// Same contract as the verb sync: persist first, and only then
    /// confirm the manifest, so a persistence failure leaves it
    /// unrecorded and the next sync genuinely retries. Every failure
    /// here is silent (only reported to `syncStatus`) and never touches
    /// `verbs` or `firstLaunchState`.
    private func syncGrammar() async {
        guard let grammarSyncService, let grammarPersisting else { return }
        let result: GrammarSyncResult
        do {
            result = try await grammarSyncService.sync()
        } catch {
            syncStatus?.recordFailure(.grammar, error)
            return
        }
        guard case let .updated(manifest, points, books) = result else {
            syncStatus?.recordUpToDate(.grammar)
            return
        }
        do {
            try grammarPersisting.replaceAllGrammar(points: points, textbooks: books)
        } catch {
            syncStatus?.recordFailure(.grammar, error, whileSaving: true)
            return
        }
        grammarSyncService.confirmSynced(manifest)
        syncStatus?.recordUpdated(.grammar, version: manifest.version)
        grammarPoints = points
        textbooks = books
    }
}
