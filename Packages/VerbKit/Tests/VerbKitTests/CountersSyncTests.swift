import XCTest
@testable import VerbKit

final class CountersSyncTests: XCTestCase {
    static let json = """
    {"version":"1.0.0","description":"d","counters":[
      {"id":"hon","counter":"本","reading":"ほん","meaning":"long, thin things","jlpt":"N5","sound":"h-b","symbol":"pencil",
       "readings":{"1":["いっぽん"],"2":["にほん"],"3":["さんぼん"],"4":["よんほん"],"5":["ごほん"],"6":["ろっぽん"],
                   "7":["ななほん"],"8":["はっぽん","はちほん"],"9":["きゅうほん"],"10":["じゅっぽん","じっぽん"],"what":["なんぼん"]},
       "changed":["1","3","6","8","10","what"]}],
     "groups":[{"id":"long","title":"Long things","symbol":"pencil","summary":"s","members":[{"counter":"hon","note":"pencils"}]}]}
    """

    private var data: Data { Data(Self.json.utf8) }

    private func fetcher(version: String = "1.0.0", sha: String? = nil) -> MockVerbDataFetcher {
        let fetcher = MockVerbDataFetcher()
        fetcher.countersManifestResult = .success(CountersManifest(version: version, sha256: sha ?? sha256Hex(of: data)))
        fetcher.countersDataResult = .success(data)
        return fetcher
    }

    func testSyncFetchesVerifiesAndDoesNotConfirm() async throws {
        let state = InMemorySyncStateStore()
        let service = CountersSyncService(fetcher: fetcher(), syncState: state)
        guard case let .updated(manifest, file) = try await service.sync() else { return XCTFail("expected updated") }
        XCTAssertEqual(file.counters.map(\.id), ["hon"])
        XCTAssertEqual(file.groups.map(\.id), ["long"])
        XCTAssertNil(state.lastSyncedCountersManifest())
        service.confirmSynced(manifest)
        XCTAssertEqual(state.lastSyncedCountersManifest(), manifest)
        XCTAssertEqual(state.highestAcceptedVersion(for: "counters"), "1.0.0")
        let again = try await service.sync()
        XCTAssertEqual(again, .upToDate)
    }

    func testNoCountersBlockIsUpToDate() async throws {
        let service = CountersSyncService(fetcher: MockVerbDataFetcher(), syncState: InMemorySyncStateStore())
        let result = try await service.sync()
        XCTAssertEqual(result, .upToDate)
    }

    func testAChangedManifestIsUpdatedAgain() async throws {
        let state = InMemorySyncStateStore()
        state.saveLastSyncedCountersManifest(CountersManifest(version: "0.9.0", sha256: "old"))
        let result = try await CountersSyncService(fetcher: fetcher(), syncState: state).sync()
        guard case .updated = result else { return XCTFail("expected updated") }
    }

    func testHashMismatchIsMalformed() async {
        do {
            _ = try await CountersSyncService(fetcher: fetcher(sha: "bad"), syncState: InMemorySyncStateStore()).sync()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? VerbSyncError, .malformedData)
        }
    }

    func testOlderVersionThanAcceptedIsRefused() async {
        let state = InMemorySyncStateStore()
        state.saveHighestAcceptedVersion("2.0.0", for: "counters")
        do {
            _ = try await CountersSyncService(fetcher: fetcher(), syncState: state).sync()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? VerbSyncError, .untrusted)
        }
    }

    func testTheAcceptedVersionIsTheRollbackFloor() {
        let state = InMemorySyncStateStore()
        let service = CountersSyncService(fetcher: fetcher(), syncState: state)
        XCTAssertNil(service.acceptedVersion())
        service.confirmSynced(CountersManifest(version: "1.4.0", sha256: "x"))
        XCTAssertEqual(service.acceptedVersion(), "1.4.0")
    }
}
