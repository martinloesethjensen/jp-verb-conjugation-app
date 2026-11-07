import XCTest
import SwiftData
@testable import VerbKit

enum KanjiJSON {
    static func file(schema: Int = 1, extra: String = "") -> Data {
        Data("""
        {"schema":\(schema),"sources":{"kanjivg":"20260714","kanjidic2":"2026-11-07"},"license":"l",
         "kanji":{
          "人":{"strokes":["M54,10c0,0,0,1,0,2","M55,40c1,1,2,2,3,3"],"grade":1,"on":["ジン","ニン"],"kun":["ひと"],"meanings":["person"]},
          "食":{"strokes":["M52.75,10.5c0.11,0.98-0.19,2.67-0.97,3.93C45,25.34,31.75,41.19,14,51.5"],"on":["ショク"],"kun":[],"meanings":["eat","food"]}\(extra)
         }}
        """.utf8)
    }

    /// The same two kanji plus 山, so a test can tell which copy is in use.
    static var newer: Data {
        file(extra: #","山":{"strokes":["M50,10c0,1,0,2,0,3"],"grade":1,"on":["サン"],"kun":["やま"],"meanings":["mountain"]}"#)
    }
}

final class KanjiDataFileTests: XCTestCase {
    func testDecodesEntriesKeyedByCharacter() throws {
        let file = try KanjiDataFile.decode(KanjiJSON.file())
        XCTAssertEqual(Set(file.entries.keys), ["人", "食"])
        let person = try XCTUnwrap(file.entries["人"])
        XCTAssertEqual(person.character, "人")
        XCTAssertEqual(person.strokes.count, 2)
        XCTAssertEqual(person.grade, 1)
        XCTAssertEqual(person.on, ["ジン", "ニン"])
        XCTAssertEqual(person.kun, ["ひと"])
        XCTAssertEqual(person.meanings, ["person"])
        let eat = try XCTUnwrap(file.entries["食"])
        XCTAssertNil(eat.grade)
        XCTAssertEqual(eat.kun, [])
    }

    func testANewerMajorSchemaIsRefused() {
        XCTAssertThrowsError(try KanjiDataFile.decode(KanjiJSON.file(schema: 2))) { error in
            XCTAssertEqual(error as? KanjiDataFile.LoadError, .unsupportedSchema(2))
        }
    }

    func testGarbageIsMalformed() {
        XCTAssertThrowsError(try KanjiDataFile.decode(Data("not json".utf8))) { error in
            XCTAssertEqual(error as? KanjiDataFile.LoadError, .malformed)
        }
        XCTAssertThrowsError(try KanjiDataFile.decode(Data(#"{"schema":1,"kanji":{"ab":{"strokes":[]}}}"#.utf8))) { error in
            XCTAssertEqual(error as? KanjiDataFile.LoadError, .malformed)
        }
    }

    func testANewerSchemaIsTheNeedsAppUpdateProblem() {
        XCTAssertEqual(DataSyncProblem(syncError: KanjiDataFile.LoadError.unsupportedSchema(2)), .needsAppUpdate)
    }
}

final class KanjiSyncServiceTests: XCTestCase {
    private let data = KanjiJSON.file()

    func testSyncVerifiesTheHashAndDecodesButDoesNotConfirm() async throws {
        let fetcher = MockVerbDataFetcher()
        fetcher.kanjiManifestResult = .success(KanjiManifest(version: "1.0.0", sha256: sha256Hex(of: data)))
        fetcher.kanjiDataResult = .success(data)
        let state = InMemorySyncStateStore()
        let service = KanjiSyncService(fetcher: fetcher, syncState: state)
        guard case let .updated(manifest, bytes, file) = try await service.sync() else { return XCTFail("expected updated") }
        XCTAssertEqual(bytes, data)
        XCTAssertEqual(file.entries.count, 2)
        XCTAssertNil(state.lastSyncedKanjiManifest())
        service.confirmSynced(manifest)
        XCTAssertEqual(state.lastSyncedKanjiManifest(), manifest)
        XCTAssertEqual(state.highestAcceptedVersion(for: "kanji"), "1.0.0")
        XCTAssertEqual(service.acceptedVersion(), "1.0.0")
        let again = try await service.sync()
        XCTAssertEqual(again, .upToDate)
    }

    func testNoKanjiEntryIsUpToDate() async throws {
        let result = try await KanjiSyncService(fetcher: MockVerbDataFetcher(), syncState: InMemorySyncStateStore()).sync()
        XCTAssertEqual(result, .upToDate)
    }

    func testAHashMismatchIsMalformed() async {
        let fetcher = MockVerbDataFetcher()
        fetcher.kanjiManifestResult = .success(KanjiManifest(version: "1.0.0", sha256: "bad"))
        fetcher.kanjiDataResult = .success(data)
        do {
            _ = try await KanjiSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore()).sync()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? VerbSyncError, .malformedData)
        }
    }

