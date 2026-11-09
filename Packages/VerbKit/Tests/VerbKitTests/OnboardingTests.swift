import XCTest
@testable import VerbKit

final class OnboardingTests: XCTestCase {
    private func fresh(_ name: String, function: String = #function) -> UserDefaults {
        let suite = "OnboardingTests.\(function).\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testAFreshInstallShowsOnceThenNotAfterFinishing() {
        let (group, standard) = (fresh("g"), fresh("s"))
        XCTAssertTrue(OnboardingProgress.begin(appGroup: group, standard: standard))
        OnboardingProgress.finish(appGroup: group)
        XCTAssertFalse(OnboardingProgress.begin(appGroup: group, standard: standard))
        XCTAssertNil(group.object(forKey: OnboardingProgress.pendingKey))
    }

    func testAnInstallThatHasAcceptedVerbsSkipsAndRemembers() {
        let (group, standard) = (fresh("g"), fresh("s"))
        standard.set("1.20.0", forKey: "VerbKit.lastSyncedManifest.version")
        XCTAssertFalse(OnboardingProgress.begin(appGroup: group, standard: standard))
        XCTAssertTrue(group.bool(forKey: OnboardingProgress.completedKey))
    }

    func testTheHighestAcceptedVerbsVersionAlsoCountsAsAnExistingInstall() {
        let (group, standard) = (fresh("g"), fresh("s"))
        standard.set("1.20.0", forKey: "VerbKit.highestAcceptedVersion.verbs")
        XCTAssertFalse(OnboardingProgress.begin(appGroup: group, standard: standard))
    }

    func testAStoredLevelOrFuriganaSettingCountsAsAnExistingInstall() {
        let group = fresh("g")
        group.set("", forKey: LevelSettings.defaultsKey)
        XCTAssertFalse(OnboardingProgress.begin(appGroup: group, standard: fresh("s")))
        let other = fresh("g2")
        other.set(false, forKey: FuriganaSetting.defaultsKey)
        XCTAssertFalse(OnboardingProgress.begin(appGroup: other, standard: fresh("s2")))
    }

    func testAnUnfinishedFlowShowsAgainAfterDataArrived() {
        let (group, standard) = (fresh("g"), fresh("s"))
        XCTAssertTrue(OnboardingProgress.begin(appGroup: group, standard: standard))
        standard.set("1.20.0", forKey: "VerbKit.lastSyncedManifest.version")   // the bundled install ran, app killed
        XCTAssertTrue(OnboardingProgress.begin(appGroup: group, standard: standard))
    }

    func testTheLastLevelCannotBeUnpicked() {
        var choices = OnboardingChoices()
        XCTAssertEqual(choices.levels, [.n5, .n4])
        choices.toggle(.n4)
        choices.toggle(.n5)
        XCTAssertEqual(choices.levels, [.n5])
        choices.toggle(.n1)
        XCTAssertEqual(choices.levels, [.n5, .n1])
    }

    func testDefaults() {
        let choices = OnboardingChoices()
        XCTAssertTrue(choices.furigana)
        XCTAssertEqual(choices.theme, .light)
    }

    func testApplyWritesOnlyItsThreeSettings() {
        let group = fresh("g")
        ThemeChoice(theme: .latte, appearance: .dark, seasonal: true).save(to: group)
        var choices = OnboardingChoices()
        choices.furigana = false
        choices.theme = .matcha
        choices.apply(to: group, amongEach: [[.n5, .n4], [.n5, .n4, .n3, .n2]])
        XCTAssertEqual(ThemeChoice.load(from: group), ThemeChoice(theme: .matcha, appearance: .dark, seasonal: true))
        XCTAssertEqual(group.object(forKey: FuriganaSetting.defaultsKey) as? Bool, false)
        XCTAssertEqual(LevelSettings.load(from: group).hidden, [.n3, .n2, .n1])
    }
}
