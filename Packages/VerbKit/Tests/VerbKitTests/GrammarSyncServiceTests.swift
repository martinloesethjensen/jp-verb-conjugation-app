import XCTest
@testable import VerbKit

final class GrammarSyncServiceTests: XCTestCase {
    private func manifest(for data: Data, version: String = "1.0.0") -> GrammarManifest {
        GrammarManifest(version: version, sha256: sha256Hex(of: data))
    }

    func testNoGrammarEntryInManifestIsUpToDate() async throws {
        let fetcher = MockVerbDataFetcher()
        fetcher.grammarManifestResult = .success(nil)
        fetcher.grammarDataResult = .failure(VerbSyncError.serverUnreachable) // must not be called

        let service = GrammarSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore())
        let result = try await service.sync()

        XCTAssertEqual(result, .upToDate)
    }

    func testUnchangedConfirmedManifestSkipsGrammarDataFetch() async throws {
        let entry = manifest(for: GrammarFixture.data)
        let fetcher = MockVerbDataFetcher()
        fetcher.grammarManifestResult = .success(entry)
        fetcher.grammarDataResult = .failure(VerbSyncError.serverUnreachable) // must not be called

        let syncState = InMemorySyncStateStore()
        syncState.saveLastSyncedGrammarManifest(entry)

        let result = try await GrammarSyncService(fetcher: fetcher, syncState: syncState).sync()
        XCTAssertEqual(result, .upToDate)
    }

    func testChangedManifestFetchesAndDecodesButDoesNotRecordState() async throws {
        let entry = manifest(for: GrammarFixture.data, version: "1.1.0")
        let fetcher = MockVerbDataFetcher()
        fetcher.grammarManifestResult = .success(entry)
        fetcher.grammarDataResult = .success(GrammarFixture.data)

        let syncState = InMemorySyncStateStore()
        let result = try await GrammarSyncService(fetcher: fetcher, syncState: syncState).sync()

        guard case let .updated(updatedManifest, points) = result else {
            return XCTFail("expected .updated")
        }
        XCTAssertEqual(updatedManifest, entry)
        XCTAssertEqual(points.map(\.id), ["n-desu", "wake-desu"])
        // Recording is the caller's job, after it has persisted the points.
        XCTAssertNil(syncState.lastSyncedGrammarManifest())
    }

    func testConfirmSyncedRecordsTheManifestOnlyWhenCalled() async throws {
        let entry = manifest(for: GrammarFixture.data)
        let fetcher = MockVerbDataFetcher()
        fetcher.grammarManifestResult = .success(entry)
        fetcher.grammarDataResult = .success(GrammarFixture.data)

        let syncState = InMemorySyncStateStore()
        let service = GrammarSyncService(fetcher: fetcher, syncState: syncState)
        _ = try await service.sync()
        XCTAssertNil(syncState.lastSyncedGrammarManifest())

        service.confirmSynced(entry)
        XCTAssertEqual(syncState.lastSyncedGrammarManifest(), entry)
        // After confirming, the same manifest is up to date.
        let again = try await service.sync()
        XCTAssertEqual(again, .upToDate)
    }

    func testGrammarSyncDoesNotTouchVerbSyncState() async throws {
        let entry = manifest(for: GrammarFixture.data)
        let fetcher = MockVerbDataFetcher()
        fetcher.grammarManifestResult = .success(entry)
        fetcher.grammarDataResult = .success(GrammarFixture.data)

        let syncState = InMemorySyncStateStore()
        let service = GrammarSyncService(fetcher: fetcher, syncState: syncState)
        _ = try await service.sync()
        service.confirmSynced(entry)

        XCTAssertNil(syncState.lastSyncedManifest())
    }

    func testHashMismatchThrowsMalformedData() async throws {
        let fetcher = MockVerbDataFetcher()
        fetcher.grammarManifestResult = .success(GrammarManifest(version: "1.1.0", sha256: "not-the-real-hash"))
        fetcher.grammarDataResult = .success(GrammarFixture.data)

        let syncState = InMemorySyncStateStore()
        do {
            _ = try await GrammarSyncService(fetcher: fetcher, syncState: syncState).sync()
            XCTFail("expected malformedData")
        } catch VerbSyncError.malformedData {
            XCTAssertNil(syncState.lastSyncedGrammarManifest())
        }
    }

    func testMalformedJSONThrowsMalformedData() async throws {
        let bad = Data("not json".utf8)
        let fetcher = MockVerbDataFetcher()
        fetcher.grammarManifestResult = .success(manifest(for: bad))
        fetcher.grammarDataResult = .success(bad)

        do {
            _ = try await GrammarSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore()).sync()
            XCTFail("expected malformedData")
        } catch VerbSyncError.malformedData {
            // expected
        }
    }

    func testOfflineErrorPropagates() async throws {
        let fetcher = MockVerbDataFetcher()
        fetcher.grammarManifestResult = .failure(VerbSyncError.offline)

        do {
            _ = try await GrammarSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore()).sync()
            XCTFail("expected offline")
        } catch VerbSyncError.offline {
            // expected
        }
    }
}