    func testAnOlderVersionThanOneAcceptedIsRefused() async {
        let fetcher = MockVerbDataFetcher()
        fetcher.kanjiManifestResult = .success(KanjiManifest(version: "1.0.0", sha256: sha256Hex(of: data)))
        fetcher.kanjiDataResult = .success(data)
        let state = InMemorySyncStateStore()
        state.saveHighestAcceptedVersion("1.2.0", for: "kanji")
        do {
            _ = try await KanjiSyncService(fetcher: fetcher, syncState: state).sync()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? VerbSyncError, .untrusted)
        }
    }

    func testANewerMajorSchemaIsRefusedAndNotRecorded() async {
        let newer = KanjiJSON.file(schema: 2)
        let fetcher = MockVerbDataFetcher()
        fetcher.kanjiManifestResult = .success(KanjiManifest(version: "2.0.0", sha256: sha256Hex(of: newer)))
        fetcher.kanjiDataResult = .success(newer)
        let state = InMemorySyncStateStore()
        do {
            _ = try await KanjiSyncService(fetcher: fetcher, syncState: state).sync()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? KanjiDataFile.LoadError, .unsupportedSchema(2))
        }
        XCTAssertNil(state.lastSyncedKanjiManifest())
        XCTAssertNil(state.highestAcceptedVersion(for: "kanji"))
    }

    func testUnreadableJSONWithAMatchingHashIsMalformed() async {
        let junk = Data("{}".utf8)
        let fetcher = MockVerbDataFetcher()
        fetcher.kanjiManifestResult = .success(KanjiManifest(version: "1.0.0", sha256: sha256Hex(of: junk)))
        fetcher.kanjiDataResult = .success(junk)
        do {
            _ = try await KanjiSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore()).sync()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? VerbSyncError, .malformedData)
        }
    }
}

@MainActor
final class KanjiStoreTests: XCTestCase {
    private let suite = "KanjiStoreTests"
    private var defaults: UserDefaults!

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    final class MemoryPersisting: KanjiPersisting {
        var stored: SyncedKanjiData?
        var failSaves = false
        func loadKanji() throws -> SyncedKanjiData? { stored }
        func replaceKanji(with synced: SyncedKanjiData) throws {
            if failSaves { throw CocoaError(.fileWriteUnknown) }
            stored = synced
        }
    }

    private var bundled: BundledKanji {
        let data = KanjiJSON.file()
        return BundledKanji(data: data, version: "1.0.0", sha256: sha256Hex(of: data))
    }

    private func makeStore(
        fetcher: MockVerbDataFetcher = MockVerbDataFetcher(), persisting: MemoryPersisting? = nil,
        state: InMemorySyncStateStore = InMemorySyncStateStore(), status: DataSyncStatus? = nil,
        bundled: BundledKanji?? = nil
    ) -> KanjiStore {
        KanjiStore(syncService: KanjiSyncService(fetcher: fetcher, syncState: state), persisting: persisting ?? MemoryPersisting(),
                   syncStatus: status, bundled: bundled ?? self.bundled)
    }

    func testOfflineFirstLaunchUsesTheBundledCopy() async {
        let fetcher = MockVerbDataFetcher()
        fetcher.kanjiManifestResult = .failure(VerbSyncError.offline)
        let status = DataSyncStatus(defaults: defaults)
        let store = makeStore(fetcher: fetcher, status: status)
        XCTAssertNil(store.entry(for: "人"))

        await store.start()

        XCTAssertEqual(store.entry(for: "人")?.meanings, ["person"])
        XCTAssertEqual(store.version, "1.0.0")
        XCTAssertEqual(status.status(for: .kanji).version, "1.0.0")
        XCTAssertEqual(status.status(for: .kanji).problem, .offline)
    }

    func testANewerVerifiedCopyIsPersistedAndUsed() async {
        let fetcher = MockVerbDataFetcher()
        fetcher.kanjiManifestResult = .success(KanjiManifest(version: "1.1.0", sha256: sha256Hex(of: KanjiJSON.newer)))
        fetcher.kanjiDataResult = .success(KanjiJSON.newer)
        let persisting = MemoryPersisting()
        let state = InMemorySyncStateStore()
        let store = makeStore(fetcher: fetcher, persisting: persisting, state: state)

        await store.start()

        XCTAssertNotNil(store.entry(for: "山"))
        XCTAssertEqual(store.version, "1.1.0")
        XCTAssertEqual(persisting.stored?.manifest.version, "1.1.0")
        XCTAssertEqual(state.lastSyncedKanjiManifest()?.version, "1.1.0")
    }

