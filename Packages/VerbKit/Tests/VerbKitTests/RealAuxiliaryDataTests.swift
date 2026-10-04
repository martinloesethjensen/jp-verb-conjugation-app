import XCTest
@testable import VerbKit

/// Tests against the auxiliary forms in the real `data/verbs.json`
/// (`RealDataFileTests` guards the file against its manifest hash). They read the
/// file straight from the repo checkout, and restate the formation rules
/// independently of the generator.
final class RealAuxiliaryDataTests: XCTestCase {
    private func loadVerbs() throws -> [Verb] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // VerbKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // VerbKit
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("data")
            .appendingPathComponent("verbs.json")
        return try JSONDecoder().decode(VerbDataFile.self, from: Data(contentsOf: url)).verbs
    }

    /// Verbs that take none of the て-form auxiliaries.
    private let withoutTeAuxiliaries: Set<String> = ["ある"]

    func testEveryVerbHasItsAuxiliaryFormsBuiltFromItsTeFormAndStem() throws {
        let verbs = try loadVerbs()
        XCTAssertGreaterThanOrEqual(verbs.count, 25)
        for verb in verbs {
            let f = verb.forms
            XCTAssertTrue(f.masuPos.hasSuffix("ます"), verb.dict)
            let stem = String(f.masuPos.dropLast(2))
            XCTAssertEqual(f.sugiru, stem + "すぎる", verb.dict)
            XCTAssertEqual(f.sugiruPolite, stem + "すぎます", verb.dict)
            XCTAssertEqual(f.yasui, stem + "やすい", verb.dict)
            XCTAssertEqual(f.yasuiPolite, stem + "やすいです", verb.dict)
            XCTAssertEqual(f.nikui, stem + "にくい", verb.dict)
            XCTAssertEqual(f.nikuiPolite, stem + "にくいです", verb.dict)
            XCTAssertEqual(f.nagara, stem + "ながら", verb.dict)

            if withoutTeAuxiliaries.contains(verb.dict) {
                for value in [f.teiru, f.teiruNeg, f.teiruPast, f.teiruPastNeg, f.teiruMasuPos,
                              f.teiruMasuNeg, f.teiruMasuPast, f.teiruMasuPastNeg, f.teiruTe,
                              f.teshimau, f.teshimauPolite, f.teoku, f.teokuPolite,
                              f.temiru, f.temiruPolite] {
                    XCTAssertNil(value, verb.dict)
                }
                continue
            }
            XCTAssertEqual(f.teiru, f.te + "いる", verb.dict)
            XCTAssertEqual(f.teiruNeg, f.te + "いない", verb.dict)
            XCTAssertEqual(f.teiruPast, f.te + "いた", verb.dict)
            XCTAssertEqual(f.teiruPastNeg, f.te + "いなかった", verb.dict)
            XCTAssertEqual(f.teiruMasuPos, f.te + "います", verb.dict)
            XCTAssertEqual(f.teiruMasuNeg, f.te + "いません", verb.dict)
            XCTAssertEqual(f.teiruMasuPast, f.te + "いました", verb.dict)
            XCTAssertEqual(f.teiruMasuPastNeg, f.te + "いませんでした", verb.dict)
            XCTAssertEqual(f.teiruTe, f.te + "いて", verb.dict)
            XCTAssertEqual(f.teshimau, f.te + "しまう", verb.dict)
            XCTAssertEqual(f.teshimauPolite, f.te + "しまいます", verb.dict)
            XCTAssertEqual(f.teoku, f.te + "おく", verb.dict)
            XCTAssertEqual(f.teokuPolite, f.te + "おきます", verb.dict)
            XCTAssertEqual(f.temiru, f.te + "みる", verb.dict)
            XCTAssertEqual(f.temiruPolite, f.te + "みます", verb.dict)
        }
    }

    /// Hand-verified values: one per verb class and the awkward て-forms.
    func testAuxiliarySpotChecks() throws {
        let verbs = try loadVerbs()
        func forms(_ dict: String) throws -> VerbForms {
            try XCTUnwrap(verbs.first { $0.dict == dict }, dict).forms
        }
        XCTAssertEqual(try forms("たべる").teiru, "たべている")
        XCTAssertEqual(try forms("たべる").sugiru, "たべすぎる")
        XCTAssertEqual(try forms("のむ").teiruMasuPos, "のんでいます")        // む → んで
        XCTAssertEqual(try forms("のむ").nikuiPolite, "のみにくいです")
        XCTAssertEqual(try forms("かう").teshimau, "かってしまう")           // う → って
        XCTAssertEqual(try forms("かく").teoku, "かいておく")                // く → いて
        XCTAssertEqual(try forms("いそぐ").temiru, "いそいでみる")           // ぐ → いで
        XCTAssertEqual(try forms("はなす").teshimauPolite, "はなしてしまいます") // す → して
        XCTAssertEqual(try forms("いく").teiru, "いっている")                // いく is irregular
        XCTAssertEqual(try forms("する").teiru, "している")
        XCTAssertEqual(try forms("する").sugiru, "しすぎる")
        XCTAssertEqual(try forms("くる").teiruPast, "きていた")
        XCTAssertEqual(try forms("くる").nagara, "きながら")
        XCTAssertEqual(try forms("ある").sugiru, "ありすぎる")
        XCTAssertNil(try forms("ある").teiru)
    }

    func testEveryVerbHasAuxiliaryForms() throws {
        for verb in try loadVerbs() {
            XCTAssertTrue(verb.forms.hasAuxiliaryForms, verb.dict)
        }
    }
}
