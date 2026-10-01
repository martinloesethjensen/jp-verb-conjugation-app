import XCTest
@testable import VerbKit

/// Tests against the verb-auxiliary lessons in the real `data/grammar.json`
/// (`RealGrammarDataTests` guards the file against its manifest hash).
final class RealAuxiliaryLessonsTests: XCTestCase {
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

    func testTheFourLessonsExistWithTheAgreedLevels() throws {
        let points = try loadGrammar()
        let expected: [(String, JLPTLevel)] = [
            ("teiru", .n5), ("teshimau", .n4),
            ("temiru", .n4), ("sugiru", .n4),
        ]
        for (id, level) in expected {
            let lesson = try XCTUnwrap(points.first { $0.id == id }, id)
            XCTAssertEqual(lesson.jlpt, level, id)
            XCTAssertFalse(lesson.usages.isEmpty, id)
            XCTAssertFalse(lesson.pitfalls.isEmpty, id)
            XCTAssertTrue(lesson.attachesToVerbs, id)
        }
    }

    func testEachLessonAttachesToTheWordClassesItShould() throws {
        let points = try loadGrammar()
        func classes(_ id: String) throws -> Set<WordClass> {
            Set(try XCTUnwrap(points.first { $0.id == id }, id).attachment.map(\.wordClass))
        }
        XCTAssertEqual(try classes("teiru"), [.verb])
        XCTAssertEqual(try classes("teshimau"), [.verb])
        XCTAssertEqual(try classes("temiru"), [.verb])
        XCTAssertEqual(try classes("sugiru"), [.verb, .iAdjective, .naAdjective])
    }

    func testTheAgreedCrossLinksExistInBothDirections() throws {
        let points = try loadGrammar()
        let byID = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0) })
        let pairs = [("teiru", "teshimau"), ("teshimau", "temiru"), ("temiru", "sugiru"), ("sugiru", "appearance")]
        for (a, b) in pairs {
            XCTAssertTrue(byID[a]?.related.contains(b) ?? false, "\(a) should link to \(b)")
            XCTAssertTrue(byID[b]?.related.contains(a) ?? false, "\(b) should link to \(a)")
        }
    }

    func testTeiruAndTearuAreDistinguishedByCondition() throws {
        let teiru = try XCTUnwrap(try loadGrammar().first { $0.id == "teiru" })
        let conditions = teiru.attachment.compactMap(\.condition)
        XCTAssertEqual(conditions, ["Most verbs", "Verbs that take an object"])
    }
}
