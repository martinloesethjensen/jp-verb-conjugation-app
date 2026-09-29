import XCTest
@testable import VerbKit

/// Tests against the grammar half of the real published files in `data/`
/// (`RealDataFileTests` already guards `verbs.json` against its manifest
/// hash). They read the files straight from the repo checkout, so they
/// fail when someone edits the data and forgets `scripts/update_data.py`.
final class RealGrammarDataTests: XCTestCase {
    private func dataURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // VerbKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // VerbKit
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("data")
            .appendingPathComponent(name)
    }

    private func loadVerbs() throws -> [Verb] {
        let data = try Data(contentsOf: dataURL("verbs.json"))
        return try JSONDecoder().decode(VerbDataFile.self, from: data).verbs
    }

    private func loadGrammar() throws -> [GrammarPoint] {
        let data = try Data(contentsOf: dataURL("grammar.json"))
        return try JSONDecoder().decode(GrammarDataFile.self, from: data).grammar
    }

    func testEveryVerbHasNdFormsBuiltFromItsPlainForms() throws {
        let verbs = try loadVerbs()
        XCTAssertFalse(verbs.isEmpty)
        for verb in verbs {
            let f = verb.forms
            XCTAssertEqual(f.ndPos, f.shortPos + "んです", verb.dict)
            XCTAssertEqual(f.ndNeg, f.shortNeg + "んです", verb.dict)
            XCTAssertEqual(f.ndPast, f.shortPast + "んです", verb.dict)
            XCTAssertEqual(f.ndPastNeg, f.shortPastNeg + "んです", verb.dict)
            XCTAssertEqual(f.ndCasualPos, f.shortPos + "んだ", verb.dict)
            XCTAssertEqual(f.ndCasualNeg, f.shortNeg + "んだ", verb.dict)
            XCTAssertEqual(f.ndCasualPast, f.shortPast + "んだ", verb.dict)
            XCTAssertEqual(f.ndCasualPastNeg, f.shortPastNeg + "んだ", verb.dict)
        }
    }

    /// Hand-verified values, one per verb class: ichidan, godan, and both irregulars.
    func testNdFormsSpotChecks() throws {
        let verbs = try loadVerbs()
        func forms(_ dict: String) throws -> VerbForms {
            try XCTUnwrap(verbs.first { $0.dict == dict }, dict).forms
        }
        XCTAssertEqual(try forms("たべる").ndPastNeg, "たべなかったんです")
        XCTAssertEqual(try forms("かう").ndNeg, "かわないんです")
        XCTAssertEqual(try forms("かう").ndPast, "かったんです")
        XCTAssertEqual(try forms("する").ndCasualPos, "するんだ")
        XCTAssertEqual(try forms("くる").ndNeg, "こないんです")
        XCTAssertEqual(try forms("くる").ndPast, "きたんです")
    }

    func testGrammarFileDecodesAndContainsNDesu() throws {
        let points = try loadGrammar()
        let nDesu = try XCTUnwrap(points.first { $0.id == GrammarPoint.nDesuID })
        XCTAssertEqual(nDesu.title, "んです")
        XCTAssertEqual(nDesu.usages.count, 7)
        XCTAssertEqual(nDesu.attachment.count, 6)
        XCTAssertEqual(nDesu.pitfalls.count, 3)
        XCTAssertTrue(nDesu.conjugations.contains { $0.form == "の" && $0.register == .casual })
    }

    func testGrammarIDsAreUniqueAndRelatedIDsExist() throws {
        let points = try loadGrammar()
        let ids = points.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        for point in points {
            for related in point.related {
                XCTAssertTrue(ids.contains(related), "\(point.id) -> \(related)")
            }
        }
    }

    func testManifestGrammarHashMatchesTheGrammarFile() throws {
        let manifestData = try Data(contentsOf: dataURL("manifest.json"))
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        let grammar = try XCTUnwrap(manifest["grammar"] as? [String: String], "manifest.json has no grammar block")
        XCTAssertEqual(grammar["sha256"], sha256Hex(of: try Data(contentsOf: dataURL("grammar.json"))))
    }
}
