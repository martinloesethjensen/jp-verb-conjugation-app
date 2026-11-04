import XCTest
@testable import VerbKit

final class GrammarUsageLevelTests: XCTestCase {
    private func usage(_ heading: String, _ jlpt: JLPTLevel? = nil) -> GrammarUsage {
        GrammarUsage(heading: heading, explanation: "e", examples: [GrammarExample(jp: "あ", en: "a")], jlpt: jlpt)
    }

    private func point(_ jlpt: JLPTLevel?, _ usages: [GrammarUsage]) -> GrammarPoint {
        GrammarPoint(id: "p", title: "t", summary: "s", jlpt: jlpt, usages: usages,
                     attachment: [], conjugations: [], pitfalls: [], related: [])
    }

    /// Shaped like `certainty`: N4 by default, わけ at N3.
    private var certainty: GrammarPoint {
        point(.n4, [usage("はず"), usage("かもしれない"), usage("わけ", .n3)])
    }

    private let onlyN4 = LevelSettings(hidden: [.n5, .n3, .n2, .n1])
    private let onlyN3 = LevelSettings(hidden: [.n5, .n4, .n2, .n1])

    func testUsageWithoutALevelTakesTheLessons() {
        let p = certainty
        XCTAssertEqual(p.usages.map { p.level(of: $0) }, [.n4, .n4, .n3])
    }

    func testOnlyN4ShowsHazuAndKamoshirenaiButNotWake() {
        XCTAssertTrue(certainty.isVisible(in: onlyN4))
        XCTAssertEqual(certainty.visibleUsages(in: onlyN4).map(\.heading), ["はず", "かもしれない"])
    }

    func testOnlyN3ShowsWakeAlone() {
        XCTAssertTrue(certainty.isVisible(in: onlyN3))
        XCTAssertEqual(certainty.visibleUsages(in: onlyN3).map(\.heading), ["わけ"])
    }

    func testLessonVisibleWhenAnyUsageIs() {
        let teiru = point(.n5, [usage("ている"), usage("てある", .n4)])
        XCTAssertTrue(teiru.isVisible(in: LevelSettings(hidden: [.n5])))
        XCTAssertTrue(teiru.isVisible(in: LevelSettings(hidden: [.n4])))
        XCTAssertFalse(teiru.isVisible(in: LevelSettings(hidden: [.n5, .n4])))
    }

    func testSequenceFilteringUsesUsageLevels() {
        let points = [certainty, point(.n5, [usage("x")])]
        XCTAssertEqual(points.visible(in: onlyN3).count, 1)
        XCTAssertEqual(points.hiddenCount(in: onlyN3), 1)
        XCTAssertEqual(points.levels(), [.n5, .n4, .n3])
    }

    func testRange() {
        XCTAssertEqual(certainty.levelRange, .n4 ... .n3)
        XCTAssertTrue(certainty.hasMixedLevels)
        let single = point(.n5, [usage("a"), usage("b")])
        XCTAssertEqual(single.levelRange, .n5 ... .n5)
        XCTAssertFalse(single.hasMixedLevels)
        XCTAssertNil(point(nil, [usage("a")]).levelRange)
    }

    func testLessonLevelOnlyMattersThroughUsages() {
        // Every usage overrides the lesson's level, so the lesson's own level is not taught.
        let p = point(.n5, [usage("a", .n3)])
        XCTAssertEqual(p.levelsTaught, [.n3])
        XCTAssertFalse(p.isVisible(in: LevelSettings(hidden: [.n3])))
    }

    func testNoLevelIsAlwaysVisible() {
        let p = point(nil, [usage("a"), usage("b", .n3)])
        XCTAssertEqual(p.visibleUsages(in: LevelSettings(hidden: [.n3])).map(\.heading), ["a"])
        XCTAssertTrue(p.isVisible(in: LevelSettings(hidden: Set(JLPTLevel.allCases))))
    }

    func testDecodingUsageLevelIsOptionalAndRoundTrips() throws {
        let json = #"{"heading":"h","explanation":"e","examples":[],"jlpt":"N3"}"#
        let decoded = try JSONDecoder().decode(GrammarUsage.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.jlpt, .n3)
        let plainJSON = #"{"heading":"h","explanation":"e","examples":[]}"#
        let plain = try JSONDecoder().decode(GrammarUsage.self, from: Data(plainJSON.utf8))
        XCTAssertNil(plain.jlpt)
        let reencoded = try JSONDecoder().decode(GrammarUsage.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(reencoded, decoded)
    }
}
