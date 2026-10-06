import XCTest
import SwiftData
@testable import VerbKit

final class WordsSyncTests: XCTestCase {
    static let json = """
    {"version":"1.0.0","description":"d","words":[
      {"class":"i-adjective","dict":"たかい","kanji":"高い","meaning":"expensive","jlpt":"N5",
       "forms":{"te":"たかくて","short_pos":"たかい","short_neg":"たかくない","short_past":"たかかった","short_past_neg":"たかくなかった","stem":"たか"}},
      {"class":"noun","dict":"あめ","meaning":"rain","forms":{"short_pos":"あめだ"}}]}
    """

    private var data: Data { Data(Self.json.utf8) }

    func testDecodesWordsWithClassAndForms() throws {
        let file = try JSONDecoder().decode(WordsDataFile.self, from: data)
        XCTAssertEqual(file.words.map(\.wordClass), [.iAdjective, .noun])
        XCTAssertEqual(file.words[0].forms["stem"], "たか")
        XCTAssertEqual(file.words[0].kanji, "高い")
        XCTAssertEqual(file.words[0].jlpt, .n5)
        XCTAssertNil(file.words[1].kanji)
        XCTAssertNil(file.words[1].jlpt)
    }

    func testSyncFetchesVerifiesAndDoesNotConfirm() async throws {
        let fetcher = MockVerbDataFetcher()
        fetcher.wordsManifestResult = .success(WordsManifest(version: "1.0.0", sha256: sha256Hex(of: data)))
        fetcher.wordsDataResult = .success(data)
        let state = InMemorySyncStateStore()
        let service = WordsSyncService(fetcher: fetcher, syncState: state)
        let result = try await service.sync()
        guard case let .updated(manifest, words) = result else { return XCTFail("expected updated") }
        XCTAssertEqual(words.count, 2)
        XCTAssertNil(state.lastSyncedWordsManifest())
        service.confirmSynced(manifest)
        XCTAssertEqual(state.lastSyncedWordsManifest(), manifest)
        let again = try await service.sync()
        XCTAssertEqual(again, .upToDate)
    }

    func testNoWordsBlockIsUpToDate() async throws {
        let result = try await WordsSyncService(fetcher: MockVerbDataFetcher(), syncState: InMemorySyncStateStore()).sync()
        XCTAssertEqual(result, .upToDate)
    }

    func testHashMismatchIsMalformed() async {
        let fetcher = MockVerbDataFetcher()
        fetcher.wordsManifestResult = .success(WordsManifest(version: "1.0.0", sha256: "bad"))
        fetcher.wordsDataResult = .success(data)
        do {
            _ = try await WordsSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore()).sync()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? VerbSyncError, .malformedData)
        }
    }

    func testOlderVersionThanAcceptedIsRefused() async {
        let fetcher = MockVerbDataFetcher()
        fetcher.wordsManifestResult = .success(WordsManifest(version: "1.0.0", sha256: sha256Hex(of: data)))
        fetcher.wordsDataResult = .success(data)
        let state = InMemorySyncStateStore()
        state.saveHighestAcceptedVersion("2.0.0", for: "words")
        do {
            _ = try await WordsSyncService(fetcher: fetcher, syncState: state).sync()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? VerbSyncError, .untrusted)
        }
    }

    @MainActor
    func testPersistingRoundTrip() throws {
        let container = try VerbModelContainer.makeInMemory()
        let persisting = SwiftDataWordsPersisting(modelContext: ModelContext(container))
        XCTAssertNil(try persisting.loadWords())
        let words = try JSONDecoder().decode(WordsDataFile.self, from: data).words
        try persisting.replaceWords(with: words)
        XCTAssertEqual(try persisting.loadWords(), words)
        try persisting.replaceWords(with: [words[1]])
        XCTAssertEqual(try persisting.loadWords(), [words[1]])
    }

    @MainActor
    func testStoreLoadsCacheThenSyncs() async throws {
        let container = try VerbModelContainer.makeInMemory()
        let persisting = SwiftDataWordsPersisting(modelContext: ModelContext(container))
        let fetcher = MockVerbDataFetcher()
        fetcher.wordsManifestResult = .success(WordsManifest(version: "1.0.0", sha256: sha256Hex(of: data)))
        fetcher.wordsDataResult = .success(data)
        let store = WordsStore(syncService: WordsSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore()), persisting: persisting)
        XCTAssertTrue(store.words.isEmpty)
        await store.start()
        XCTAssertEqual(store.words.count, 2)
        XCTAssertEqual(store.words(of: .noun).map(\.dict), ["あめ"])
        XCTAssertEqual(try persisting.loadWords()?.count, 2)
    }
}
