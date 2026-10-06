import XCTest
@testable import VerbKit

final class VerbSyncServiceTests: XCTestCase {
    private func fixtureData() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "verbs-fixture", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testUpToDateSkipsVerbDataFetch() async throws {
        let data = try fixtureData()
        let manifest = VerbManifest(version: "1.0.0", sha256: sha256Hex(of: data))
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .success(manifest)
        fetcher.verbDataResult = .failure(VerbSyncError.serverUnreachable) // must not be called

        let syncState = InMemorySyncStateStore()
        syncState.saveLastSyncedManifest(manifest)

        let service = VerbSyncService(fetcher: fetcher, syncState: syncState)
        let result = try await service.sync()

        XCTAssertEqual(result, .upToDate)
    }

    func testChangedManifestFetchesAndDecodesVerbs() async throws {
        let data = try fixtureData()
        let manifest = VerbManifest(version: "1.1.0", sha256: sha256Hex(of: data))
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .success(manifest)
        fetcher.verbDataResult = .success(data)

        let syncState = InMemorySyncStateStore()
        let service = VerbSyncService(fetcher: fetcher, syncState: syncState)
        let result = try await service.sync()

        guard case let .updated(updatedManifest, verbs) = result else {
            return XCTFail("expected .updated")
        }
        XCTAssertEqual(updatedManifest, manifest)
        XCTAssertEqual(verbs.count, 2)
        // sync() must NOT record the manifest as synced on its own —
        // only a caller who has durably persisted the verbs should do
        // that, via confirmSynced(_:). See Important #4 of the final
        // whole-branch review: recording it here would make a later
        // persistence failure indistinguishable from "nothing changed".
        XCTAssertNil(syncState.lastSyncedManifest())
    }

    func testConfirmSyncedRecordsManifestOnlyWhenCalled() async throws {
        let data = try fixtureData()
        let manifest = VerbManifest(version: "1.1.0", sha256: sha256Hex(of: data))
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .success(manifest)
        fetcher.verbDataResult = .success(data)

        let syncState = InMemorySyncStateStore()
        let service = VerbSyncService(fetcher: fetcher, syncState: syncState)
        _ = try await service.sync()
        XCTAssertNil(syncState.lastSyncedManifest())

        service.confirmSynced(manifest)
        XCTAssertEqual(syncState.lastSyncedManifest(), manifest)
    }

    func testHashMismatchThrowsMalformedData() async throws {
        let data = try fixtureData()
        let manifest = VerbManifest(version: "1.1.0", sha256: "not-the-real-hash")
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .success(manifest)
        fetcher.verbDataResult = .success(data)

        let service = VerbSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore())
        do {
            _ = try await service.sync()
            XCTFail("expected malformedData error")
        } catch VerbSyncError.malformedData {
            // expected
        }
    }

    func testMalformedJSONThrowsMalformedData() async throws {
        let badData = Data("not json".utf8)
        let manifest = VerbManifest(version: "1.1.0", sha256: sha256Hex(of: badData))
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .success(manifest)
        fetcher.verbDataResult = .success(badData)

        let service = VerbSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore())
        do {
            _ = try await service.sync()
            XCTFail("expected malformedData error")
        } catch VerbSyncError.malformedData {
            // expected
        }
    }

    func testManifestOlderThanOneAlreadyAcceptedIsRefused() async throws {
        let data = try fixtureData()
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .success(VerbManifest(version: "1.1.0", sha256: sha256Hex(of: data)))
        fetcher.verbDataResult = .success(data)
        let syncState = InMemorySyncStateStore()
        syncState.saveHighestAcceptedVersion("1.2.0", for: "verbs")

        let service = VerbSyncService(fetcher: fetcher, syncState: syncState)
        do {
            _ = try await service.sync()
            XCTFail("expected untrusted")
        } catch VerbSyncError.untrusted {
            // expected
        }
    }

    func testConfirmSyncedRaisesTheHighestAcceptedVersion() {
        let syncState = InMemorySyncStateStore()
        let service = VerbSyncService(fetcher: MockVerbDataFetcher(), syncState: syncState)
        service.confirmSynced(VerbManifest(version: "1.3.0", sha256: "abc"))
        XCTAssertEqual(syncState.highestAcceptedVersion(for: "verbs"), "1.3.0")
    }

    func testGrammarManifestOlderThanOneAlreadyAcceptedIsRefused() async throws {
        let fetcher = MockVerbDataFetcher()
        fetcher.grammarManifestResult = .success(GrammarManifest(version: "1.0.0", sha256: "x"))
        let syncState = InMemorySyncStateStore()
        syncState.saveHighestAcceptedVersion("1.1.0", for: "grammar")

        do {
            _ = try await GrammarSyncService(fetcher: fetcher, syncState: syncState).sync()
            XCTFail("expected untrusted")
        } catch VerbSyncError.untrusted {
            // expected
        }
    }

    func testFuriganaManifestOlderThanOneAlreadyAcceptedIsRefused() async throws {
        let fetcher = MockVerbDataFetcher()
        fetcher.furiganaManifestResult = .success(FuriganaManifest(version: "1.0.0", sha256: "x"))
        let syncState = InMemorySyncStateStore()
        syncState.saveHighestAcceptedVersion("1.1.0", for: "furigana")

        do {
            _ = try await FuriganaSyncService(fetcher: fetcher, syncState: syncState).sync()
            XCTFail("expected untrusted")
        } catch VerbSyncError.untrusted {
            // expected
        }
    }

    func testOfflineErrorPropagates() async throws {
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .failure(VerbSyncError.offline)

        let service = VerbSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore())
        do {
            _ = try await service.sync()
            XCTFail("expected offline error")
        } catch VerbSyncError.offline {
            // expected
        }
    }
}

