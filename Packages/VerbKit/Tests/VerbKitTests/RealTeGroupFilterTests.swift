import XCTest
@testable import VerbKit

final class RealTeGroupFilterTests: XCTestCase {
    private func loadVerbs() throws -> [Verb] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("data").appendingPathComponent("verbs.json")
        return try JSONDecoder().decode(VerbDataFile.self, from: Data(contentsOf: url)).verbs
    }

    func testEachGroupFiltersToItsVerbs() throws {
        let verbs = try loadVerbs()
        let counts = Dictionary(uniqueKeysWithValues: TeGroup.allCases.map { group in
            (group, verbs.filter { matchesTeGroup($0, filter: group) }.count)
        })
        XCTAssertEqual(counts[.tte], 6)
        XCTAssertEqual(counts[.nde], 4)
        XCTAssertEqual(counts[.ite], 3)
        XCTAssertEqual(counts[.ide], 2)
        XCTAssertEqual(counts[.shite], 2)
        XCTAssertEqual(verbs.filter { matchesTeGroup($0, filter: nil) }.count, verbs.count)
    }

    func testRuVerbsAndIrregularsNeverMatchAGroup() throws {
        for verb in try loadVerbs() where verb.type != .u {
            for group in TeGroup.allCases {
                XCTAssertFalse(matchesTeGroup(verb, filter: group), verb.dict)
            }
        }
    }

    func testRuleTableCoversEveryGroupAndItsExamplesAreReal() throws {
        XCTAssertEqual(Set(TeFormRule.all.map(\.group)), Set(TeGroup.allCases))
        let byDict = Dictionary(uniqueKeysWithValues: try loadVerbs().map { ($0.dict, $0) })
        for rule in TeFormRule.all {
            let verb = try XCTUnwrap(byDict[rule.example.dict], rule.example.dict)
            XCTAssertEqual(verb.teGroup, rule.group)
            XCTAssertEqual(verb.forms.te, rule.example.te)
            XCTAssertTrue(rule.example.te.hasSuffix(rule.result))
        }
    }
}