    func testACachedNewerCopyIsUsedOnLaunch() async {
        let fetcher = MockVerbDataFetcher()
        fetcher.kanjiManifestResult = .failure(VerbSyncError.offline)
        let persisting = MemoryPersisting()
        persisting.stored = SyncedKanjiData(
            manifest: KanjiManifest(version: "1.1.0", sha256: sha256Hex(of: KanjiJSON.newer)), data: KanjiJSON.newer)
        let store = makeStore(fetcher: fetcher, persisting: persisting)
        await store.start()
        XCTAssertNotNil(store.entry(for: "山"))
        XCTAssertEqual(store.version, "1.1.0")
    }

    func testABadCachedCopyFallsBackToTheBundledOne() async {
        let fetcher = MockVerbDataFetcher()
        fetcher.kanjiManifestResult = .failure(VerbSyncError.offline)
        let persisting = MemoryPersisting()
        persisting.stored = SyncedKanjiData(manifest: KanjiManifest(version: "1.1.0", sha256: "tampered"),
                                            data: KanjiJSON.newer)
        let store = makeStore(fetcher: fetcher, persisting: persisting)
        await store.start()
        XCTAssertNil(store.entry(for: "山"))
        XCTAssertEqual(store.version, "1.0.0")
    }

    func testACachedCopyOlderThanTheBundledOneIsNotUsed() async {
        let fetcher = MockVerbDataFetcher()
        fetcher.kanjiManifestResult = .failure(VerbSyncError.offline)
        let persisting = MemoryPersisting()
        persisting.stored = SyncedKanjiData(
            manifest: KanjiManifest(version: "0.9.0", sha256: sha256Hex(of: KanjiJSON.newer)), data: KanjiJSON.newer)
        let store = makeStore(fetcher: fetcher, persisting: persisting)
        await store.start()
        XCTAssertNil(store.entry(for: "山"))
    }

    func testAFailedSaveKeepsTheDataAndRetriesNextTime() async {
        let fetcher = MockVerbDataFetcher()
        fetcher.kanjiManifestResult = .success(KanjiManifest(version: "1.1.0", sha256: sha256Hex(of: KanjiJSON.newer)))
        fetcher.kanjiDataResult = .success(KanjiJSON.newer)
        let persisting = MemoryPersisting()
        persisting.failSaves = true
        let state = InMemorySyncStateStore()
        let status = DataSyncStatus(defaults: defaults)
        let store = makeStore(fetcher: fetcher, persisting: persisting, state: state, status: status)

        await store.start()

        XCTAssertNil(store.entry(for: "山"))
        XCTAssertNil(state.lastSyncedKanjiManifest())
        XCTAssertEqual(status.status(for: .kanji).problem, .couldNotSave)
    }

    func testKanjiInTextSkipsUnknownAndRepeats() async {
        let fetcher = MockVerbDataFetcher()
        fetcher.kanjiManifestResult = .failure(VerbSyncError.offline)
        let store = makeStore(fetcher: fetcher)
        await store.start()
        XCTAssertEqual(store.kanji(in: ["人々が食べる", "食", "鬱"]), ["人", "食"])
        XCTAssertEqual(store.kanji(in: ["たべる"]), [])
    }

    func testWithoutAnyDataNothingIsKnown() async {
        let fetcher = MockVerbDataFetcher()
        fetcher.kanjiManifestResult = .failure(VerbSyncError.offline)
        let store = makeStore(fetcher: fetcher, bundled: .some(nil))
        await store.start()
        XCTAssertNil(store.entry(for: "人"))
        XCTAssertEqual(store.kanji(in: ["人"]), [])
    }

    func testSwiftDataRoundTripsTheSyncedData() throws {
        let container = try VerbModelContainer.makeInMemory()
        let persisting = SwiftDataKanjiPersisting(modelContext: ModelContext(container))
        XCTAssertNil(try persisting.loadKanji())
        let first = SyncedKanjiData(manifest: KanjiManifest(version: "1.1.0", sha256: "a"), data: Data("one".utf8))
        let second = SyncedKanjiData(manifest: KanjiManifest(version: "1.2.0", sha256: "b"), data: Data("two".utf8))
        try persisting.replaceKanji(with: first)
        try persisting.replaceKanji(with: second)
        XCTAssertEqual(try persisting.loadKanji(), second)
    }

    func testTheSyncStateRemembersTheKanjiManifestPerBuild() {
        let old = UserDefaultsSyncStateStore(defaults: defaults, build: "1")
        old.saveLastSyncedKanjiManifest(KanjiManifest(version: "1.0.0", sha256: "k"))
        XCTAssertEqual(old.lastSyncedKanjiManifest(), KanjiManifest(version: "1.0.0", sha256: "k"))
        XCTAssertNil(UserDefaultsSyncStateStore(defaults: defaults, build: "2").lastSyncedKanjiManifest())
    }

    func testTheRealBundledCopyLoads() throws {
        let bundled = try XCTUnwrap(BundledKanji.load())
        let file = try KanjiDataFile.decode(bundled.data)
        XCTAssertGreaterThanOrEqual(file.entries.count, 2136)
        XCTAssertEqual(file.entries["食"]?.strokes.count, 9)
    }
}
