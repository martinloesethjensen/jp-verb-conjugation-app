import XCTest
@testable import VerbKit

final class LevelSettingsTests: XCTestCase {
    func testRawValueRoundTripAndOrdering() {
        XCTAssertEqual(LevelSettings(hidden: [.n3, .n5]).rawValue, "N5,N3")
        XCTAssertEqual(LevelSettings(rawValue: "N5,N3").hidden, [.n5, .n3])
        XCTAssertEqual(LevelSettings().rawValue, "")
    }

    func testParsingIgnoresJunk() {
        XCTAssertEqual(LevelSettings(rawValue: nil).hidden, [])
        XCTAssertEqual(LevelSettings(rawValue: "").hidden, [])
        XCTAssertEqual(LevelSettings(rawValue: "bogus,N4").hidden, [.n4])
    }

    func testNilIsAlwaysVisible() {
        let all = LevelSettings(hidden: Set(JLPTLevel.allCases))
        XCTAssertTrue(all.isVisible(nil))
        XCTAssertFalse(all.isVisible(.n5))
        XCTAssertTrue(LevelSettings().isVisible(.n5))
    }

    func testAnyHiddenAmongAvailable() {
        let s = LevelSettings(hidden: [.n1])
        XCTAssertFalse(s.anyHidden(among: [.n5, .n4]))
        XCTAssertTrue(s.anyHidden(among: [.n5, .n1]))
    }

    func testCanHide() {
        let s = LevelSettings(hidden: [.n5])
        XCTAssertFalse(s.canHide(.n4, among: [.n5, .n4]))
        XCTAssertTrue(s.canHide(.n4, among: [.n5, .n4, .n3]))
        XCTAssertTrue(s.canHide(.n1, among: [.n5, .n4]))
        XCTAssertTrue(LevelSettings().canHide(.n5, among: [.n5, .n4]))
        XCTAssertFalse(LevelSettings().canHide(.n5, among: [.n5]))
    }

    func testSummary() {
        let avail: Set<JLPTLevel> = [.n5, .n4, .n3]
        XCTAssertNil(LevelSettings().summary(among: avail))
        XCTAssertNil(LevelSettings(hidden: [.n1]).summary(among: avail))
        XCTAssertEqual(LevelSettings(hidden: [.n3]).summary(among: avail), "N5–N4")
        XCTAssertEqual(LevelSettings(hidden: [.n4]).summary(among: avail), "N5, N3")
        XCTAssertEqual(LevelSettings(hidden: [.n5, .n4]).summary(among: avail), "N3")
        XCTAssertEqual(LevelSettings(hidden: [.n5]).summary(among: avail), "N4–N3")
        XCTAssertEqual(LevelSettings(hidden: [.n4, .n3]).summary(among: avail), "N5")
    }

    func testSummaryContiguityIsAmongAllJLPTLevels() {
        // N4 is not in the data, but N5 and N3 still are not adjacent JLPT levels.
        XCTAssertEqual(LevelSettings(hidden: [.n2]).summary(among: [.n5, .n3, .n2]), "N5, N3")
        XCTAssertEqual(LevelSettings(hidden: [.n5, .n4]).summary(among: [.n5, .n3, .n2]), "N3–N2")
    }

    func testSaveLoadRoundTrip() throws {
        let name = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(LevelSettings.load(from: defaults), LevelSettings())
        LevelSettings(hidden: [.n4, .n1]).save(to: defaults)
        XCTAssertEqual(defaults.string(forKey: "hiddenJLPTLevels"), "N4,N1")
        XCTAssertEqual(LevelSettings.load(from: defaults).hidden, [.n4, .n1])
    }

    func testSummaryIsEmptyWhenEverythingAvailableIsHidden() {
        XCTAssertEqual(LevelSettings(hidden: [.n5, .n4]).summary(among: [.n5, .n4]), "")
    }

    func testCanHideWithEmptyAvailableSetIsTrue() {
        XCTAssertTrue(LevelSettings().canHide(.n5, among: []))
    }

    func testCanHideAmongEachDataset() {
        let verbs: Set<JLPTLevel> = [.n5, .n4]
        let grammar: Set<JLPTLevel> = [.n5, .n4, .n3, .n2]
        let none = LevelSettings()
        XCTAssertTrue(none.canHide(.n5, amongEach: [verbs, grammar]))
        let n5Hidden = LevelSettings(hidden: [.n5])
        XCTAssertFalse(n5Hidden.canHide(.n4, amongEach: [verbs, grammar]))
        XCTAssertTrue(n5Hidden.canHide(.n3, amongEach: [verbs, grammar]))
        XCTAssertTrue(none.canHide(.n5, amongEach: [verbs, []]))
        XCTAssertTrue(none.canHide(.n3, amongEach: [[.n5], grammar]))
        XCTAssertFalse(none.canHide(.n5, amongEach: [[.n5], grammar]))
    }
}
