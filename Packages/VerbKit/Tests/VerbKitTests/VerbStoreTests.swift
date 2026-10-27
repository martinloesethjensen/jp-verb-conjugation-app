import XCTest
import SwiftData
@testable import VerbKit

@MainActor
final class VerbStoreTests: XCTestCase {
    private func fixtureData() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "verbs-fixture", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func makePersisting() throws -> SwiftDataVerbPersisting {
        let container = try VerbModelContainer.makeInMemory()
        return SwiftDataVerbPersisting(modelContext: ModelContext(container))
    }

    func testFirstLaunchSuccessPopulatesVerbsAndPersists() async throws {
        let data = try fixtureData()
        let manifest = VerbManifest(version: "1.0.0", sha256: sha256Hex(of: data))
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .success(manifest)
        fetcher.verbDataResult = .success(data)

        let persisting = try makePersisting()
        let syncService = VerbSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore())
        let store = VerbStore(syncService: syncService, persisting: persisting, networkMonitor: NetworkMonitor())

        await store.start()

        XCTAssertEqual(store.firstLaunchState, .success)
        XCTAssertEqual(store.verbs.count, 2)
        XCTAssertTrue(store.hasLocalData)
        XCTAssertEqual(try persisting.loadAllVerbs().count, 2)
    }

    func testFirstLaunchOfflineFailureSetsFailedState() async throws {
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .failure(VerbSyncError.offline)

        let syncService = VerbSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore())
        let store = VerbStore(syncService: syncService, persisting: try makePersisting(), networkMonitor: NetworkMonitor())

        await store.start()

        XCTAssertEqual(store.firstLaunchState, .failed(.offline))
        XCTAssertTrue(store.verbs.isEmpty)
    }

    func testFirstLaunchServerUnreachableFailureSetsFailedState() async throws {
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .failure(VerbSyncError.serverUnreachable)

        let syncService = VerbSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore())
        let store = VerbStore(syncService: syncService, persisting: try makePersisting(), networkMonitor: NetworkMonitor())

        await store.start()

        XCTAssertEqual(store.firstLaunchState, .failed(.serverUnreachable))
    }

    func testManualRetryAfterFailureCanSucceed() async throws {
        let data = try fixtureData()
        let manifest = VerbManifest(version: "1.0.0", sha256: sha256Hex(of: data))
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .failure(VerbSyncError.offline)

        let syncService = VerbSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore())
        let store = VerbStore(syncService: syncService, persisting: try makePersisting(), networkMonitor: NetworkMonitor())

        await store.start()
        XCTAssertEqual(store.firstLaunchState, .failed(.offline))

        fetcher.manifestResult = .success(manifest)
        fetcher.verbDataResult = .success(data)
        await store.retryFirstLaunch()

        XCTAssertEqual(store.firstLaunchState, .success)
        XCTAssertEqual(store.verbs.count, 2)
    }

    func testReconnectCallbackRetriesAfterOfflineFailure() async throws {
        let data = try fixtureData()
        let manifest = VerbManifest(version: "1.0.0", sha256: sha256Hex(of: data))
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .failure(VerbSyncError.offline)

        let syncService = VerbSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore())
        let networkMonitor = NetworkMonitor()
        let store = VerbStore(syncService: syncService, persisting: try makePersisting(), networkMonitor: networkMonitor)

        await store.start()
        XCTAssertEqual(store.firstLaunchState, .failed(.offline))

        fetcher.manifestResult = .success(manifest)
        fetcher.verbDataResult = .success(data)

        // NetworkMonitor's real NWPathMonitor was never started (VerbStore
        // only assigns onChange, doesn't call start()), so this manual
        // call is the only thing that can trigger it here — deterministic.
        networkMonitor.onChange?(true)
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(store.firstLaunchState, .success)
    }

    func testFirstLaunchPersistenceFailureLeavesManifestUnsavedSoRetryCanRefetch() async throws {
        // Important #4 of the final whole-branch review: if persistence
        // fails on first launch, the manifest must NOT be recorded as
        // synced — otherwise every later retry sees `.upToDate` with no
        // verbs ever persisted, and the user is stuck forever.
        let data = try fixtureData()
        let manifest = VerbManifest(version: "1.0.0", sha256: sha256Hex(of: data))
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .success(manifest)
        fetcher.verbDataResult = .success(data)

        let syncState = InMemorySyncStateStore()
        let syncService = VerbSyncService(fetcher: fetcher, syncState: syncState)
        let persisting = FailingVerbPersisting(shouldFail: true)
        let store = VerbStore(syncService: syncService, persisting: persisting, networkMonitor: NetworkMonitor())

        await store.start()

        XCTAssertTrue(store.verbs.isEmpty)
        guard case .failed = store.firstLaunchState else {
            return XCTFail("expected a failed state when persistence throws")
        }
        XCTAssertNil(syncState.lastSyncedManifest(), "manifest must stay unrecorded when persistence fails")

        // Fix the persistence layer and retry: since the manifest was
        // never recorded, sync() must actually re-fetch and succeed
        // rather than short-circuiting to `.upToDate`.
        persisting.shouldFail = false
        await store.retryFirstLaunch()

        XCTAssertEqual(store.firstLaunchState, .success)
        XCTAssertEqual(store.verbs.count, 2)
        XCTAssertEqual(syncState.lastSyncedManifest(), manifest)
    }

    func testBackgroundSyncPersistenceFailureLeavesManifestUnsavedAndVerbsUnchanged() async throws {
        let seedVerb = Verb(
            type: .u, label: "U-verb", dict: "のむ", kanji: nil, meaning: "to drink", description: "d",
            forms: VerbForms(masuPos: "a", masuNeg: "b", masuPast: "c", masuPastNeg: "d", te: "e", shortPos: "f", shortNeg: "g", shortPast: "h", shortPastNeg: "i"),
            examples: []
        )
        let persisting = FailingVerbPersisting(initialVerbs: [seedVerb], shouldFail: true)

        let data = try fixtureData()
        let manifest = VerbManifest(version: "2.0.0", sha256: sha256Hex(of: data))
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .success(manifest)
        fetcher.verbDataResult = .success(data)

        let syncState = InMemorySyncStateStore()
        let syncService = VerbSyncService(fetcher: fetcher, syncState: syncState)
        let store = VerbStore(syncService: syncService, persisting: persisting, networkMonitor: NetworkMonitor())

        // Cached path: loads seedVerb locally, then syncInBackground()
        // fetches a changed manifest but fails to persist it.
        await store.start()

        XCTAssertEqual(store.verbs.map(\.dict), [seedVerb.dict], "in-memory verbs must stay untouched when the background persist fails")
        XCTAssertNil(syncState.lastSyncedManifest(), "manifest must stay unrecorded so a later sync retries instead of reporting up to date")
    }

    func testExistingLocalDataSkipsFirstLaunchFlowAndSyncsInBackground() async throws {
        let persisting = try makePersisting()
        let seedVerb = Verb(
            type: .u, label: "U-verb", dict: "のむ", kanji: nil, meaning: "to drink", description: "d",
            forms: VerbForms(masuPos: "a", masuNeg: "b", masuPast: "c", masuPastNeg: "d", te: "e", shortPos: "f", shortNeg: "g", shortPast: "h", shortPastNeg: "i"),
            examples: []
        )
        try persisting.replaceAllVerbs(with: [seedVerb])

        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .failure(VerbSyncError.offline) // background sync fails silently
        let syncService = VerbSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore())
        let store = VerbStore(syncService: syncService, persisting: persisting, networkMonitor: NetworkMonitor())

        await store.start()

        XCTAssertEqual(store.verbs.map(\.dict), ["のむ"])
        XCTAssertEqual(store.firstLaunchState, .checking) // first-launch flow never entered
    }

    // MARK: the bundled copy

    /// A verb persisting wrapper that counts replaces and can be told to fail them.
    private final class RecordingVerbPersisting: VerbPersisting, @unchecked Sendable {
        let base: VerbPersisting
        var replaces = 0
        var failReplace = false
        init(_ base: VerbPersisting) { self.base = base }
        func loadAllVerbs() throws -> [Verb] { try base.loadAllVerbs() }
        func replaceAllVerbs(with verbs: [Verb]) throws {
            replaces += 1
            if failReplace { throw VerbSyncError.malformedData }
            try base.replaceAllVerbs(with: verbs)
        }
    }

    private struct FailingGrammarPersisting: GrammarPersisting {
        func loadAllGrammarPoints() throws -> [GrammarPoint] { [] }
        func loadAllTextbooks() throws -> [Textbook] { [] }
        func replaceAllGrammar(points: [GrammarPoint], textbooks: [Textbook]) throws { throw VerbSyncError.malformedData }
    }

    private func bundledVerbs(version: String = "1.0.0") throws -> BundledData<VerbDataFile> {
        let data = try fixtureData()
        return BundledData(
            value: try JSONDecoder().decode(VerbDataFile.self, from: data), version: version,
            sha256: sha256Hex(of: data), data: data
        )
    }

    private func offlineFetcher() -> MockVerbDataFetcher {
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .failure(VerbSyncError.offline)
        return fetcher
    }

    private func store(
        persisting: VerbPersisting, state: InMemorySyncStateStore = InMemorySyncStateStore(),
        verbs: BundledData<VerbDataFile>? = nil, grammar: BundledData<GrammarDataFile>? = nil,
        grammarPersisting: GrammarPersisting? = nil
    ) -> VerbStore {
        VerbStore(
            syncService: VerbSyncService(fetcher: offlineFetcher(), syncState: state),
            persisting: persisting, networkMonitor: NetworkMonitor(),
            grammarSyncService: grammar == nil && grammarPersisting == nil
                ? nil : GrammarSyncService(fetcher: offlineFetcher(), syncState: state),
            grammarPersisting: grammarPersisting, bundledVerbs: verbs, bundledGrammar: grammar
        )
    }

    func testAnOfflineFirstLaunchWithABundleShowsAndPersistsItsVerbs() async throws {
        let persisting = try makePersisting()
        let state = InMemorySyncStateStore()
        let store = store(persisting: persisting, state: state, verbs: try bundledVerbs())
        await store.start()
        XCTAssertTrue(store.hasLocalData)
        XCTAssertEqual(store.verbs.count, 2)
        XCTAssertEqual(try persisting.loadAllVerbs().count, 2, "widgets and intents read the persisted store")
        XCTAssertEqual(state.highestAcceptedVersion(for: "verbs"), "1.0.0")
        XCTAssertEqual(state.lastSyncedManifest()?.version, "1.0.0")
    }

    func testANewerBundleReplacesTheCacheOnce() async throws {
        let all = try JSONDecoder().decode(VerbDataFile.self, from: try fixtureData()).verbs
        let persisting = RecordingVerbPersisting(try makePersisting())
        try persisting.base.replaceAllVerbs(with: [all[0]])
        let state = InMemorySyncStateStore()
        state.saveHighestAcceptedVersion("0.9.0", for: "verbs")
        let store = store(persisting: persisting, state: state, verbs: try bundledVerbs())
        await store.start()
        XCTAssertEqual(store.verbs.count, 2)
        XCTAssertEqual(persisting.replaces, 1)
    }

    func testAnOlderBundleChangesNothing() async throws {
        let all = try JSONDecoder().decode(VerbDataFile.self, from: try fixtureData()).verbs
        let persisting = RecordingVerbPersisting(try makePersisting())
        try persisting.base.replaceAllVerbs(with: [all[0]])
        let state = InMemorySyncStateStore()
        state.saveHighestAcceptedVersion("2.0.0", for: "verbs")
        let store = store(persisting: persisting, state: state, verbs: try bundledVerbs(version: "1.0.0"))
        await store.start()
        XCTAssertEqual(store.verbs.count, 1)
        XCTAssertEqual(persisting.replaces, 0)
        XCTAssertEqual(state.highestAcceptedVersion(for: "verbs"), "2.0.0")
    }

    func testAnEqualVersionDoesNotReinstall() async throws {
        let persisting = RecordingVerbPersisting(try makePersisting())
        try persisting.base.replaceAllVerbs(with: JSONDecoder().decode(VerbDataFile.self, from: try fixtureData()).verbs)
        let state = InMemorySyncStateStore()
        state.saveHighestAcceptedVersion("1.0.0", for: "verbs")
        let store = store(persisting: persisting, state: state, verbs: try bundledVerbs())
        await store.start()
        XCTAssertEqual(persisting.replaces, 0)
        XCTAssertEqual(store.verbs.count, 2)
    }

    func testAFailedInstallKeepsTheCacheAndRecordsNothing() async throws {
        let all = try JSONDecoder().decode(VerbDataFile.self, from: try fixtureData()).verbs
        let persisting = RecordingVerbPersisting(try makePersisting())
        try persisting.base.replaceAllVerbs(with: [all[0]])
        persisting.failReplace = true
        let state = InMemorySyncStateStore()
        let store = store(persisting: persisting, state: state, verbs: try bundledVerbs())
        await store.start()
        XCTAssertEqual(store.verbs.count, 1, "the old cache stays")
        XCTAssertNil(state.lastSyncedManifest())
        XCTAssertNil(state.highestAcceptedVersion(for: "verbs"))
    }

    func testTheGrammarBundleIsInstalledAndTheFloorRecorded() async throws {
        let grammar = try XCTUnwrap(BundledData<GrammarDataFile>.load(named: "grammar"))
        let state = InMemorySyncStateStore()
        let container = try VerbModelContainer.makeInMemory()
        let grammarPersisting = SwiftDataGrammarPersisting(modelContext: ModelContext(container))
        let store = store(
            persisting: try makePersisting(), state: state, verbs: try bundledVerbs(), grammar: grammar,
            grammarPersisting: grammarPersisting
        )
        await store.start()
        XCTAssertFalse(grammar.value.grammar.isEmpty)
        XCTAssertEqual(store.grammarPoints.count, grammar.value.grammar.count)
        XCTAssertEqual(try grammarPersisting.loadAllGrammarPoints().count, grammar.value.grammar.count)
        XCTAssertEqual(state.highestAcceptedVersion(for: "grammar"), grammar.version)
    }

    func testAGrammarInstallFailureDoesNotHideTheVerbs() async throws {
        let grammar = try XCTUnwrap(BundledData<GrammarDataFile>.load(named: "grammar"))
        let state = InMemorySyncStateStore()
        let store = store(
            persisting: try makePersisting(), state: state, verbs: try bundledVerbs(), grammar: grammar,
            grammarPersisting: FailingGrammarPersisting()
        )
        await store.start()
        XCTAssertEqual(store.verbs.count, 2)
        XCTAssertTrue(store.grammarPoints.isEmpty)
        XCTAssertNil(state.highestAcceptedVersion(for: "grammar"))
    }
}

/// A `VerbPersisting` mock whose `replaceAllVerbs(with:)` can be made to
/// throw on demand, so tests can simulate a persistence failure (e.g. the
/// in-memory SwiftData fallback being in use because the real App Group
/// container isn't available) independently of the real SwiftData stack.
private enum FailingVerbPersistingError: Error {
    case persistFailed
}

@MainActor
private final class FailingVerbPersisting: VerbPersisting {
    var shouldFail: Bool
    private var stored: [Verb]

    init(initialVerbs: [Verb] = [], shouldFail: Bool) {
        self.stored = initialVerbs
        self.shouldFail = shouldFail
    }

    func loadAllVerbs() throws -> [Verb] { stored }

    func replaceAllVerbs(with verbs: [Verb]) throws {
        if shouldFail { throw FailingVerbPersistingError.persistFailed }
        stored = verbs
    }
}
