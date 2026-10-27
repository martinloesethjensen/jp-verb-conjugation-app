import SwiftData
import XCTest
@testable import VerbKit

/// The real `data/forms.json`, and variants of it, for the catalogue sync and drift tests.
enum FormsJSON {
    static var repoRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }

    static func published() throws -> Data {
        try Data(contentsOf: repoRoot.appendingPathComponent("data/forms.json"))
    }

    /// The published catalogue as a JSON object, changed by `edit`, then serialized.
    static func edited(_ edit: (inout [String: Any]) -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: try published()) as? [String: Any])
        edit(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    /// What a newer catalogue could look like to this build: a new field everywhere, a new
    /// form in a known family, a new family with a form, facet values and a word class this
    /// build does not know, and one form it cannot read at all.
    static func newer() throws -> Data {
        try edited { doc in
            doc["schema"] = 1
            doc["released"] = "2027-01-01"
            var families = doc["families"] as! [[String: Any]]
            families.append(["id": "keigo", "title": "Keigo", "icon": "crown"])
            doc["families"] = families
            var forms = (doc["forms"] as! [[String: Any]]).map { form -> [String: Any] in
                var form = form
                form["audio"] = true
                return form
            }
            forms.append([
                "id": "zu_ni", "family": "other", "label": "Without doing (ずに)", "name": "Without doing (ずに)",
                "role": "derived", "applies_to": ["verb", "adverb"], "source": "derived", "grammar": "zu-ni",
                "register": "literary", "mood": "irrealis",
            ])
            forms.append([
                "id": "sonkeigo", "family": "keigo", "label": "Honorific", "role": "derived",
                "applies_to": ["verb"], "source": "derived",
            ])
            forms.append([
                "id": "mystery", "family": "other", "label": "Mystery", "role": "auxiliary-chain",
                "applies_to": ["verb"], "source": "derived",
            ])
            forms.append(["id": "orphan", "family": "nowhere", "label": "Orphan", "role": "derived",
                          "applies_to": ["verb"], "source": "derived"])
            doc["forms"] = forms
        }
    }
}

// MARK: - Drift: an older app reading a newer catalogue

final class FormCatalogueDriftTests: XCTestCase {
    func testAnOlderAppReadsANewerCatalogueAndIgnoresWhatItDoesNotKnow() throws {
        let catalogue = try FormCatalogue.replacement(data: try FormsJSON.newer(), version: "1.1.0")
        let bundled = FormCatalogue.bundled

        // Every form it knew is still there, unchanged.
        for spec in bundled.forms {
            XCTAssertEqual(catalogue.spec(for: spec.id), spec, spec.id.rawValue)
        }
        // A new form in a known family, with its unknown facet values and word class dropped.
        let zuNi = try XCTUnwrap(catalogue.spec(for: "zu_ni"))
        XCTAssertEqual(zuNi.label, "Without doing (ずに)")
        XCTAssertNil(zuNi.register)
        XCTAssertEqual(zuNi.appliesTo, [.verb])
        // A new family is data, so it is kept; a form whose role it cannot read, or whose
        // family is not declared, is skipped without failing the rest.
        XCTAssertEqual(catalogue.families.map(\.id), bundled.families.map(\.id) + ["keigo"])
        XCTAssertNotNil(catalogue.spec(for: "sonkeigo"))
        XCTAssertNil(catalogue.spec(for: "mystery"))
        XCTAssertNil(catalogue.spec(for: "orphan"))
        XCTAssertEqual(catalogue.forms.count, bundled.forms.count + 2)
    }

    func testTheQuizTakesNewFormsInKnownTopicsAndSkipsUnknownFamilies() throws {
        let catalogue = try FormCatalogue.replacement(data: try FormsJSON.newer(), version: "1.1.0")
        let quiz = QuizForm.forms(in: catalogue)
        let zuNi = try XCTUnwrap(quiz.first { $0.id == "zu_ni" })
        XCTAssertEqual(zuNi.topic, .otherForms)
        XCTAssertEqual(zuNi.label, "Without doing (ずに)")
        XCTAssertFalse(quiz.contains { $0.id == "sonkeigo" }, "keigo has no quiz topic in this build")
        XCTAssertEqual(quiz.count, QuizForm.forms(in: .bundled).count + 1)
    }

