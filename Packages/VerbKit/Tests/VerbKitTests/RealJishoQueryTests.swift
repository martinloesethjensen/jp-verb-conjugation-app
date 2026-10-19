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
        // Keyed by id, not dict: two verbs can be spelled the same in kana (着る and 切る are both きる).
        let byID = Dictionary(uniqueKeysWithValues: verbs.map { ($0.id, $0) })
        XCTAssertEqual(byID["みせる"]?.jishoQuery, "見せる")
        XCTAssertEqual(byID["する"]?.jishoQuery, "する")
        XCTAssertEqual(byID["ある"]?.jishoQuery, "ある")
        XCTAssertEqual(byID["きる"]?.jishoQuery, "着る")
        XCTAssertEqual(byID["きる:切る"]?.jishoQuery, "切る")
    }

    func testEveryVerbHasAQueryThatBuildsAURL() throws {
        for verb in try loadVerbs() {
            XCTAssertFalse(verb.jishoQuery.isEmpty, verb.dict)
            XCTAssertNotNil(TextLookupURL.jisho(verb.jishoQuery), verb.dict)
        }
    }
}
