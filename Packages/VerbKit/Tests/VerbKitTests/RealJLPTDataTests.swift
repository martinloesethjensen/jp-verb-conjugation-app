import XCTest
@testable import VerbKit

/// The shipped data carries the curated JLPT levels.
final class RealJLPTDataTests: XCTestCase {
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

    func testGrammarLevelsAreTheCuratedOnes() throws {
        let expected: [String: JLPTLevel] = [
            "n-desu": .n4, "potential": .n4, "certainty": .n3, "obligation": .n3,
            "appearance": .n3, "ppoi": .n2, "teiru": .n5, "teshimau": .n4,
            "temiru": .n4, "sugiru": .n4,
        ]
        let points = try loadGrammar()
        XCTAssertEqual(Set(points.map(\.id)), Set(expected.keys))
        for point in points {
            XCTAssertNotNil(point.jlpt, point.id)
            XCTAssertEqual(point.jlpt, expected[point.id], point.id)
        }
    }

    func testVerbLevelsAreTheCuratedOnes() throws {
        let n4: Set<String> = ["しぬ", "いそぐ", "みせる", "かえす"]
        for verb in try RealVerbs.load() {
            XCTAssertNotNil(verb.jlpt, verb.dict)
            XCTAssertEqual(verb.jlpt, n4.contains(verb.dict) ? .n4 : .n5, verb.dict)
        }
    }
}
