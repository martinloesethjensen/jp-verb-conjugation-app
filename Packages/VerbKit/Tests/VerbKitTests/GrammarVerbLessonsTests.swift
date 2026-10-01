import XCTest
@testable import VerbKit

final class GrammarVerbLessonsTests: XCTestCase {
    private func point(_ id: String, classes: [WordClass]) -> GrammarPoint {
        GrammarPoint(
            id: id,
            title: id,
            summary: "s",
            level: .intermediate,
            usages: [],
            attachment: classes.map { AttachmentRule(wordClass: $0, pattern: "p", example: "e") },
            conjugations: [],
            pitfalls: [],
            related: []
        )
    }

    func testALessonWithAVerbRuleAttachesToVerbs() {
        XCTAssertTrue(point("a", classes: [.noun, .verb]).attachesToVerbs)
    }

    func testALessonWithoutAVerbRuleDoesNot() {
        XCTAssertFalse(point("a", classes: [.noun, .naAdjective]).attachesToVerbs)
        XCTAssertFalse(point("a", classes: []).attachesToVerbs)
    }

    func testFilteringKeepsTheGivenOrder() {
        let points = [
            point("first", classes: [.verb]),
            point("noun-only", classes: [.noun]),
            point("second", classes: [.iAdjective, .verb]),
        ]
        XCTAssertEqual(points.attachingToVerbs.map(\.id), ["first", "second"])
    }

    func testNoLessonsMeansNothingToList() {
        XCTAssertTrue([GrammarPoint]().attachingToVerbs.isEmpty)
    }
}
