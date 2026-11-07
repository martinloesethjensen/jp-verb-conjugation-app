import XCTest
@testable import VerbKit

final class FormHighlightTests: XCTestCase {
    private func verb(_ dict: String, kanji: String?, type: VerbType = .ru) -> Verb {
        Verb(
            type: type, label: dict, dict: dict, kanji: kanji, meaning: "", description: "",
            forms: VerbForms(masuPos: "x", masuNeg: "x", masuPast: "x", masuPastNeg: "x", te: "x",
                             shortPos: dict, shortNeg: "x", shortPast: "x", shortPastNeg: "x"),
            examples: []
        )
    }

    private var taberu: Verb { verb("たべる", kanji: "食べる") }
    private var kuru: Verb { verb("くる", kanji: "来る", type: .irregular) }
    private var suru: Verb { verb("する", kanji: nil, type: .irregular) }

    func testFindsKanjiSpelledForm() {
        XCTAssertEqual(FormHighlight.range(of: "たべます", for: taberu, in: "朝ご飯を食べます。"), 4..<8)
    }

    func testFindsTeFormBeforeKara() {
        XCTAssertEqual(FormHighlight.range(of: "たべて", for: taberu, in: "食べてから、出かけます。"), 0..<3)
    }

    func testFindsKuruChangedStem() {
        XCTAssertEqual(FormHighlight.range(of: "こない", for: kuru, in: "彼は来ない。"), 2..<5)
    }

    func testFallsBackToKanaSpelling() {
        XCTAssertEqual(FormHighlight.range(of: "たべます", for: taberu, in: "なにをたべますか。"), 3..<7)
    }

    func testVerbWithoutKanjiUsesKana() {
        XCTAssertEqual(FormHighlight.range(of: "します", for: suru, in: "宿題をします。"), 3..<6)
    }

    func testNilWhenAbsent() {
        XCTAssertNil(FormHighlight.range(of: "たべません", for: taberu, in: "朝ご飯を食べます。"))
    }

    /// Every published example contains its form, written in kanji or kana (483 of 483 when
    /// this was written), so the verb page can always underline it.
    func testEveryPublishedExampleContainsItsForm() throws {
        var checked = 0
        for verb in try RealVerbs.load() {
            for example in verb.examples {
                guard let form = verb.forms[id: example.form] else { continue }
                XCTAssertNotNil(FormHighlight.range(of: form, for: verb, in: example.jp),
                                "\(verb.id) \(example.form) \(form) in \(example.jp)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 400)
    }
}
