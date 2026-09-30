import XCTest
import SwiftData
@testable import VerbKit

@MainActor
final class FuriganaStoreTests: XCTestCase {
    private struct Harness {
        let store: FuriganaStore
        let fetcher: MockVerbDataFetcher
        let persisting: SwiftDataFuriganaPersisting
        let syncState: InMemorySyncStateStore
        let manifest: FuriganaManifest
    }

    private func makeHarness() throws -> Harness {
        let manifest = FuriganaManifest(version: "1.0.0", sha256: sha256Hex(of: FuriganaFixture.data))
        let fetcher = MockVerbDataFetcher()
        fetcher.furiganaManifestResult = .success(manifest)
        fetcher.furiganaDataResult = .success(FuriganaFixture.data)

        let container = try VerbModelContainer.makeInMemory()
        let persisting = SwiftDataFuriganaPersisting(modelContext: ModelContext(container))
        let syncState = InMemorySyncStateStore()
        let store = FuriganaStore(
            syncService: FuriganaSyncService(fetcher: fetcher, syncState: syncState),
            persisting: persisting
        )
        return Harness(store: store, fetcher: fetcher, persisting: persisting, syncState: syncState, manifest: manifest)
    }

    func testThereIsNoDictionaryBeforeStart() throws {
        XCTAssertNil(try makeHarness().store.dictionary)
    }

    func testFirstSyncLoadsPersistsAndConfirms() async throws {
        let h = try makeHarness()

        await h.store.start()

        XCTAssertEqual(h.store.dictionary, FuriganaFixture.dictionary)
        XCTAssertEqual(try h.persisting.loadFuriganaDictionary(), FuriganaFixture.dictionary)
        XCTAssertEqual(h.syncState.lastSyncedFuriganaManifest(), h.manifest)
    }

    func testACachedDictionaryLoadsEvenWhenTheSyncFails() async throws {
        let h = try makeHarness()
        try h.persisting.replaceFuriganaDictionary(with: FuriganaFixture.dictionary)
        h.fetcher.furiganaManifestResult = .failure(VerbSyncError.offline)

        await h.store.start()

        XCTAssertEqual(h.store.dictionary, FuriganaFixture.dictionary)
    }

    func testASyncFailureWithNothingCachedLeavesNoDictionarySilently() async throws {
        let h = try makeHarness()
        h.fetcher.furiganaManifestResult = .failure(VerbSyncError.serverUnreachable)

        await h.store.start()

        XCTAssertNil(h.store.dictionary)
    }

    func testAnUpToDateManifestKeepsTheCachedDictionary() async throws {
        let h = try makeHarness()
        try h.persisting.replaceFuriganaDictionary(with: FuriganaFixture.dictionary)
        h.syncState.saveLastSyncedFuriganaManifest(h.manifest)
        h.fetcher.furiganaDataResult = .failure(VerbSyncError.serverUnreachable) // must not be fetched

        await h.store.start()

        XCTAssertEqual(h.store.dictionary, FuriganaFixture.dictionary)
    }

    func testANewerDictionaryReplacesTheCachedOne() async throws {
        let h = try makeHarness()
        try h.persisting.replaceFuriganaDictionary(with: FuriganaDictionary(readings: ["猫": "ねこ"]))

        await h.store.start()

        XCTAssertEqual(h.store.dictionary, FuriganaFixture.dictionary)
        XCTAssertEqual(try h.persisting.loadFuriganaDictionary(), FuriganaFixture.dictionary)
    }

    func testAPersistenceFailureLeavesTheManifestUnconfirmedSoARetryRefetches() async throws {
        let manifest = FuriganaManifest(version: "1.0.0", sha256: sha256Hex(of: FuriganaFixture.data))
        let fetcher = MockVerbDataFetcher()
        fetcher.furiganaManifestResult = .success(manifest)
        fetcher.furiganaDataResult = .success(FuriganaFixture.data)
        let syncState = InMemorySyncStateStore()
        let persisting = FailingFuriganaPersisting(shouldFail: true)
        let store = FuriganaStore(
            syncService: FuriganaSyncService(fetcher: fetcher, syncState: syncState),
            persisting: persisting
        )

        await store.start()

        XCTAssertNil(store.dictionary)
        XCTAssertNil(syncState.lastSyncedFuriganaManifest())

        // Once persistence works, the next start genuinely re-fetches.
        persisting.shouldFail = false
        await store.start()

        XCTAssertEqual(store.dictionary, FuriganaFixture.dictionary)
        XCTAssertEqual(syncState.lastSyncedFuriganaManifest(), manifest)
    }

    func testNoDictionaryMeansEveryStringIsPlain() {
        // The app treats a nil dictionary as "no furigana"; the empty dictionary is the
        // same thing expressed as a value.
        let units = FuriganaDictionary.empty.units(for: "食べる")
        XCTAssertTrue(units.allSatisfy { $0.reading == nil })
    }
}

private enum FailingFuriganaPersistingError: Error { case persistFailed }

/// A `FuriganaPersisting` whose `replaceFuriganaDictionary(with:)` can be made
/// to throw on demand, to simulate a persistence failure.
@MainActor
private final class FailingFuriganaPersisting: FuriganaPersisting {
    var shouldFail: Bool
    private var stored: FuriganaDictionary?

    init(shouldFail: Bool) { self.shouldFail = shouldFail }

    func loadFuriganaDictionary() throws -> FuriganaDictionary? { stored }

    func replaceFuriganaDictionary(with dictionary: FuriganaDictionary) throws {
        if shouldFail { throw FailingFuriganaPersistingError.persistFailed }
        stored = dictionary
    }
}
