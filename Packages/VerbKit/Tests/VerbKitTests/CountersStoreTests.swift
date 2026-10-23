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
        persisting: CountersPersisting
    ) -> CountersStore {
        CountersStore(syncService: CountersSyncService(fetcher: fetcher, syncState: state), persisting: persisting)
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
}
