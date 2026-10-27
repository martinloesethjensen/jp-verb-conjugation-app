import XCTest
import SwiftData
@testable import VerbKit

/// The bundled-copy install rule for the furigana and words stores. Verbs and grammar are in VerbStoreTests.
@MainActor
final class BundledInstallTests: XCTestCase {
    private func offline() -> MockVerbDataFetcher {
        let fetcher = MockVerbDataFetcher()
        fetcher.furiganaManifestResult = .failure(VerbSyncError.offline)
        fetcher.wordsManifestResult = .failure(VerbSyncError.offline)
        return fetcher
    }

    // MARK: furigana

    private func bundledFurigana(version: String = "1.0.0") -> BundledData<FuriganaDataFile> {
        BundledData(
            value: try! JSONDecoder().decode(FuriganaDataFile.self, from: FuriganaFixture.data), version: version,
            sha256: sha256Hex(of: FuriganaFixture.data), data: FuriganaFixture.data
        )
    }

    private func furiganaStore(
        _ persisting: FuriganaPersisting, _ state: InMemorySyncStateStore, bundled: BundledData<FuriganaDataFile>?
    ) -> FuriganaStore {
        FuriganaStore(
            syncService: FuriganaSyncService(fetcher: offline(), syncState: state), persisting: persisting,
            bundled: bundled
        )
    }

    private func furiganaPersisting() throws -> SwiftDataFuriganaPersisting {
        SwiftDataFuriganaPersisting(modelContext: ModelContext(try VerbModelContainer.makeInMemory()))
    }

    private final class CountingFurigana: FuriganaPersisting {
        let base: FuriganaPersisting
        var replaces = 0
        var fail = false
        init(_ base: FuriganaPersisting) { self.base = base }
        func loadFuriganaDictionary() throws -> FuriganaDictionary? { try base.loadFuriganaDictionary() }
        func replaceFuriganaDictionary(with dictionary: FuriganaDictionary) throws {
            replaces += 1
            if fail { throw VerbSyncError.malformedData }
            try base.replaceFuriganaDictionary(with: dictionary)
        }
    }

    func testAnOfflineFirstLaunchShowsAndPersistsTheBundledFurigana() async throws {
        let persisting = try furiganaPersisting()
        let state = InMemorySyncStateStore()
        let store = furiganaStore(persisting, state, bundled: bundledFurigana())
        await store.start()
        XCTAssertEqual(store.dictionary, FuriganaFixture.dictionary)
        XCTAssertEqual(try persisting.loadFuriganaDictionary(), FuriganaFixture.dictionary)
        XCTAssertEqual(state.highestAcceptedVersion(for: "furigana"), "1.0.0")
        XCTAssertEqual(state.lastSyncedFuriganaManifest()?.version, "1.0.0")
    }

    func testANewerBundledFuriganaReplacesTheCacheOnce() async throws {
        let persisting = CountingFurigana(try furiganaPersisting())
        let state = InMemorySyncStateStore()
        state.saveHighestAcceptedVersion("0.9.0", for: "furigana")
        let store = furiganaStore(persisting, state, bundled: bundledFurigana())
        await store.start()
        XCTAssertEqual(persisting.replaces, 1)
        XCTAssertEqual(store.dictionary, FuriganaFixture.dictionary)
    }

    func testAnOlderOrEqualBundledFuriganaChangesNothing() async throws {
        for floor in ["1.0.0", "2.0.0"] {
            let persisting = CountingFurigana(try furiganaPersisting())
            let state = InMemorySyncStateStore()
            state.saveHighestAcceptedVersion(floor, for: "furigana")
            let store = furiganaStore(persisting, state, bundled: bundledFurigana())
            await store.start()
            XCTAssertEqual(persisting.replaces, 0, "floor \(floor)")
            XCTAssertNil(store.dictionary)
        }
    }

    func testAFailedFuriganaInstallRecordsNothing() async throws {
        let persisting = CountingFurigana(try furiganaPersisting())
        persisting.fail = true
        let state = InMemorySyncStateStore()
        let store = furiganaStore(persisting, state, bundled: bundledFurigana())
        await store.start()
        XCTAssertNil(store.dictionary)
        XCTAssertNil(state.highestAcceptedVersion(for: "furigana"))
        XCTAssertNil(state.lastSyncedFuriganaManifest())
    }

