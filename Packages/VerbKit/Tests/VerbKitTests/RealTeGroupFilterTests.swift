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
        // A u-verb's group follows its last kana (いく is filed under its ending too),
        // so the expectation is derived rather than a count that every new verb breaks.
        let byEnding: [Character: TeGroup] = [
            "う": .tte, "つ": .tte, "る": .tte, "む": .nde, "ぶ": .nde, "ぬ": .nde,
            "く": .ite, "ぐ": .ide, "す": .shite,
        ]
        for verb in verbs where verb.type == .u {
            let expected = try XCTUnwrap(byEnding[try XCTUnwrap(verb.dict.last)], verb.dict)
            for group in TeGroup.allCases {
                XCTAssertEqual(matchesTeGroup(verb, filter: group), group == expected, "\(verb.dict) \(group)")
            }
        }
        for group in TeGroup.allCases {
            XCTAssertFalse(verbs.filter { matchesTeGroup($0, filter: group) }.isEmpty, "\(group) has no verbs")
        }
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
