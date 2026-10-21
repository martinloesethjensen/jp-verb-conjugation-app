import XCTest
import SwiftData
@testable import VerbKit

/// The stores report each sync to `DataSyncStatus`, and `refresh()` checks again.
@MainActor
final class StoreSyncStatusTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "StoreSyncStatusTests"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func verbData() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "verbs-fixture", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private struct VerbHarness {
        let store: VerbStore
        let fetcher: MockVerbDataFetcher
        let status: DataSyncStatus
    }

    private func makeVerbHarness(verbPersisting: VerbPersisting? = nil) throws -> VerbHarness {
        let verbBytes = try verbData()
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .success(VerbManifest(version: "1.0.0", sha256: sha256Hex(of: verbBytes)))
        fetcher.verbDataResult = .success(verbBytes)
        fetcher.grammarManifestResult = .success(GrammarManifest(version: "2.0.0", sha256: sha256Hex(of: GrammarFixture.data)))
        fetcher.grammarDataResult = .success(GrammarFixture.data)

        let context = ModelContext(try VerbModelContainer.makeInMemory())
        let syncState = InMemorySyncStateStore()
        let status = DataSyncStatus(defaults: defaults)
        let store = VerbStore(
            syncService: VerbSyncService(fetcher: fetcher, syncState: syncState),
            persisting: verbPersisting ?? SwiftDataVerbPersisting(modelContext: context),
            networkMonitor: NetworkMonitor(),
            grammarSyncService: GrammarSyncService(fetcher: fetcher, syncState: syncState),
            grammarPersisting: SwiftDataGrammarPersisting(modelContext: context),
            syncStatus: status
        )
        return VerbHarness(store: store, fetcher: fetcher, status: status)
    }

    func testFirstLaunchRecordsVerbsAndGrammarVersions() async throws {
        let h = try makeVerbHarness()

        await h.store.start()

        XCTAssertEqual(h.status.status(for: .verbs).version, "1.0.0")
        XCTAssertEqual(h.status.status(for: .grammar).version, "2.0.0")
        XCTAssertNotNil(h.status.status(for: .verbs).lastUpdated)
        XCTAssertNil(h.status.status(for: .verbs).problem)
    }

    func testFirstLaunchFailureIsRecorded() async throws {
        let h = try makeVerbHarness()
        h.fetcher.manifestResult = .failure(VerbSyncError.offline)

        await h.store.start()

        XCTAssertEqual(h.status.status(for: .verbs).problem, .offline)
        XCTAssertFalse(h.status.status(for: .verbs).hasData)
    }

    func testRefreshPicksUpANewVersion() async throws {
        let h = try makeVerbHarness()
        await h.store.start()

        let bytes = try verbData()
        h.fetcher.manifestResult = .success(VerbManifest(version: "1.1.0", sha256: sha256Hex(of: bytes)))
        await h.store.refresh()

        XCTAssertEqual(h.status.status(for: .verbs).version, "1.1.0")
        XCTAssertEqual(h.status.status(for: .grammar).version, "2.0.0")
    }

    func testRefreshWithNothingNewIsUpToDate() async throws {
        let h = try makeVerbHarness()
        await h.store.start()
        let checked = try XCTUnwrap(h.status.status(for: .verbs).lastChecked)

        await h.store.refresh()

        XCTAssertGreaterThanOrEqual(try XCTUnwrap(h.status.status(for: .verbs).lastChecked), checked)
        XCTAssertNil(h.status.status(for: .verbs).problem)
        XCTAssertEqual(h.status.status(for: .verbs).version, "1.0.0")
    }

    func testAnUntrustedManifestOnRefreshKeepsTheCurrentVerbs() async throws {
        let h = try makeVerbHarness()
        await h.store.start()

        h.fetcher.manifestResult = .failure(VerbSyncError.untrusted)
        h.fetcher.grammarManifestResult = .failure(VerbSyncError.untrusted)
        await h.store.refresh()

        XCTAssertEqual(h.store.verbs.count, 2)
        XCTAssertEqual(h.status.status(for: .verbs).problem, .untrusted)
        XCTAssertEqual(h.status.status(for: .grammar).problem, .untrusted)
        XCTAssertEqual(h.status.status(for: .verbs).version, "1.0.0")
    }

    func testRefreshWithoutVerbsRetriesTheFirstLaunch() async throws {
        let h = try makeVerbHarness()
        h.fetcher.manifestResult = .failure(VerbSyncError.serverUnreachable)
        await h.store.start()
        XCTAssertEqual(h.store.firstLaunchState, .failed(.serverUnreachable))

        let bytes = try verbData()
        h.fetcher.manifestResult = .success(VerbManifest(version: "1.0.0", sha256: sha256Hex(of: bytes)))
        await h.store.refresh()

        XCTAssertEqual(h.store.firstLaunchState, .success)
        XCTAssertEqual(h.status.status(for: .verbs).version, "1.0.0")
        XCTAssertNil(h.status.status(for: .verbs).problem)
    }

    func testAFailedSaveIsRecordedAsCouldNotSave() async throws {
        let h = try makeVerbHarness(verbPersisting: AlwaysFailingVerbPersisting())

        await h.store.start()

        XCTAssertEqual(h.status.status(for: .verbs).problem, .couldNotSave)
        XCTAssertNil(h.status.status(for: .verbs).version)
    }

    func testFuriganaStoreReportsAndRefreshes() async throws {
        let fetcher = MockVerbDataFetcher()
        fetcher.furiganaManifestResult = .failure(VerbSyncError.malformedData)
        let status = DataSyncStatus(defaults: defaults)
        let store = FuriganaStore(
            syncService: FuriganaSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore()),
            persisting: SwiftDataFuriganaPersisting(modelContext: ModelContext(try VerbModelContainer.makeInMemory())),
            syncStatus: status
        )

        await store.start()
        XCTAssertEqual(status.status(for: .furigana).problem, .damaged)

        fetcher.furiganaManifestResult = .success(FuriganaManifest(version: "1.0.0", sha256: sha256Hex(of: FuriganaFixture.data)))
        fetcher.furiganaDataResult = .success(FuriganaFixture.data)
        await store.refresh()

        XCTAssertEqual(status.status(for: .furigana).version, "1.0.0")
        XCTAssertNil(status.status(for: .furigana).problem)
        XCTAssertNotNil(store.dictionary)
    }

    func testWordsStoreReportsAndRefreshes() async throws {
        let data = Data(WordsSyncTests.json.utf8)
        let fetcher = MockVerbDataFetcher()
        fetcher.wordsManifestResult = .failure(VerbSyncError.offline)
        let status = DataSyncStatus(defaults: defaults)
        let store = WordsStore(
            syncService: WordsSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore()),
            persisting: SwiftDataWordsPersisting(modelContext: ModelContext(try VerbModelContainer.makeInMemory())),
            syncStatus: status
        )

        await store.start()
        XCTAssertEqual(status.status(for: .words).problem, .offline)

        fetcher.wordsManifestResult = .success(WordsManifest(version: "1.0.0", sha256: sha256Hex(of: data)))
        fetcher.wordsDataResult = .success(data)
        await store.refresh()

        XCTAssertEqual(status.status(for: .words).version, "1.0.0")
        XCTAssertEqual(store.words.count, 2)
    }

    func testCountersStoreReportsAndRefreshes() async throws {
        let data = Data(CountersSyncTests.json.utf8)
        let fetcher = MockVerbDataFetcher()
        fetcher.countersManifestResult = .failure(VerbSyncError.serverUnreachable)
        let status = DataSyncStatus(defaults: defaults)
        let store = CountersStore(
            syncService: CountersSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore()),
            persisting: SwiftDataCountersPersisting(modelContext: ModelContext(try VerbModelContainer.makeInMemory())),
            syncStatus: status
        )

        await store.start()
        XCTAssertEqual(status.status(for: .counters).problem, .serverUnreachable)

        fetcher.countersManifestResult = .success(CountersManifest(version: "1.0.0", sha256: sha256Hex(of: data)))
        fetcher.countersDataResult = .success(data)
        await store.refresh()

        XCTAssertEqual(status.status(for: .counters).version, "1.0.0")
        XCTAssertEqual(store.counters.map(\.id), ["hon"])
    }

    func testAnUnpublishedFileCountsAsCheckedWithNoData() async throws {
        let status = DataSyncStatus(defaults: defaults)
        let store = CountersStore(
            syncService: CountersSyncService(fetcher: MockVerbDataFetcher(), syncState: InMemorySyncStateStore()),
            persisting: SwiftDataCountersPersisting(modelContext: ModelContext(try VerbModelContainer.makeInMemory())),
            syncStatus: status
        )

        await store.start()

        XCTAssertNotNil(status.status(for: .counters).lastChecked)
        XCTAssertNil(status.status(for: .counters).version)
        XCTAssertNil(status.status(for: .counters).problem)
    }
}

private struct SaveFailed: Error {}

@MainActor
private final class AlwaysFailingVerbPersisting: VerbPersisting {
    func loadAllVerbs() throws -> [Verb] { [] }
    func replaceAllVerbs(with verbs: [Verb]) throws { throw SaveFailed() }
}