    func testANewFormInTheVerbDataReachesTheQuizWithoutANewField() throws {
        let json = #"""
        {"masu_pos":"たべます","masu_neg":"たべません","masu_past":"たべました","masu_past_neg":"たべませんでした",
         "te":"たべて","short_pos":"たべる","short_neg":"たべない","short_past":"たべた","short_past_neg":"たべなかった",
         "potential":"たべられる","zu_ni":"たべずに","future_shape":{"not":"a string"}}
        """#
        let forms = try JSONDecoder().decode(VerbForms.self, from: Data(json.utf8))
        XCTAssertEqual(forms.potential, "たべられる")
        XCTAssertEqual(forms.extra, ["zu_ni": "たべずに"])
        XCTAssertEqual(forms[id: "zu_ni"], "たべずに")
        XCTAssertEqual(forms[id: .masuPos], "たべます")
        XCTAssertEqual(forms[id: "potential"], "たべられる")
        XCTAssertNil(forms[id: "passive"])

        // Kept through a save (VerbEntity stores the encoded forms) and in the Word bridge.
        let again = try JSONDecoder().decode(VerbForms.self, from: JSONEncoder().encode(forms))
        XCTAssertEqual(again, forms)
        let catalogue = try FormCatalogue.replacement(data: try FormsJSON.newer(), version: "1.1.0")
        let zuNi = try XCTUnwrap(QuizForm.forms(in: catalogue).first { $0.id == "zu_ni" })
        XCTAssertEqual(zuNi.value(in: forms), "たべずに")
    }

    func testFormIDConstantsFallBackWhenACatalogueLacksThem() throws {
        let withoutPotential = try FormsJSON.edited { doc in
            doc["forms"] = (doc["forms"] as! [[String: Any]]).filter { ($0["id"] as! String) != "potential" }
        }
        let catalogue = try FormCatalogue.replacement(data: withoutPotential, version: "1.1.0")
        XCTAssertNil(catalogue.spec(for: .potential))
        XCTAssertEqual(catalogue.label(for: .potential), "Potential · plain", "falls back to the bundled label")
        XCTAssertEqual(catalogue.label(for: "never_heard_of"), "never_heard_of")
        XCTAssertFalse(QuizForm.forms(in: catalogue).contains { $0.id == "potential" })
    }

    func testACatalogueWithoutTheFormsCodeNeedsIsRefused() throws {
        let withoutTe = try FormsJSON.edited { doc in
            doc["forms"] = (doc["forms"] as! [[String: Any]]).filter { ($0["id"] as! String) != "te" }
        }
        XCTAssertThrowsError(try FormCatalogue.replacement(data: withoutTe, version: "1.1.0")) { error in
            XCTAssertEqual(error as? FormCatalogue.LoadError, .missingRequiredForms(["te"]))
        }
    }

    // MARK: Schema

    func testANewerMajorSchemaIsRefused() throws {
        for schema: Any in [2, "2.0"] {
            let data = try FormsJSON.edited { $0["schema"] = schema }
            XCTAssertThrowsError(try FormCatalogue(data: data)) { error in
                XCTAssertEqual(error as? FormCatalogue.LoadError, .unsupportedSchema(2))
            }
        }
        // Even when the rest has changed shape beyond recognition, it is reported as too new.
        let reshaped = Data(#"{"schema": 3, "forms": {"by_id": {}}}"#.utf8)
        XCTAssertThrowsError(try FormCatalogue(data: reshaped)) { error in
            XCTAssertEqual(error as? FormCatalogue.LoadError, .unsupportedSchema(3))
        }
    }

    func testAMinorSchemaBumpIsAccepted() throws {
        let data = try FormsJSON.edited { $0["schema"] = "1.4" }
        XCTAssertEqual(try FormCatalogue(data: data).schema, 1)
    }

    func testGarbageIsMalformed() {
        for text in ["nope", "{}", #"{"schema": 1, "families": [], "forms": []}"#] {
            XCTAssertThrowsError(try FormCatalogue(data: Data(text.utf8))) { error in
                XCTAssertEqual(error as? FormCatalogue.LoadError, .malformed, text)
            }
        }
    }
}

// MARK: - The quiz reads the catalogue

final class QuizFormCatalogueTests: XCTestCase {
    func testQuizFormsAreTheBundledCataloguesVerbForms() {
        let quiz = QuizForm.forms(in: .bundled)
        let verbSpecs = FormCatalogue.bundled.specs(for: .verb)
        XCTAssertEqual(Set(quiz.map(\.id)), Set(verbSpecs.map(\.id.rawValue)))
        for form in quiz {
            let spec = FormCatalogue.bundled.spec(for: FormID(rawValue: form.id))
            XCTAssertEqual(spec?.label, form.label, form.id)
            XCTAssertEqual(spec?.family, form.topic.family, form.id)
        }
        // Grouped by topic, in the catalogue's family order.
        XCTAssertEqual(quiz.map(\.topic).reduce(into: [QuizTopic]()) { if $0.last != $1 { $0.append($1) } },
                       [.basic, .potential, .nDesu, .auxiliaries, .otherForms])
    }

    func testAllFollowsTheCurrentCatalogue() throws {
        XCTAssertEqual(QuizForm.all, QuizForm.forms(in: FormCatalogue.current))
    }

    func testEveryTopicHasAFamilyAndBack() {
        for topic in QuizTopic.allCases {
            XCTAssertEqual(QuizTopic(family: topic.family), topic)
        }
        XCTAssertNil(QuizTopic(family: "keigo"))
    }
}

// MARK: - Fetching and verifying forms.json

final class FormsSyncServiceTests: XCTestCase {
    private func fetcher(_ data: Data, version: String = "1.1.0", sha: String? = nil) -> MockVerbDataFetcher {
        let fetcher = MockVerbDataFetcher()
        fetcher.formsManifestResult = .success(FormsManifest(version: version, sha256: sha ?? sha256Hex(of: data)))
        fetcher.formsDataResult = .success(data)
        return fetcher
    }

    func testSyncVerifiesTheHashAndDecodesButDoesNotConfirm() async throws {
        let data = try FormsJSON.newer()
        let state = InMemorySyncStateStore()
        let service = FormsSyncService(fetcher: fetcher(data), syncState: state)
        guard case let .updated(manifest, synced) = try await service.sync() else { return XCTFail("expected updated") }
        XCTAssertEqual(synced, data)
        XCTAssertNil(state.lastSyncedFormsManifest())

        service.confirmSynced(manifest)
        XCTAssertEqual(state.lastSyncedFormsManifest(), manifest)
        XCTAssertEqual(state.highestAcceptedVersion(for: "forms"), "1.1.0")
        let again = try await service.sync()
        XCTAssertEqual(again, .upToDate)
    }

    func testNoFormsEntryIsUpToDate() async throws {
        let result = try await FormsSyncService(fetcher: MockVerbDataFetcher(), syncState: InMemorySyncStateStore()).sync()
        XCTAssertEqual(result, .upToDate)
    }

    func testAHashMismatchIsMalformed() async throws {
        let service = FormsSyncService(fetcher: fetcher(try FormsJSON.published(), sha: "not-it"), syncState: InMemorySyncStateStore())
        do {
            _ = try await service.sync()
            XCTFail("expected malformedData")
        } catch VerbSyncError.malformedData {
            // expected
        }
    }

    func testAnOlderVersionThanOneAcceptedIsRefused() async throws {
        let state = InMemorySyncStateStore()
        state.saveHighestAcceptedVersion("1.2.0", for: "forms")
        let service = FormsSyncService(fetcher: fetcher(try FormsJSON.published()), syncState: state)
        do {
            _ = try await service.sync()
            XCTFail("expected untrusted")
        } catch VerbSyncError.untrusted {
            // expected
        }
    }

    func testANewerMajorSchemaIsRefusedAndNotRecorded() async throws {
        let state = InMemorySyncStateStore()
        let service = FormsSyncService(fetcher: fetcher(try FormsJSON.edited { $0["schema"] = 2 }), syncState: state)
        do {
            _ = try await service.sync()
            XCTFail("expected unsupportedSchema")
        } catch FormCatalogue.LoadError.unsupportedSchema(2) {
            // expected
        }
        XCTAssertNil(state.highestAcceptedVersion(for: "forms"))
        XCTAssertEqual(DataSyncProblem(syncError: FormCatalogue.LoadError.unsupportedSchema(2)), .needsAppUpdate)
    }

    func testUnreadableJSONWithAMatchingHashIsMalformed() async throws {
        let service = FormsSyncService(fetcher: fetcher(Data("nope".utf8)), syncState: InMemorySyncStateStore())
        do {
            _ = try await service.sync()
            XCTFail("expected malformedData")
        } catch VerbSyncError.malformedData {
            // expected
        }
    }
}

// MARK: - The store: bundled first, then a newer verified synced copy

@MainActor
final class FormCatalogueStoreTests: XCTestCase {
    private final class MemoryPersisting: FormCataloguePersisting {
        var stored: SyncedFormCatalogue?
        var failSaves = false
        func loadFormCatalogue() throws -> SyncedFormCatalogue? { stored }
        func replaceFormCatalogue(with synced: SyncedFormCatalogue) throws {
            if failSaves { throw VerbSyncError.malformedData }
            stored = synced
        }
    }

    private var defaults: UserDefaults!
    private let suite = "FormCatalogueStoreTests"
    private var installed: [FormCatalogue] = []

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        installed = []
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func bundled() throws -> FormCatalogue {
        try FormCatalogue(data: try FormsJSON.published(), version: "1.0.0")
    }

    private func makeStore(
        fetcher: MockVerbDataFetcher, persisting: MemoryPersisting, state: InMemorySyncStateStore = InMemorySyncStateStore(),
        status: DataSyncStatus? = nil
    ) throws -> FormCatalogueStore {
        FormCatalogueStore(
            syncService: FormsSyncService(fetcher: fetcher, syncState: state),
            persisting: persisting, syncStatus: status, bundled: try bundled(),
            install: { [unowned self] in self.installed.append($0) }
        )
    }

    func testOfflineFirstLaunchUsesTheBundledCopy() async throws {
        let fetcher = MockVerbDataFetcher()
        fetcher.formsManifestResult = .failure(VerbSyncError.offline)
        let status = DataSyncStatus(defaults: defaults)
        let store = try makeStore(fetcher: fetcher, persisting: MemoryPersisting(), status: status)

        await store.start()

        XCTAssertEqual(store.catalogue.version, "1.0.0")
        XCTAssertEqual(store.catalogue.forms.count, FormCatalogue.bundled.forms.count)
        XCTAssertEqual(installed.map(\.version), ["1.0.0"])
        XCTAssertEqual(status.status(for: .forms).version, "1.0.0", "Settings shows the bundled version")
        XCTAssertEqual(status.status(for: .forms).problem, .offline)
    }

    func testTheRealBundledCatalogueIsWhatAFirstLaunchQuizzes() {
        XCTAssertFalse(FormCatalogue.bundled.forms.isEmpty)
        XCTAssertEqual(FormCatalogue.bundled.version, FormCatalogue.bundledManifest?.version)
        XCTAssertEqual(QuizForm.forms(in: .bundled).count, 72)
    }

    func testANewerVerifiedCatalogueIsPersistedAndUsed() async throws {
        let data = try FormsJSON.newer()
        let fetcher = MockVerbDataFetcher()
        fetcher.formsManifestResult = .success(FormsManifest(version: "1.1.0", sha256: sha256Hex(of: data)))
        fetcher.formsDataResult = .success(data)
        let persisting = MemoryPersisting()
        let state = InMemorySyncStateStore()
        let status = DataSyncStatus(defaults: defaults)
        let store = try makeStore(fetcher: fetcher, persisting: persisting, state: state, status: status)

        await store.start()

        XCTAssertEqual(store.catalogue.version, "1.1.0")
        XCTAssertNotNil(store.catalogue.spec(for: "zu_ni"))
        XCTAssertEqual(installed.last?.version, "1.1.0")
        XCTAssertEqual(persisting.stored?.data, data)
        XCTAssertEqual(state.lastSyncedFormsManifest()?.version, "1.1.0")
        XCTAssertEqual(status.status(for: .forms).version, "1.1.0")
        XCTAssertNil(status.status(for: .forms).problem)

        // Next launch, offline: the cached copy is used again.
        fetcher.formsManifestResult = .failure(VerbSyncError.offline)
        let relaunch = try makeStore(fetcher: fetcher, persisting: persisting, state: state)
        relaunch.loadCached()
        XCTAssertEqual(relaunch.catalogue.version, "1.1.0")
    }

    func testANewerMajorSchemaKeepsTheCurrentCatalogue() async throws {
        let data = try FormsJSON.edited { $0["schema"] = 2 }
        let fetcher = MockVerbDataFetcher()
        fetcher.formsManifestResult = .success(FormsManifest(version: "2.0.0", sha256: sha256Hex(of: data)))
        fetcher.formsDataResult = .success(data)
        let persisting = MemoryPersisting()
        let status = DataSyncStatus(defaults: defaults)
        let store = try makeStore(fetcher: fetcher, persisting: persisting, status: status)

        await store.start()

        XCTAssertEqual(store.catalogue.version, "1.0.0")
        XCTAssertNil(persisting.stored)
        XCTAssertEqual(status.status(for: .forms).problem, .needsAppUpdate)
    }

    func testABadCachedCatalogueFallsBackToTheBundledOne() throws {
        let persisting = MemoryPersisting()
        // Tampered after it was saved: the hash no longer matches.
        persisting.stored = SyncedFormCatalogue(
            manifest: FormsManifest(version: "1.5.0", sha256: sha256Hex(of: try FormsJSON.published())),
            data: try FormsJSON.newer()
        )
        let store = try makeStore(fetcher: MockVerbDataFetcher(), persisting: persisting)
        store.loadCached()
        XCTAssertEqual(store.catalogue.version, "1.0.0")

        // Intact but unreadable by this build.
        let tooNew = try FormsJSON.edited { $0["schema"] = 2 }
        persisting.stored = SyncedFormCatalogue(manifest: FormsManifest(version: "1.5.0", sha256: sha256Hex(of: tooNew)), data: tooNew)
        let again = try makeStore(fetcher: MockVerbDataFetcher(), persisting: persisting)
        again.loadCached()
        XCTAssertEqual(again.catalogue.version, "1.0.0")
    }

    func testACachedCatalogueOlderThanTheBundledOneIsNotUsed() throws {
        let persisting = MemoryPersisting()
        let older = try FormsJSON.newer()
        persisting.stored = SyncedFormCatalogue(manifest: FormsManifest(version: "0.9.0", sha256: sha256Hex(of: older)), data: older)
        let store = try makeStore(fetcher: MockVerbDataFetcher(), persisting: persisting)
        store.loadCached()
        XCTAssertEqual(store.catalogue.version, "1.0.0")
        XCTAssertNil(store.catalogue.spec(for: "zu_ni"))
    }

    func testAFailedSaveKeepsTheCatalogueAndRetriesNextTime() async throws {
        let data = try FormsJSON.newer()
        let fetcher = MockVerbDataFetcher()
        fetcher.formsManifestResult = .success(FormsManifest(version: "1.1.0", sha256: sha256Hex(of: data)))
        fetcher.formsDataResult = .success(data)
        let persisting = MemoryPersisting()
        persisting.failSaves = true
        let state = InMemorySyncStateStore()
        let status = DataSyncStatus(defaults: defaults)
        let store = try makeStore(fetcher: fetcher, persisting: persisting, state: state, status: status)

        await store.start()

        XCTAssertEqual(store.catalogue.version, "1.0.0")
        XCTAssertNil(state.lastSyncedFormsManifest())
        XCTAssertEqual(status.status(for: .forms).problem, .couldNotSave)
    }

    func testTheIndexCacheKeysOnTheCatalogueVersion() throws {
        let catalogue = try FormCatalogue(data: try FormsJSON.published(), version: "1.4.0")
        XCTAssertEqual(FormIndexCache.Key(verbs: "1.13.0", catalogue: catalogue),
                       FormIndexCache.Key(verbs: "1.13.0", catalogue: "1.4.0"))
        XCTAssertEqual(FormIndexCache.Key(verbs: "1", catalogue: FormCatalogue.bundled).catalogue,
                       FormCatalogue.bundledManifest?.version)
    }
}

// MARK: - Persisting and status

@MainActor
final class FormCataloguePersistenceTests: XCTestCase {
    func testSwiftDataRoundTripsTheSyncedCatalogue() throws {
        let container = try VerbModelContainer.makeInMemory()
        let persisting = SwiftDataFormCataloguePersisting(modelContext: ModelContext(container))
        XCTAssertNil(try persisting.loadFormCatalogue())
        let first = SyncedFormCatalogue(manifest: FormsManifest(version: "1.1.0", sha256: "a"), data: Data("one".utf8))
        let second = SyncedFormCatalogue(manifest: FormsManifest(version: "1.2.0", sha256: "b"), data: Data("two".utf8))
        try persisting.replaceFormCatalogue(with: first)
        try persisting.replaceFormCatalogue(with: second)
        XCTAssertEqual(try persisting.loadFormCatalogue(), second)
    }

    func testTheSyncStateRemembersTheFormsManifestPerBuild() {
        let suite = "FormCatalogueSyncStateTests"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let old = UserDefaultsSyncStateStore(defaults: defaults, build: "1")
        old.saveLastSyncedFormsManifest(FormsManifest(version: "1.0.0", sha256: "f"))
        XCTAssertEqual(old.lastSyncedFormsManifest(), FormsManifest(version: "1.0.0", sha256: "f"))
        XCTAssertNil(UserDefaultsSyncStateStore(defaults: defaults, build: "2").lastSyncedFormsManifest())
    }

    func testRecordInUseShowsTheBundledVersionWithoutADownloadDate() {
        let suite = "FormCatalogueStatusTests"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let status = DataSyncStatus(defaults: defaults)
        status.recordInUse(.forms, version: "1.0.0")
        XCTAssertEqual(status.status(for: .forms).version, "1.0.0")
        XCTAssertNil(status.status(for: .forms).lastUpdated)
        XCTAssertNil(status.status(for: .forms).lastChecked)
        XCTAssertEqual(DataFile.forms.displayName, "Forms")
    }
}
