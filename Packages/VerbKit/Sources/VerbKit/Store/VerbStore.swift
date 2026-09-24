import Observation

@MainActor
@Observable
public final class VerbStore {
    public private(set) var verbs: [Verb] = []
    public private(set) var firstLaunchState: FirstLaunchState = .checking
    public var hasLocalData: Bool { !verbs.isEmpty }

    private let syncService: VerbSyncService
    private let persisting: VerbPersisting
    private let networkMonitor: NetworkMonitor

    public init(syncService: VerbSyncService, persisting: VerbPersisting, networkMonitor: NetworkMonitor) {
        self.syncService = syncService
        self.persisting = persisting
        self.networkMonitor = networkMonitor
    }

    public func start() async {
        networkMonitor.onChange = { [weak self] connected in
            guard connected else { return }
            guard case .failed(.offline) = self?.firstLaunchState else { return }
            Task { @MainActor [weak self] in
                await self?.retryFirstLaunch()
            }
        }

        if let cached = try? persisting.loadAllVerbs(), !cached.isEmpty {
            verbs = cached
            await syncInBackground()
            return
        }

        await runFirstLaunchFetch()
    }

    public func retryFirstLaunch() async {
        await runFirstLaunchFetch()
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
            case let .updated(_, fetchedVerbs):
                try persisting.replaceAllVerbs(with: fetchedVerbs)
                verbs = fetchedVerbs
                firstLaunchState = .success
            }
        } catch let error as VerbSyncError {
            firstLaunchState = .failed(error)
        } catch {
            firstLaunchState = .failed(.malformedData)
        }
    }

    private func syncInBackground() async {
        guard let result = try? await syncService.sync() else { return }
        if case let .updated(_, fetchedVerbs) = result {
            try? persisting.replaceAllVerbs(with: fetchedVerbs)
            verbs = fetchedVerbs
        }
    }
}
