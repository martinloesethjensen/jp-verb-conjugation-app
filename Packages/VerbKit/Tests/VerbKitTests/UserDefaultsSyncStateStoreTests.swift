import XCTest
@testable import VerbKit

final class UserDefaultsSyncStateStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "UserDefaultsSyncStateStoreTests"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testManifestsSurviveWithinTheSameBuild() {
        UserDefaultsSyncStateStore(defaults: defaults, build: "1").saveLastSyncedManifest(VerbManifest(version: "1.0.0", sha256: "a"))
        XCTAssertEqual(
            UserDefaultsSyncStateStore(defaults: defaults, build: "1").lastSyncedManifest(),
            VerbManifest(version: "1.0.0", sha256: "a")
        )
    }

    func testHighestAcceptedVersionSurvivesANewBuild() {
        UserDefaultsSyncStateStore(defaults: defaults, build: "1").saveHighestAcceptedVersion("1.4.0", for: "verbs")
        let new = UserDefaultsSyncStateStore(defaults: defaults, build: "2")
        XCTAssertEqual(new.highestAcceptedVersion(for: "verbs"), "1.4.0")
        XCTAssertNil(new.highestAcceptedVersion(for: "grammar"))
    }

    func testANewBuildForgetsAllThreeManifests() {
        let old = UserDefaultsSyncStateStore(defaults: defaults, build: "1")
        old.saveLastSyncedManifest(VerbManifest(version: "1.0.0", sha256: "a"))
        old.saveLastSyncedGrammarManifest(GrammarManifest(version: "1.0.0", sha256: "b"))
        old.saveLastSyncedFuriganaManifest(FuriganaManifest(version: "1.0.0", sha256: "c"))
        let new = UserDefaultsSyncStateStore(defaults: defaults, build: "2")
        XCTAssertNil(new.lastSyncedManifest())
        XCTAssertNil(new.lastSyncedGrammarManifest())
        XCTAssertNil(new.lastSyncedFuriganaManifest())
    }

    func testEachFileIsRetaggedOnItsOwn() {
        UserDefaultsSyncStateStore(defaults: defaults, build: "1")
            .saveLastSyncedGrammarManifest(GrammarManifest(version: "1.0.0", sha256: "b"))
        let new = UserDefaultsSyncStateStore(defaults: defaults, build: "2")
        new.saveLastSyncedManifest(VerbManifest(version: "1.0.0", sha256: "a"))
        XCTAssertNotNil(new.lastSyncedManifest())
        XCTAssertNil(new.lastSyncedGrammarManifest(), "grammar has not re-synced under build 2")
    }

    func testManifestsFromBeforeTaggingAreTreatedAsStale() {
        defaults.set("1.0.0", forKey: "VerbKit.lastSyncedManifest.version")
        defaults.set("a", forKey: "VerbKit.lastSyncedManifest.sha256")
        XCTAssertNil(UserDefaultsSyncStateStore(defaults: defaults, build: "1").lastSyncedManifest())
    }
}