    func testFuriganaWithoutABundleBehavesAsBefore() async throws {
        let store = furiganaStore(try furiganaPersisting(), InMemorySyncStateStore(), bundled: nil)
        await store.start()
        XCTAssertNil(store.dictionary)
    }

    // MARK: words

    private func bundledWords(version: String? = nil) throws -> BundledData<WordsDataFile> {
        let real = try XCTUnwrap(BundledData<WordsDataFile>.load(named: "words"))
        guard let version else { return real }
        return BundledData(value: real.value, version: version, sha256: real.sha256, data: real.data)
    }

    private func wordsPersisting() throws -> SwiftDataWordsPersisting {
        SwiftDataWordsPersisting(modelContext: ModelContext(try VerbModelContainer.makeInMemory()))
    }

    private final class CountingWords: WordsPersisting {
        let base: WordsPersisting
        var replaces = 0
        var fail = false
        init(_ base: WordsPersisting) { self.base = base }
        func loadWords() throws -> [Word]? { try base.loadWords() }
        func replaceWords(with words: [Word]) throws {
            replaces += 1
            if fail { throw VerbSyncError.malformedData }
            try base.replaceWords(with: words)
        }
    }

    private func wordsStore(
        _ persisting: WordsPersisting, _ state: InMemorySyncStateStore, bundled: BundledData<WordsDataFile>?
    ) -> WordsStore {
        WordsStore(
            syncService: WordsSyncService(fetcher: offline(), syncState: state), persisting: persisting,
            bundled: bundled
        )
    }

    func testAnOfflineFirstLaunchShowsAndPersistsTheBundledWords() async throws {
        let bundled = try bundledWords()
        let persisting = try wordsPersisting()
        let state = InMemorySyncStateStore()
        let store = wordsStore(persisting, state, bundled: bundled)
        await store.start()
        XCTAssertFalse(bundled.value.words.isEmpty)
        XCTAssertEqual(store.words.count, bundled.value.words.count)
        XCTAssertEqual(try persisting.loadWords()?.count, bundled.value.words.count)
        XCTAssertEqual(state.highestAcceptedVersion(for: "words"), bundled.version)
        XCTAssertEqual(state.lastSyncedWordsManifest()?.version, bundled.version)
    }

    func testANewerBundledWordsReplacesTheCacheOnce() async throws {
        let persisting = CountingWords(try wordsPersisting())
        let state = InMemorySyncStateStore()
        state.saveHighestAcceptedVersion("0.0.1", for: "words")
        let store = wordsStore(persisting, state, bundled: try bundledWords())
        await store.start()
        XCTAssertEqual(persisting.replaces, 1)
        XCTAssertFalse(store.words.isEmpty)
    }

    func testAnOlderOrEqualBundledWordsChangesNothing() async throws {
        let bundled = try bundledWords()
        for floor in [bundled.version, "999.0.0"] {
            let persisting = CountingWords(try wordsPersisting())
            let state = InMemorySyncStateStore()
            state.saveHighestAcceptedVersion(floor, for: "words")
            let store = wordsStore(persisting, state, bundled: bundled)
            await store.start()
            XCTAssertEqual(persisting.replaces, 0, "floor \(floor)")
            XCTAssertTrue(store.words.isEmpty)
        }
    }

    func testAFailedWordsInstallRecordsNothing() async throws {
        let persisting = CountingWords(try wordsPersisting())
        persisting.fail = true
        let state = InMemorySyncStateStore()
        let store = wordsStore(persisting, state, bundled: try bundledWords())
        await store.start()
        XCTAssertTrue(store.words.isEmpty)
        XCTAssertNil(state.highestAcceptedVersion(for: "words"))
        XCTAssertNil(state.lastSyncedWordsManifest())
    }

    func testWordsWithoutABundleBehaveAsBefore() async throws {
        let store = wordsStore(try wordsPersisting(), InMemorySyncStateStore(), bundled: nil)
        await store.start()
        XCTAssertTrue(store.words.isEmpty)
    }
}
