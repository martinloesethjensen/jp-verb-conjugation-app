import XCTest
import SwiftData
@testable import VerbKit

@MainActor
final class CountersStoreTests: XCTestCase {
    private var data: Data { Data(CountersSyncTests.json.utf8) }

    private func fetcher() -> MockVerbDataFetcher {
        let fetcher = MockVerbDataFetcher()
        fetcher.countersManifestResult = .success(CountersManifest(version: "1.0.0", sha256: sha256Hex(of: data)))
        fetcher.countersDataResult = .success(data)
        return fetcher
    }

    private func makeStore(
        fetcher: MockVerbDataFetcher, state: InMemorySyncStateStore = InMemorySyncStateStore(),
        persisting: CountersPersisting, bundled: BundledData<CountersDataFile>? = nil
    ) -> CountersStore {
        CountersStore(
            syncService: CountersSyncService(fetcher: fetcher, syncState: state),
            persisting: persisting, bundled: bundled
        )
    }

    private func bundled(version: String = "1.0.0", ids: [String] = ["b1", "b2"]) -> BundledData<CountersDataFile> {
        BundledData(
            value: SwiftDataCountersPersistingTests.file(ids: ids), version: version, sha256: "bundled", data: Data()
        )
    }

    /// Counts replaces and can be told to fail them.
    private final class RecordingCountersPersisting: CountersPersisting {
        let base: CountersPersisting
        var replaces = 0
        var fail = false
        init(_ base: CountersPersisting) { self.base = base }
        func loadCounters() throws -> CountersDataFile? { try base.loadCounters() }
        func replaceCounters(with file: CountersDataFile) throws {
            replaces += 1
            if fail { throw VerbSyncError.malformedData }
            try base.replaceCounters(with: file)
        }
    }

    private func offline() -> MockVerbDataFetcher {
        let fetcher = MockVerbDataFetcher()
        fetcher.countersManifestResult = .failure(VerbSyncError.offline)
        return fetcher
    }

    private func persisting() throws -> SwiftDataCountersPersisting {
        SwiftDataCountersPersisting(modelContext: ModelContext(try VerbModelContainer.makeInMemory()))
    }

    func testStoreSyncsPersistsAndPublishes() async throws {
        let persisting = try persisting()
        let store = makeStore(fetcher: fetcher(), persisting: persisting)
        XCTAssertTrue(store.counters.isEmpty)
        await store.start()
        XCTAssertEqual(store.counters.map(\.id), ["hon"])
        XCTAssertEqual(store.groups.map(\.id), ["long"])
        XCTAssertEqual(store.counter(id: "hon")?.counter, "本")
        XCTAssertEqual(store.group(id: "long")?.title, "Long things")
        XCTAssertNil(store.counter(id: "nope"))
        XCTAssertEqual(try persisting.loadCounters()?.counters.count, 1)
    }

    func testTheCachedCopyLoadsBeforeSyncAndWithoutNetwork() async throws {
        let persisting = try persisting()
        try persisting.replaceCounters(with: SwiftDataCountersPersistingTests.file(ids: ["cached"]))
        let store = makeStore(fetcher: MockVerbDataFetcher(), persisting: persisting)
        await store.start()
        XCTAssertEqual(store.counters.map(\.id), ["cached"])
        XCTAssertEqual(store.groups.map(\.id), ["g"])
    }

    func testAFailedSaveDoesNotConfirm() async throws {
        struct FailingPersisting: CountersPersisting {
            func loadCounters() throws -> CountersDataFile? { nil }
            func replaceCounters(with file: CountersDataFile) throws { throw VerbSyncError.offline }
        }
        let state = InMemorySyncStateStore()
        let store = makeStore(fetcher: fetcher(), state: state, persisting: FailingPersisting())
        await store.start()
        XCTAssertNil(state.lastSyncedCountersManifest())
        XCTAssertTrue(store.counters.isEmpty)
    }

    func testEveryFailureIsSilent() async throws {
        let failing = MockVerbDataFetcher()
        failing.countersManifestResult = .failure(VerbSyncError.offline)
        let store = makeStore(fetcher: failing, persisting: try persisting())
        await store.start()
        XCTAssertTrue(store.counters.isEmpty)
    }

    func testRelatedCountersResolveInTheirListedOrder() throws {
        var hon = SwiftDataCountersPersistingTests.file(ids: ["hon", "hai", "hiki"]).counters[0]
        hon.related = ["hiki", "missing", "hai"]
        let file = CountersDataFile(
            version: "1", description: "d",
            counters: [hon] + SwiftDataCountersPersistingTests.file(ids: ["hai", "hiki"]).counters
        )
        let persisting = try persisting()
        try persisting.replaceCounters(with: file)
        let store = makeStore(fetcher: MockVerbDataFetcher(), persisting: persisting)
        let expectation = expectation(description: "started")
        Task { await store.start(); expectation.fulfill() }
        wait(for: [expectation], timeout: 5)
        XCTAssertEqual(store.related(to: hon).map(\.id), ["hiki", "hai"])
    }

    func testSectionsFallBackToTheGroupsWhenTheFileHasNone() async throws {
        let persisting = try persisting()
        try persisting.replaceCounters(with: SwiftDataCountersPersistingTests.file(ids: ["a", "b"]))
        let store = makeStore(fetcher: MockVerbDataFetcher(), persisting: persisting)
        await store.start()
        XCTAssertEqual(store.sections, [CounterSection(id: "g", title: "G", counters: ["a", "b"])])
    }