// Internal (not `private`) so Task 9's VerbStoreTests can reuse them —
// test files in the same target share internal declarations freely.
final class MockVerbDataFetcher: VerbDataFetching, @unchecked Sendable {
    var manifestResult: Result<VerbManifest, Error> = .failure(VerbSyncError.offline)
    var verbDataResult: Result<Data, Error> = .failure(VerbSyncError.offline)
    /// Defaults to "no grammar published" so verb-only tests are unaffected.
    var grammarManifestResult: Result<GrammarManifest?, Error> = .success(nil)
    var grammarDataResult: Result<Data, Error> = .failure(VerbSyncError.offline)
    /// Defaults to "no furigana published" so verb- and grammar-only tests are unaffected.
    var furiganaManifestResult: Result<FuriganaManifest?, Error> = .success(nil)
    var furiganaDataResult: Result<Data, Error> = .failure(VerbSyncError.offline)
    /// Defaults to "no words published" so the other tests are unaffected.
    var wordsManifestResult: Result<WordsManifest?, Error> = .success(nil)
    var wordsDataResult: Result<Data, Error> = .failure(VerbSyncError.offline)

    func fetchManifest() async throws -> VerbManifest { try manifestResult.get() }
    func fetchVerbData() async throws -> Data { try verbDataResult.get() }
    func fetchGrammarManifest() async throws -> GrammarManifest? { try grammarManifestResult.get() }
    func fetchGrammarData() async throws -> Data { try grammarDataResult.get() }
    func fetchFuriganaManifest() async throws -> FuriganaManifest? { try furiganaManifestResult.get() }
    func fetchFuriganaData() async throws -> Data { try furiganaDataResult.get() }
    func fetchWordsManifest() async throws -> WordsManifest? { try wordsManifestResult.get() }
    func fetchWordsData() async throws -> Data { try wordsDataResult.get() }
}

final class InMemorySyncStateStore: SyncStateStoring, @unchecked Sendable {
    private var manifest: VerbManifest?
    private var grammarManifest: GrammarManifest?
    private var furiganaManifest: FuriganaManifest?
    func lastSyncedManifest() -> VerbManifest? { manifest }
    func saveLastSyncedManifest(_ manifest: VerbManifest) { self.manifest = manifest }
    func lastSyncedGrammarManifest() -> GrammarManifest? { grammarManifest }
    func saveLastSyncedGrammarManifest(_ manifest: GrammarManifest) { grammarManifest = manifest }
    func lastSyncedFuriganaManifest() -> FuriganaManifest? { furiganaManifest }
    func saveLastSyncedFuriganaManifest(_ manifest: FuriganaManifest) { furiganaManifest = manifest }
    private var wordsManifest: WordsManifest?
    func lastSyncedWordsManifest() -> WordsManifest? { wordsManifest }
    func saveLastSyncedWordsManifest(_ manifest: WordsManifest) { wordsManifest = manifest }
    private var highest: [String: String] = [:]
    func highestAcceptedVersion(for file: String) -> String? { highest[file] }
    func saveHighestAcceptedVersion(_ version: String, for file: String) { highest[file] = version }
}
