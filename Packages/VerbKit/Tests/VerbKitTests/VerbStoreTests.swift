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
