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

    func testEveryVerbHasItsMasuStem() throws {
        for verb in try loadVerbs() {
            XCTAssertFalse(verb.forms.stem.isEmpty, verb.dict)
            XCTAssertEqual(verb.forms.stem + "ます", verb.forms.masuPos, verb.dict)
        }
    }

    private func loadWords() throws -> [Word] {
        try JSONDecoder().decode(WordsDataFile.self, from: Data(contentsOf: dataURL("words.json"))).words
    }

    func testWordsFileMatchesTheManifestAndDecodes() throws {
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: dataURL("manifest.json"))) as? [String: Any]
        let entry = try XCTUnwrap(manifest?["words"] as? [String: Any])
        XCTAssertEqual(entry["sha256"] as? String, sha256Hex(of: try Data(contentsOf: dataURL("words.json"))))
        let words = try loadWords()
        XCTAssertGreaterThanOrEqual(words.count, 30)
        XCTAssertEqual(Set(words.map(\.wordClass)), [.iAdjective, .naAdjective, .noun])
    }

    /// Every rule with an ending builds a pattern for every word of its class and every
    /// slot it lists, so the cards and the quiz never meet a missing form.
    func testEverySlotRuleBuildsForEveryWordOfItsClass() throws {
        let sources: [SlotSource] = try loadVerbs() + loadWords()
        var built = 0
        for point in try loadGrammar() {
            for rule in point.attachment where rule.then != nil {
                for word in sources where word.wordClass == rule.wordClass {
                    for slot in rule.slots {
                        XCTAssertNotNil(rule.build(word, slot: slot), "\(point.id) \(rule.wordClass) \(slot) \(word.dict)")
                        built += 1
                    }
                }
            }
        }
        XCTAssertGreaterThan(built, 200)
    }

    /// Spot checks a learner would recognise, one per tricky rule.
    func testBuiltPatternsSpotChecks() throws {
        let points = Dictionary(uniqueKeysWithValues: try loadGrammar().map { ($0.id, $0) })
        let words = try loadWords()
        let verbs = try loadVerbs()
        func build(_ id: String, _ dict: String, _ slot: GrammarSlot) throws -> String? {
            let source: SlotSource = try XCTUnwrap(verbs.first { $0.dict == dict } ?? words.first { $0.dict == dict }, dict)
            let rules = try XCTUnwrap(points[id], id).attachment
            return rules.lazy.compactMap { $0.build(source, slot: slot) }.first
        }
        XCTAssertEqual(try build("node", "しずか", .plain), "しずかなので")
        XCTAssertEqual(try build("node", "あめ", .plainPast), "あめだったので")
        XCTAssertEqual(try build("node", "たかい", .plainNeg), "たかくないので")
        XCTAssertEqual(try build("hou-ga-ii", "ねる", .plainPast), "ねたほうがいいです")
        XCTAssertEqual(try build("hou-ga-ii", "たべる", .plainNeg), "たべないほうがいいです")
        XCTAssertEqual(try build("sugiru", "いい", .stem), "よすぎる")
        XCTAssertEqual(try build("sugiru", "からい", .stem), "からすぎる")
        XCTAssertEqual(try build("n-desu", "がくせい", .plain), "がくせいなんです")
        XCTAssertEqual(try build("n-desu", "しずか", .plainPast), "しずかだったんです")
    }

    func testTheNewLessonsExistWithContrasts() throws {
        let points = try loadGrammar()
        for id in ["node", "hou-ga-ii"] {
            let point = try XCTUnwrap(points.first { $0.id == id }, id)
            XCTAssertFalse(point.contrasts.isEmpty, id)
        }
    }
}
