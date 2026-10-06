import XCTest
@testable import VerbKit

/// Tests against the potential-form half of the real published files in
/// `data/` (`RealDataFileTests` guards `verbs.json` against its manifest hash,
/// and `RealGrammarDataTests` guards `grammar.json` against its own). They read
/// the files straight from the repo checkout, so they fail when someone edits
/// the data and forgets `scripts/update_data.py`.
final class RealPotentialDataTests: XCTestCase {
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

    // MARK: per-verb forms

    /// An independent re-statement of the formation rules, so the test checks
    /// the generated data against the rules and not against the generator.
    private func expectedBase(for verb: Verb) -> String? {
        if ["ある", "わかる", "しる", "つかれる"].contains(verb.dict) { return nil }
        let eRow: [Character: String] = [
            "う": "え", "く": "け", "ぐ": "げ", "す": "せ", "つ": "て",
            "ぬ": "ね", "ぶ": "べ", "む": "め", "る": "れ",
        ]
        switch verb.type {
        case .ru:
            return String(verb.dict.dropLast()) + "られる"
        case .u:
            return String(verb.dict.dropLast()) + (eRow[verb.dict.last!] ?? "?") + "る"
        case .irregular:
            return ["する": "できる", "くる": "こられる"][verb.dict]
        }
    }

    func testEveryVerbHasPotentialFormsBuiltFromItsClass() throws {
        let verbs = try loadVerbs()
        XCTAssertGreaterThanOrEqual(verbs.count, 25)
        for verb in verbs {
            let f = verb.forms
            guard let base = expectedBase(for: verb) else {
                XCTAssertFalse(f.hasPotentialForms, "\(verb.dict) should have no potential forms")
                continue
            }
            let stem = String(base.dropLast())
            XCTAssertEqual(f.potential, base, verb.dict)
            XCTAssertEqual(f.potMasuPos, stem + "ます", verb.dict)
            XCTAssertEqual(f.potMasuNeg, stem + "ません", verb.dict)
            XCTAssertEqual(f.potMasuPast, stem + "ました", verb.dict)
            XCTAssertEqual(f.potMasuPastNeg, stem + "ませんでした", verb.dict)
            XCTAssertEqual(f.potTe, stem + "て", verb.dict)
            XCTAssertEqual(f.potShortNeg, stem + "ない", verb.dict)
            XCTAssertEqual(f.potShortPast, stem + "た", verb.dict)
            XCTAssertEqual(f.potShortPastNeg, stem + "なかった", verb.dict)
        }
    }

    /// Hand-verified values, one per verb class and u-verb ending.
    func testPotentialSpotChecks() throws {
        let verbs = try loadVerbs()
        func forms(_ dict: String) throws -> VerbForms {
            try XCTUnwrap(verbs.first { $0.dict == dict }, dict).forms
        }
        XCTAssertEqual(try forms("たべる").potential, "たべられる")
        XCTAssertEqual(try forms("のむ").potential, "のめる")       // む
        XCTAssertEqual(try forms("かう").potential, "かえる")       // う
        XCTAssertEqual(try forms("かく").potential, "かける")       // く
        XCTAssertEqual(try forms("およぐ").potential, "およげる")   // ぐ
        XCTAssertEqual(try forms("はなす").potential, "はなせる")   // す
        XCTAssertEqual(try forms("まつ").potential, "まてる")       // つ
        XCTAssertEqual(try forms("しぬ").potential, "しねる")       // ぬ
        XCTAssertEqual(try forms("あそぶ").potential, "あそべる")   // ぶ
        XCTAssertEqual(try forms("とる").potential, "とれる")       // る
        XCTAssertEqual(try forms("する").potential, "できる")
        XCTAssertEqual(try forms("する").potMasuPastNeg, "できませんでした")
        XCTAssertEqual(try forms("くる").potential, "こられる")
        XCTAssertEqual(try forms("くる").potShortPast, "こられた")
        XCTAssertEqual(try forms("のむ").potTe, "のめて")
    }

    func testAruHasNoPotentialFormsAndExplainsWhy() throws {
        let aru = try XCTUnwrap(try loadVerbs().first { $0.dict == "ある" })
        XCTAssertFalse(aru.forms.hasPotentialForms)
        let notes = try XCTUnwrap(aru.notes)
        XCTAssertTrue(notes.contains("いる"), "ある's original note must be kept")
        XCTAssertTrue(notes.contains("ありえる"), "ある's note should explain ありえる")
    }

    // MARK: the lesson

    func testPotentialLessonExistsWithTheAgreedShape() throws {
        let points = try loadGrammar()
        let potential = try XCTUnwrap(points.first { $0.id == GrammarPoint.potentialID })
        XCTAssertEqual(potential.title, "可能形")
        XCTAssertEqual(potential.jlpt, .n4)
        XCTAssertEqual(potential.usages.count, 5)
        XCTAssertEqual(potential.attachment.count, 4)
        XCTAssertEqual(potential.pitfalls.count, 4)
        XCTAssertTrue(potential.attachment.allSatisfy { $0.wordClass == .verb })
        XCTAssertEqual(
            potential.attachment.compactMap(\.condition),
            ["Ru-verbs", "U-verbs", "する", "来る"]
        )
        XCTAssertEqual(potential.conjugations.filter { $0.register == .polite }.count, 4)
        XCTAssertEqual(potential.conjugations.filter { $0.register == .casual }.count, 5)
        XCTAssertEqual(potential.conjugations.filter { $0.register == .formal }.count, 2)
        XCTAssertTrue(potential.usages.allSatisfy { !$0.examples.isEmpty })
    }

    func testLessonsLinkToEachOther() throws {
        let points = try loadGrammar()
        let potential = try XCTUnwrap(points.first { $0.id == GrammarPoint.potentialID })
        let nDesu = try XCTUnwrap(points.first { $0.id == GrammarPoint.nDesuID })
        XCTAssertEqual(potential.related, [GrammarPoint.nDesuID])
        XCTAssertTrue(nDesu.related.contains(GrammarPoint.potentialID))
    }

    func testLessonIsFoundBySearchingItsJapaneseAndEnglish() throws {
        let potential = try XCTUnwrap(try loadGrammar().first { $0.id == GrammarPoint.potentialID })
        XCTAssertTrue(matchesGrammarSearch(potential, query: "可能形"))
        XCTAssertTrue(matchesGrammarSearch(potential, query: "potential"))
        XCTAssertTrue(matchesGrammarSearch(potential, query: "食べられる"))
    }
}
