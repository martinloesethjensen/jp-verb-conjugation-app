import XCTest
@testable import VerbKit

final class RealJishoQueryTests: XCTestCase {
    private func loadVerbs() throws -> [Verb] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("data").appendingPathComponent("verbs.json")
        return try JSONDecoder().decode(VerbDataFile.self, from: Data(contentsOf: url)).verbs
    }

    func testPrefersKanjiAndFallsBackToKana() throws {
        let verbs = try loadVerbs()
        let byDict = Dictionary(uniqueKeysWithValues: verbs.map { ($0.dict, $0) })
        XCTAssertEqual(byDict["みせる"]?.jishoQuery, "見せる")
        XCTAssertEqual(byDict["する"]?.jishoQuery, "する")
        XCTAssertEqual(byDict["ある"]?.jishoQuery, "ある")
    }

    func testEveryVerbHasAQueryThatBuildsAURL() throws {
        for verb in try loadVerbs() {
            XCTAssertFalse(verb.jishoQuery.isEmpty, verb.dict)
            XCTAssertNotNil(TextLookupURL.jisho(verb.jishoQuery), verb.dict)
        }
    }
}