    func testTheFilesSectionsWinOverGroupsAndSurviveTheCache() async throws {
        var file = SwiftDataCountersPersistingTests.file(ids: ["a", "b"])
        file.sections = [CounterSection(id: "s", title: "S", counters: ["b"])]
        let persisting = try persisting()
        try persisting.replaceCounters(with: file)
        let store = makeStore(fetcher: MockVerbDataFetcher(), persisting: persisting)
        await store.start()
        XCTAssertEqual(store.sections.map(\.id), ["s"])
    }

    // MARK: the bundled copy

    func testAFirstLaunchWithoutNetworkShowsAndPersistsTheBundledCounters() async throws {
        let persisting = try persisting()
        let state = InMemorySyncStateStore()
        let store = makeStore(fetcher: offline(), state: state, persisting: persisting, bundled: bundled())
        await store.start()
        XCTAssertEqual(store.counters.map(\.id), ["b1", "b2"])
        XCTAssertEqual(store.groups.map(\.id), ["g"])
        XCTAssertEqual(try persisting.loadCounters()?.counters.map(\.id), ["b1", "b2"], "the widget reads the persisted store")
        XCTAssertEqual(state.highestAcceptedVersion(for: "counters"), "1.0.0")
        XCTAssertEqual(state.lastSyncedCountersManifest()?.version, "1.0.0")
    }

    func testANewerBundleReplacesTheCacheOnce() async throws {
        let persisting = RecordingCountersPersisting(try persisting())
        try persisting.base.replaceCounters(with: SwiftDataCountersPersistingTests.file(ids: ["stale"]))
        let state = InMemorySyncStateStore()
        state.saveHighestAcceptedVersion("0.9.0", for: "counters")
        let store = makeStore(fetcher: offline(), state: state, persisting: persisting, bundled: bundled())
        await store.start()
        XCTAssertEqual(store.counters.map(\.id), ["b1", "b2"])
        XCTAssertEqual(persisting.replaces, 1)
    }

    func testANewerCacheWinsOverTheBundle() async throws {
        let persisting = RecordingCountersPersisting(try persisting())
        try persisting.base.replaceCounters(with: SwiftDataCountersPersistingTests.file(ids: ["cached"]))
        let state = InMemorySyncStateStore()
        state.saveHighestAcceptedVersion("1.5.0", for: "counters")
        let store = makeStore(fetcher: offline(), state: state, persisting: persisting, bundled: bundled())
        await store.start()
        XCTAssertEqual(store.counters.map(\.id), ["cached"])
        XCTAssertEqual(persisting.replaces, 0)
        XCTAssertEqual(state.highestAcceptedVersion(for: "counters"), "1.5.0")
    }

    func testAnEqualVersionDoesNotReinstall() async throws {
        let persisting = RecordingCountersPersisting(try persisting())
        try persisting.base.replaceCounters(with: SwiftDataCountersPersistingTests.file(ids: ["cached"]))
        let state = InMemorySyncStateStore()
        state.saveHighestAcceptedVersion("1.0.0", for: "counters")
        let store = makeStore(fetcher: offline(), state: state, persisting: persisting, bundled: bundled())
        await store.start()
        XCTAssertEqual(store.counters.map(\.id), ["cached"])
        XCTAssertEqual(persisting.replaces, 0)
    }

    func testAFailedInstallKeepsTheCacheAndRecordsNothing() async throws {
        let persisting = RecordingCountersPersisting(try persisting())
        try persisting.base.replaceCounters(with: SwiftDataCountersPersistingTests.file(ids: ["old"]))
        persisting.fail = true
        let state = InMemorySyncStateStore()
        let store = makeStore(fetcher: offline(), state: state, persisting: persisting, bundled: bundled())
        await store.start()
        XCTAssertEqual(store.counters.map(\.id), ["old"])
        XCTAssertNil(state.highestAcceptedVersion(for: "counters"))
        XCTAssertNil(state.lastSyncedCountersManifest())
    }

    func testASyncNewerThanTheBundleReplacesIt() async throws {
        let store = makeStore(fetcher: fetcher(), persisting: try persisting(), bundled: bundled(version: "0.5.0"))
        await store.start()
        XCTAssertEqual(store.counters.map(\.id), ["hon"])
    }

    func testARemoteEqualToTheInstalledBundleDownloadsNothing() async throws {
        let fetcher = fetcher()
        let store = makeStore(
            fetcher: fetcher, persisting: try persisting(),
            bundled: BundledData(
                value: SwiftDataCountersPersistingTests.file(ids: ["b1"]), version: "1.0.0",
                sha256: sha256Hex(of: data), data: Data()
            )
        )
        await store.start()
        XCTAssertEqual(store.counters.map(\.id), ["b1"])
        XCTAssertEqual(fetcher.countersDataFetches, 0)
    }

    func testWithoutABundleACacheIsUsedAsBefore() async throws {
        let persisting = try persisting()
        try persisting.replaceCounters(with: SwiftDataCountersPersistingTests.file(ids: ["cached"]))
        let store = makeStore(fetcher: offline(), persisting: persisting)
        await store.start()
        XCTAssertEqual(store.counters.map(\.id), ["cached"])
    }
}
