import XCTest
import SwiftData
@testable import VerbKit

@MainActor
final class VerbStoreGrammarTests: XCTestCase {
    private func verbData() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "verbs-fixture", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private struct Harness {
        let store: VerbStore
        let fetcher: MockVerbDataFetcher
        let verbPersisting: SwiftDataVerbPersisting
        let grammarPersisting: SwiftDataGrammarPersisting
        let syncState: InMemorySyncStateStore
    }

    /// A store wired for both verbs and grammar, with both syncs succeeding
    /// unless a test changes the mock.
    private func makeHarness() throws -> Harness {
        let verbBytes = try verbData()
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .success(VerbManifest(version: "1.0.0", sha256: sha256Hex(of: verbBytes)))
        fetcher.verbDataResult = .success(verbBytes)
        fetcher.grammarManifestResult = .success(GrammarManifest(version: "1.0.0", sha256: sha256Hex(of: GrammarFixture.data)))
        fetcher.grammarDataResult = .success(GrammarFixture.data)

        let container = try VerbModelContainer.makeInMemory()
        let context = ModelContext(container)
        let verbPersisting = SwiftDataVerbPersisting(modelContext: context)
        let grammarPersisting = SwiftDataGrammarPersisting(modelContext: context)
        let syncState = InMemorySyncStateStore()
        let store = VerbStore(
            syncService: VerbSyncService(fetcher: fetcher, syncState: syncState),
            persisting: verbPersisting,
            networkMonitor: NetworkMonitor(),
            grammarSyncService: GrammarSyncService(fetcher: fetcher, syncState: syncState),
            grammarPersisting: grammarPersisting
        )
        return Harness(store: store, fetcher: fetcher, verbPersisting: verbPersisting, grammarPersisting: grammarPersisting, syncState: syncState)
    }

    func testFirstLaunchSyncsGrammarAfterVerbs() async throws {
        let h = try makeHarness()

        await h.store.start()

        XCTAssertEqual(h.store.firstLaunchState, .success)
        XCTAssertEqual(h.store.grammarPoints.map(\.id), ["n-desu", "wake-desu"])
        XCTAssertTrue(h.store.hasGrammar)
        XCTAssertEqual(try h.grammarPersisting.loadAllGrammarPoints().count, 2)
    }

    func testGrammarFailureNeverAffectsVerbs() async throws {
        let h = try makeHarness()
        h.fetcher.grammarManifestResult = .failure(VerbSyncError.serverUnreachable)

        await h.store.start()

        XCTAssertEqual(h.store.firstLaunchState, .success)
        XCTAssertEqual(h.store.verbs.count, 2)
        XCTAssertTrue(h.store.grammarPoints.isEmpty)
        XCTAssertFalse(h.store.hasGrammar)
    }

    func testGrammarIsNotAttemptedWhenTheVerbFetchFails() async throws {
        let h = try makeHarness()
        h.fetcher.manifestResult = .failure(VerbSyncError.offline)

        await h.store.start()

        XCTAssertEqual(h.store.firstLaunchState, .failed(.offline))
        XCTAssertTrue(h.store.grammarPoints.isEmpty)
    }

    func testCachedGrammarLoadsEvenWhenOffline() async throws {
        let h = try makeHarness()
        try h.verbPersisting.replaceAllVerbs(with: JSONDecoder().decode(VerbDataFile.self, from: verbData()).verbs)
        try h.grammarPersisting.replaceAllGrammarPoints(with: GrammarFixture.points)
        h.fetcher.manifestResult = .failure(VerbSyncError.offline)
        h.fetcher.grammarManifestResult = .failure(VerbSyncError.offline)

        await h.store.start()

        XCTAssertEqual(h.store.grammarPoints.map(\.id), ["n-desu", "wake-desu"])
        XCTAssertEqual(h.store.verbs.count, 2)
    }

    func testCachedVerbsPathSyncsGrammarInTheBackground() async throws {
        let h = try makeHarness()
        try h.verbPersisting.replaceAllVerbs(with: JSONDecoder().decode(VerbDataFile.self, from: verbData()).verbs)

        await h.store.start()

        XCTAssertEqual(h.store.grammarPoints.count, 2)
    }

