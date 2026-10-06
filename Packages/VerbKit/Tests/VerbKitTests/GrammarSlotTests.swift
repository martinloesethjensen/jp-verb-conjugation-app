import XCTest
@testable import VerbKit

final class GrammarSlotTests: XCTestCase {
    private func word(_ cls: WordClass, _ dict: String, _ forms: [FormID: String]) -> Word {
        Word(wordClass: cls, dict: dict, meaning: "m", description: "", forms: Conjugations(forms))
    }

    private var takai: Word { word(.iAdjective, "たかい", ["short_pos": "たかい", "short_past": "たかかった", "stem": "たか"]) }
    private var shizuka: Word { word(.naAdjective, "しずか", ["short_pos": "しずかだ", "short_past": "しずかだった", "stem": "しずか"]) }
    private var ame: Word { word(.noun, "あめ", ["short_pos": "あめだ"]) }

    private var taberu: Verb {
        let forms = VerbForms(
            masuPos: "たべます", masuNeg: "たべません", masuPast: "たべました", masuPastNeg: "たべませんでした",
            te: "たべて", shortPos: "たべる", shortNeg: "たべない", shortPast: "たべた", shortPastNeg: "たべなかった"
        )
        return Verb(type: .ru, label: "Ru-verb", dict: "たべる", kanji: "食べる", meaning: "to eat",
                    description: "", forms: forms, examples: [])
    }

    func testSlotsMapToFormIDs() {
        XCTAssertEqual(GrammarSlot.allCases.map(\.formID.rawValue),
                       ["short_pos", "short_neg", "short_past", "short_past_neg", "stem", "te"])
    }

    func testDaToNaOnlyTouchesPlainForNaAdjectivesAndNouns() {
        XCTAssertEqual(shizuka.form(for: .plain, daToNa: true), "しずかな")
        XCTAssertEqual(ame.form(for: .plain, daToNa: true), "あめな")
        XCTAssertEqual(shizuka.form(for: .plain), "しずかだ")
        XCTAssertEqual(shizuka.form(for: .plainPast, daToNa: true), "しずかだった")
        XCTAssertEqual(takai.form(for: .plain, daToNa: true), "たかい")
        XCTAssertNil(ame.form(for: .stem))
    }

    func testRuleBuildsThePattern() {
        let node = AttachmentRule(wordClass: .naAdjective, pattern: "p", example: "e",
                                  slots: [.plain, .plainPast], daToNa: true, then: "ので")
        XCTAssertEqual(node.build(shizuka, slot: .plain), "しずかなので")
        XCTAssertEqual(node.build(shizuka, slot: .plainPast), "しずかだったので")
        XCTAssertNil(node.build(shizuka, slot: .stem), "slot not in the rule")
        XCTAssertNil(node.build(takai, slot: .plain), "wrong class")
        let sugiru = AttachmentRule(wordClass: .iAdjective, pattern: "p", example: "e", slots: [.stem], then: "すぎる")
        XCTAssertEqual(sugiru.build(takai, slot: .stem), "たかすぎる")
        let tagOnly = AttachmentRule(wordClass: .iAdjective, pattern: "p", example: "e", slots: [.stem])
        XCTAssertNil(tagOnly.build(takai, slot: .stem))
    }

    func testVerbsAreSlotSources() {
        XCTAssertEqual(taberu.form(for: .stem), "たべ")
        XCTAssertEqual(taberu.form(for: .plainPast), "たべた")
        let hou = AttachmentRule(wordClass: .verb, pattern: "p", example: "e", slots: [.plainPast, .plainNeg], then: "ほうがいいです")
        XCTAssertEqual(hou.build(taberu, slot: .plainNeg), "たべないほうがいいです")
        XCTAssertEqual(hou.build(taberu, slot: .plainPast), "たべたほうがいいです")
    }

    func testOldJSONStillDecodesAndNewFieldsDecode() throws {
        let old = #"{"word_class":"verb","pattern":"p","example":"e"}"#
        let rule = try JSONDecoder().decode(AttachmentRule.self, from: Data(old.utf8))
        XCTAssertEqual(rule.slots, [])
        XCTAssertFalse(rule.daToNa)
        XCTAssertNil(rule.then)
        let new = #"{"word_class":"noun","pattern":"p","example":"e","slots":["plain"],"da_to_na":true,"then":"ので"}"#
        let decoded = try JSONDecoder().decode(AttachmentRule.self, from: Data(new.utf8))
        XCTAssertEqual(decoded.slots, [.plain])
        XCTAssertTrue(decoded.daToNa)
        XCTAssertEqual(decoded.then, "ので")
        let roundTrip = try JSONDecoder().decode(AttachmentRule.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(roundTrip, decoded)
    }

    func testContrastsDecodeAndDefaultToEmpty() throws {
        let point = #"{"id":"x","title":"t","summary":"s","usages":[],"attachment":[],"conjugations":[],"pitfalls":[],"related":[],"contrasts":[{"pattern":"〜から","explanation":"e"}]}"#
        let decoded = try JSONDecoder().decode(GrammarPoint.self, from: Data(point.utf8))
        XCTAssertEqual(decoded.contrasts.first?.pattern, "〜から")
        XCTAssertEqual(decoded.contrasts.first?.examples, [])
        let without = #"{"id":"x","title":"t","summary":"s","usages":[],"attachment":[],"conjugations":[],"pitfalls":[],"related":[]}"#
        XCTAssertEqual(try JSONDecoder().decode(GrammarPoint.self, from: Data(without.utf8)).contrasts, [])
        let roundTrip = try JSONDecoder().decode(GrammarPoint.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(roundTrip, decoded)
    }
}
