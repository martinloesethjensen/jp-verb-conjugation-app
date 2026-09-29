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

    private let syncService: VerbSyncService
    private let persisting: VerbPersisting
    private let networkMonitor: NetworkMonitor
    private let grammarSyncService: GrammarSyncService?
    private let grammarPersisting: GrammarPersisting?

    public init(
        syncService: VerbSyncService,
        persisting: VerbPersisting,
        networkMonitor: NetworkMonitor,
        grammarSyncService: GrammarSyncService? = nil,
        grammarPersisting: GrammarPersisting? = nil
    ) {
        self.syncService = syncService
        self.persisting = persisting
        self.networkMonitor = networkMonitor
        self.grammarSyncService = grammarSyncService
        self.grammarPersisting = grammarPersisting
    }

    public func start() async {
        networkMonitor.onChange = { [weak self] connected in
            guard connected else { return }
            guard case .failed(.offline) = self?.firstLaunchState else { return }
            Task { @MainActor [weak self] in
                await self?.retryFirstLaunch()
            }
        }

        loadCachedGrammar()

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
            case let .updated(manifest, fetchedVerbs):
                try persisting.replaceAllVerbs(with: fetchedVerbs)
                // Only record the manifest as synced once persistence has
                // actually succeeded — otherwise a persistence failure
                // here would be caught below (leaving the manifest
                // unrecorded) and a retry could genuinely re-fetch,
                // instead of seeing `.upToDate` forever.
                syncService.confirmSynced(manifest)
                verbs = fetchedVerbs
                firstLaunchState = .success
                // Verbs are the gate; grammar follows once they're in.
                await syncGrammar()
            }
        } catch let error as VerbSyncError {
            firstLaunchState = .failed(error)
        } catch {
            firstLaunchState = .failed(.malformedData)
        }
    }

    private func syncInBackground() async {
        guard let result = try? await syncService.sync() else { return }
        guard case let .updated(manifest, fetchedVerbs) = result else { return }
        do {
            try persisting.replaceAllVerbs(with: fetchedVerbs)
        } catch {
            // Persistence failed — leave the manifest unrecorded so the
            // next sync (foreground or background) still sees this as
            // changed and retries, instead of reporting `.upToDate` with
            // nothing actually saved.
            return
        }
        syncService.confirmSynced(manifest)
        verbs = fetchedVerbs
    }

    private func loadCachedGrammar() {
        guard let grammarPersisting,
              let cached = try? grammarPersisting.loadAllGrammarPoints() else { return }
        grammarPoints = cached
    }

    /// Same contract as the verb sync: persist first, and only then
    /// confirm the manifest, so a persistence failure leaves it
    /// unrecorded and the next sync genuinely retries. Every failure
    /// here is silent and never touches `verbs` or `firstLaunchState`.
    private func syncGrammar() async {
        guard let grammarSyncService, let grammarPersisting else { return }
        guard let result = try? await grammarSyncService.sync() else { return }
        guard case let .updated(manifest, points) = result else { return }
        do {
            try grammarPersisting.replaceAllGrammarPoints(with: points)
        } catch {
            return
        }
        grammarSyncService.confirmSynced(manifest)
        grammarPoints = points
    }
}
