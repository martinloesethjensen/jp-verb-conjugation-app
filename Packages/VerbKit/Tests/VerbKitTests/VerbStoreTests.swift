import XCTest
import SwiftData
@testable import VerbKit

@MainActor
final class VerbStoreTests: XCTestCase {
    private func fixtureData() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "verbs-fixture", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func makePersisting() throws -> SwiftDataVerbPersisting {
        let container = try VerbModelContainer.makeInMemory()
        return SwiftDataVerbPersisting(modelContext: ModelContext(container))
    }

    func testFirstLaunchSuccessPopulatesVerbsAndPersists() async throws {
        let data = try fixtureData()
        let manifest = VerbManifest(version: "1.0.0", sha256: sha256Hex(of: data))
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .success(manifest)
        fetcher.verbDataResult = .success(data)

        let persisting = try makePersisting()
        let syncService = VerbSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore())
        let store = VerbStore(syncService: syncService, persisting: persisting, networkMonitor: NetworkMonitor())

        await store.start()

        XCTAssertEqual(store.firstLaunchState, .success)
        XCTAssertEqual(store.verbs.count, 2)
        XCTAssertTrue(store.hasLocalData)
        XCTAssertEqual(try persisting.loadAllVerbs().count, 2)
    }

    func testFirstLaunchOfflineFailureSetsFailedState() async throws {
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .failure(VerbSyncError.offline)

        let syncService = VerbSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore())
        let store = VerbStore(syncService: syncService, persisting: try makePersisting(), networkMonitor: NetworkMonitor())

        await store.start()

        XCTAssertEqual(store.firstLaunchState, .failed(.offline))
        XCTAssertTrue(store.verbs.isEmpty)
    }

    func testFirstLaunchServerUnreachableFailureSetsFailedState() async throws {
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .failure(VerbSyncError.serverUnreachable)

        let syncService = VerbSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore())
        let store = VerbStore(syncService: syncService, persisting: try makePersisting(), networkMonitor: NetworkMonitor())

        await store.start()

        XCTAssertEqual(store.firstLaunchState, .failed(.serverUnreachable))
    }

    func testManualRetryAfterFailureCanSucceed() async throws {
        let data = try fixtureData()
        let manifest = VerbManifest(version: "1.0.0", sha256: sha256Hex(of: data))
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .failure(VerbSyncError.offline)

        let syncService = VerbSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore())
        let store = VerbStore(syncService: syncService, persisting: try makePersisting(), networkMonitor: NetworkMonitor())

        await store.start()
        XCTAssertEqual(store.firstLaunchState, .failed(.offline))

        fetcher.manifestResult = .success(manifest)
        fetcher.verbDataResult = .success(data)
        await store.retryFirstLaunch()

        XCTAssertEqual(store.firstLaunchState, .success)
        XCTAssertEqual(store.verbs.count, 2)
    }

    func testReconnectCallbackRetriesAfterOfflineFailure() async throws {
        let data = try fixtureData()
        let manifest = VerbManifest(version: "1.0.0", sha256: sha256Hex(of: data))
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .failure(VerbSyncError.offline)

        let syncService = VerbSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore())
        let networkMonitor = NetworkMonitor()
        let store = VerbStore(syncService: syncService, persisting: try makePersisting(), networkMonitor: networkMonitor)

        await store.start()
        XCTAssertEqual(store.firstLaunchState, .failed(.offline))

        fetcher.manifestResult = .success(manifest)
        fetcher.verbDataResult = .success(data)

        // NetworkMonitor's real NWPathMonitor was never started (VerbStore
        // only assigns onChange, doesn't call start()), so this manual
        // call is the only thing that can trigger it here — deterministic.
        networkMonitor.onChange?(true)
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(store.firstLaunchState, .success)
    }

    func testFirstLaunchPersistenceFailureLeavesManifestUnsavedSoRetryCanRefetch() async throws {
        // Important #4 of the final whole-branch review: if persistence
        // fails on first launch, the manifest must NOT be recorded as
        // synced — otherwise every later retry sees `.upToDate` with no
        // verbs ever persisted, and the user is stuck forever.
        let data = try fixtureData()
        let manifest = VerbManifest(version: "1.0.0", sha256: sha256Hex(of: data))
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .success(manifest)
        fetcher.verbDataResult = .success(data)

        let syncState = InMemorySyncStateStore()
        let syncService = VerbSyncService(fetcher: fetcher, syncState: syncState)
        let persisting = FailingVerbPersisting(shouldFail: true)
        let store = VerbStore(syncService: syncService, persisting: persisting, networkMonitor: NetworkMonitor())

        await store.start()

        XCTAssertTrue(store.verbs.isEmpty)
        guard case .failed = store.firstLaunchState else {
            return XCTFail("expected a failed state when persistence throws")
        }
        XCTAssertNil(syncState.lastSyncedManifest(), "manifest must stay unrecorded when persistence fails")

        // Fix the persistence layer and retry: since the manifest was
        // never recorded, sync() must actually re-fetch and succeed
        // rather than short-circuiting to `.upToDate`.
        persisting.shouldFail = false
        await store.retryFirstLaunch()

        XCTAssertEqual(store.firstLaunchState, .success)
        XCTAssertEqual(store.verbs.count, 2)
        XCTAssertEqual(syncState.lastSyncedManifest(), manifest)
    }

    func testBackgroundSyncPersistenceFailureLeavesManifestUnsavedAndVerbsUnchanged() async throws {
        let seedVerb = Verb(
            type: .u, label: "U-verb", dict: "のむ", kanji: nil, meaning: "to drink", description: "d",
            forms: VerbForms(masuPos: "a", masuNeg: "b", masuPast: "c", masuPastNeg: "d", te: "e", shortPos: "f", shortNeg: "g", shortPast: "h", shortPastNeg: "i"),
            examples: []
        )
        let persisting = FailingVerbPersisting(initialVerbs: [seedVerb], shouldFail: true)

        let data = try fixtureData()
        let manifest = VerbManifest(version: "2.0.0", sha256: sha256Hex(of: data))
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .success(manifest)
        fetcher.verbDataResult = .success(data)

        let syncState = InMemorySyncStateStore()
        let syncService = VerbSyncService(fetcher: fetcher, syncState: syncState)
        let store = VerbStore(syncService: syncService, persisting: persisting, networkMonitor: NetworkMonitor())

        // Cached path: loads seedVerb locally, then syncInBackground()
        // fetches a changed manifest but fails to persist it.
        await store.start()

        XCTAssertEqual(store.verbs.map(\.dict), [seedVerb.dict], "in-memory verbs must stay untouched when the background persist fails")
        XCTAssertNil(syncState.lastSyncedManifest(), "manifest must stay unrecorded so a later sync retries instead of reporting up to date")
    }

    func testExistingLocalDataSkipsFirstLaunchFlowAndSyncsInBackground() async throws {
        let persisting = try makePersisting()
        let seedVerb = Verb(
            type: .u, label: "U-verb", dict: "のむ", kanji: nil, meaning: "to drink", description: "d",
            forms: VerbForms(masuPos: "a", masuNeg: "b", masuPast: "c", masuPastNeg: "d", te: "e", shortPos: "f", shortNeg: "g", shortPast: "h", shortPastNeg: "i"),
            examples: []
        )
        try persisting.replaceAllVerbs(with: [seedVerb])

        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .failure(VerbSyncError.offline) // background sync fails silently
        let syncService = VerbSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore())
        let store = VerbStore(syncService: syncService, persisting: persisting, networkMonitor: NetworkMonitor())

        await store.start()

        XCTAssertEqual(store.verbs.map(\.dict), ["のむ"])
        XCTAssertEqual(store.firstLaunchState, .checking) // first-launch flow never entered
    }
}

/// A `VerbPersisting` mock whose `replaceAllVerbs(with:)` can be made to
/// throw on demand, so tests can simulate a persistence failure (e.g. the
/// in-memory SwiftData fallback being in use because the real App Group
/// container isn't available) independently of the real SwiftData stack.
private enum FailingVerbPersistingError: Error {
    case persistFailed
}

@MainActor
private final class FailingVerbPersisting: VerbPersisting {
    var shouldFail: Bool
    private var stored: [Verb]

    init(initialVerbs: [Verb] = [], shouldFail: Bool) {
        self.stored = initialVerbs
        self.shouldFail = shouldFail
    }

    func loadAllVerbs() throws -> [Verb] { stored }

    func replaceAllVerbs(with verbs: [Verb]) throws {
        if shouldFail { throw FailingVerbPersistingError.persistFailed }
        stored = verbs
    }
}
