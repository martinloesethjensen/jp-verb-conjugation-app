import XCTest
@testable import VerbKit

/// Tests against the nuance-ending lessons in the real `data/grammar.json`
/// (`RealGrammarDataTests` guards the file against its manifest hash). They read
/// the file straight from the repo checkout.
final class RealNuanceDataTests: XCTestCase {
    private func loadGrammar() throws -> [GrammarPoint] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // VerbKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // VerbKit
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("data")
            .appendingPathComponent("grammar.json")
        return try JSONDecoder().decode(GrammarDataFile.self, from: Data(contentsOf: url)).grammar
    }

    private let nuanceIDs = ["certainty", "obligation", "appearance", "ppoi"]

    func testTheFourLessonsExistAsIntermediate() throws {
        let points = try loadGrammar()
        for id in nuanceIDs {
            let lesson = try XCTUnwrap(points.first { $0.id == id }, id)
            XCTAssertEqual(lesson.level, .intermediate, id)
            XCTAssertFalse(lesson.usages.isEmpty, id)
            XCTAssertFalse(lesson.pitfalls.isEmpty, id)
        }
    }

    func testEachLessonHasAttachmentRulesForTheClassesItShould() throws {
        let points = try loadGrammar()
        func classes(_ id: String) throws -> Set<WordClass> {
            Set(try XCTUnwrap(points.first { $0.id == id }, id).attachment.map(\.wordClass))
        }
        XCTAssertEqual(try classes("certainty"), [.verb, .iAdjective, .naAdjective, .noun])
        XCTAssertEqual(try classes("obligation"), [.verb, .iAdjective, .naAdjective])
        XCTAssertEqual(try classes("appearance"), [.verb, .iAdjective, .naAdjective, .noun])
        XCTAssertEqual(try classes("ppoi"), [.noun, .verb, .iAdjective])
    }

    func testSiblingLessonsLinkBothWays() throws {
        let points = try loadGrammar()
        let byID = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0) })
        for lesson in points {
            for other in lesson.related {
                XCTAssertTrue(byID[other]?.related.contains(lesson.id) ?? false,
                              "\(lesson.id) relates to \(other), which does not relate back")
            }
        }
    }

    func testEveryLessonAttachingToVerbsShowsInTheVerbPageList() throws {
        // All six lessons have a verb rule; the list keeps the file's order.
        XCTAssertEqual(
            try loadGrammar().attachingToVerbs.map(\.id),
            ["n-desu", "potential", "certainty", "obligation", "appearance", "ppoi"]
        )
    }
}