    func testRetryGrammarSyncRecoversAfterAFailure() async throws {
        let h = try makeHarness()
        h.fetcher.grammarManifestResult = .failure(VerbSyncError.offline)
        await h.store.start()
        XCTAssertTrue(h.store.grammarPoints.isEmpty)

        h.fetcher.grammarManifestResult = .success(GrammarManifest(version: "1.0.0", sha256: sha256Hex(of: GrammarFixture.data)))
        await h.store.retryGrammarSync()

        XCTAssertEqual(h.store.grammarPoints.count, 2)
    }

    // MARK: persistence failure (same contract as verbs)

    func testGrammarPersistenceFailureLeavesManifestUnconfirmedSoRetryRefetches() async throws {
        let entry = GrammarManifest(version: "1.0.0", sha256: sha256Hex(of: GrammarFixture.data))
        let verbBytes = try verbData()
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .success(VerbManifest(version: "1.0.0", sha256: sha256Hex(of: verbBytes)))
        fetcher.verbDataResult = .success(verbBytes)
        fetcher.grammarManifestResult = .success(entry)
        fetcher.grammarDataResult = .success(GrammarFixture.data)

        let container = try VerbModelContainer.makeInMemory()
        let syncState = InMemorySyncStateStore()
        let grammarPersisting = FailingGrammarPersisting(shouldFail: true)
        let store = VerbStore(
            syncService: VerbSyncService(fetcher: fetcher, syncState: syncState),
            persisting: SwiftDataVerbPersisting(modelContext: ModelContext(container)),
            networkMonitor: NetworkMonitor(),
            grammarSyncService: GrammarSyncService(fetcher: fetcher, syncState: syncState),
            grammarPersisting: grammarPersisting
        )

        await store.start()

        // Verbs are unaffected, and the failed grammar persist is not
        // recorded as synced.
        XCTAssertEqual(store.firstLaunchState, .success)
        XCTAssertEqual(store.verbs.count, 2)
        XCTAssertTrue(store.grammarPoints.isEmpty)
        XCTAssertNil(syncState.lastSyncedGrammarManifest())

        // Once persistence works again, a retry must really re-fetch
        // instead of short-circuiting to "up to date".
        grammarPersisting.shouldFail = false
        await store.retryGrammarSync()

        XCTAssertEqual(store.grammarPoints.count, 2)
        XCTAssertEqual(syncState.lastSyncedGrammarManifest(), entry)
    }

    func testSuccessfulGrammarSyncConfirmsTheManifestAfterPersisting() async throws {
        let h = try makeHarness()
        let entry = GrammarManifest(version: "1.0.0", sha256: sha256Hex(of: GrammarFixture.data))

        await h.store.start()

        XCTAssertEqual(h.syncState.lastSyncedGrammarManifest(), entry)
        XCTAssertEqual(try h.grammarPersisting.loadAllGrammarPoints().count, 2)
    }

    func testStoreWithoutGrammarDependenciesIgnoresGrammar() async throws {
        let verbBytes = try verbData()
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .success(VerbManifest(version: "1.0.0", sha256: sha256Hex(of: verbBytes)))
        fetcher.verbDataResult = .success(verbBytes)
        let container = try VerbModelContainer.makeInMemory()
        let store = VerbStore(
            syncService: VerbSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore()),
            persisting: SwiftDataVerbPersisting(modelContext: ModelContext(container)),
            networkMonitor: NetworkMonitor()
        )

        await store.start()
        await store.retryGrammarSync()

        XCTAssertEqual(store.verbs.count, 2)
        XCTAssertTrue(store.grammarPoints.isEmpty)
    }
}

/// A `GrammarPersisting` whose `replaceAllGrammarPoints(with:)` can be made
/// to throw on demand, to simulate a persistence failure.
private enum FailingGrammarPersistingError: Error {
    case persistFailed
}

@MainActor
private final class FailingGrammarPersisting: GrammarPersisting {
    var shouldFail: Bool
    private var stored: [GrammarPoint] = []

    init(shouldFail: Bool) {
        self.shouldFail = shouldFail
    }

    func loadAllGrammarPoints() throws -> [GrammarPoint] { stored }

    func replaceAllGrammarPoints(with points: [GrammarPoint]) throws {
        if shouldFail { throw FailingGrammarPersistingError.persistFailed }
        stored = points
    }
}
