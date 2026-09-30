import XCTest
@testable import VerbKit

final class FuriganaSyncServiceTests: XCTestCase {
    private func manifest(for data: Data, version: String = "1.0.0") -> FuriganaManifest {
        FuriganaManifest(version: version, sha256: sha256Hex(of: data))
    }

    func testNoFuriganaEntryInManifestIsUpToDate() async throws {
        let fetcher = MockVerbDataFetcher()
        fetcher.furiganaManifestResult = .success(nil)
        fetcher.furiganaDataResult = .failure(VerbSyncError.serverUnreachable) // must not be called

        let result = try await FuriganaSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore()).sync()
        XCTAssertEqual(result, .upToDate)
    }

    func testUnchangedConfirmedManifestSkipsTheDataFetch() async throws {
        let entry = manifest(for: FuriganaFixture.data)
        let fetcher = MockVerbDataFetcher()
        fetcher.furiganaManifestResult = .success(entry)
        fetcher.furiganaDataResult = .failure(VerbSyncError.serverUnreachable) // must not be called

        let syncState = InMemorySyncStateStore()
        syncState.saveLastSyncedFuriganaManifest(entry)

        let result = try await FuriganaSyncService(fetcher: fetcher, syncState: syncState).sync()
        XCTAssertEqual(result, .upToDate)
    }

    func testChangedManifestFetchesAndDecodesButDoesNotRecordState() async throws {
        let entry = manifest(for: FuriganaFixture.data, version: "1.1.0")
        let fetcher = MockVerbDataFetcher()
        fetcher.furiganaManifestResult = .success(entry)
        fetcher.furiganaDataResult = .success(FuriganaFixture.data)

        let syncState = InMemorySyncStateStore()
        let result = try await FuriganaSyncService(fetcher: fetcher, syncState: syncState).sync()

        guard case let .updated(updatedManifest, dictionary) = result else {
            return XCTFail("expected .updated")
        }
        XCTAssertEqual(updatedManifest, entry)
        XCTAssertEqual(dictionary, FuriganaFixture.dictionary)
        // Recording is the caller's job, after it has persisted the dictionary.
        XCTAssertNil(syncState.lastSyncedFuriganaManifest())
    }

    func testConfirmSyncedRecordsTheManifestOnlyWhenCalled() async throws {
        let entry = manifest(for: FuriganaFixture.data)
        let fetcher = MockVerbDataFetcher()
        fetcher.furiganaManifestResult = .success(entry)
        fetcher.furiganaDataResult = .success(FuriganaFixture.data)

        let syncState = InMemorySyncStateStore()
        let service = FuriganaSyncService(fetcher: fetcher, syncState: syncState)
        _ = try await service.sync()
        XCTAssertNil(syncState.lastSyncedFuriganaManifest())

        service.confirmSynced(entry)
        XCTAssertEqual(syncState.lastSyncedFuriganaManifest(), entry)
        let again = try await service.sync()
        XCTAssertEqual(again, .upToDate)
    }

    func testFuriganaSyncDoesNotTouchVerbOrGrammarSyncState() async throws {
        let entry = manifest(for: FuriganaFixture.data)
        let fetcher = MockVerbDataFetcher()
        fetcher.furiganaManifestResult = .success(entry)
        fetcher.furiganaDataResult = .success(FuriganaFixture.data)

        let syncState = InMemorySyncStateStore()
        let service = FuriganaSyncService(fetcher: fetcher, syncState: syncState)
        _ = try await service.sync()
        service.confirmSynced(entry)

        XCTAssertNil(syncState.lastSyncedManifest())
        XCTAssertNil(syncState.lastSyncedGrammarManifest())
    }

    func testHashMismatchThrowsMalformedData() async throws {
        let fetcher = MockVerbDataFetcher()
        fetcher.furiganaManifestResult = .success(FuriganaManifest(version: "1.1.0", sha256: "not-the-real-hash"))
        fetcher.furiganaDataResult = .success(FuriganaFixture.data)

        let syncState = InMemorySyncStateStore()
        do {
            _ = try await FuriganaSyncService(fetcher: fetcher, syncState: syncState).sync()
            XCTFail("expected malformedData")
        } catch VerbSyncError.malformedData {
            XCTAssertNil(syncState.lastSyncedFuriganaManifest())
        }
    }

    func testMalformedJSONThrowsMalformedData() async throws {
        let bad = Data("not json".utf8)
        let fetcher = MockVerbDataFetcher()
        fetcher.furiganaManifestResult = .success(manifest(for: bad))
        fetcher.furiganaDataResult = .success(bad)

        do {
            _ = try await FuriganaSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore()).sync()
            XCTFail("expected malformedData")
        } catch VerbSyncError.malformedData {
            // expected
        }
    }

    func testOfflineErrorPropagates() async throws {
        let fetcher = MockVerbDataFetcher()
        fetcher.furiganaManifestResult = .failure(VerbSyncError.offline)

        do {
            _ = try await FuriganaSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore()).sync()
            XCTFail("expected offline")
        } catch VerbSyncError.offline {
            // expected
        }
    }
}
