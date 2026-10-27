import XCTest
@testable import VerbKit

/// Widgets, Spotlight, intents and pickers title a word the same way: the kana
/// citation form, with the kanji in parentheses when there is one.
final class DisplayTitleTests: XCTestCase {
    private func verb(dict: String, kanji: String?) -> Verb {
        Verb(
            type: .ru, label: "Ru-verb", dict: dict, kanji: kanji, meaning: "meaning", description: "",
            forms: VerbForms(
                masuPos: "a", masuNeg: "b", masuPast: "c", masuPastNeg: "d",
                te: "e", shortPos: "f", shortNeg: "g", shortPast: "h", shortPastNeg: "i"
            ),
            examples: []
        )
    }

    private func word(dict: String, kanji: String?) -> Word {
        Word(
            wordClass: .noun, dict: dict, kanji: kanji, meaning: "meaning", description: "",
            forms: Conjugations()
        )
    }

    func testVerbTitlePutsTheKanjiInParentheses() {
        XCTAssertEqual(verb(dict: "たべる", kanji: "食べる").displayTitle, "たべる (食べる)")
    }

    func testVerbTitleIsTheDictionaryFormWithoutKanji() {
        XCTAssertEqual(verb(dict: "する", kanji: nil).displayTitle, "する")
    }

    func testWordTitlePutsTheKanjiInParentheses() {
        XCTAssertEqual(word(dict: "たべもの", kanji: "食べ物").displayTitle, "たべもの (食べ物)")
        XCTAssertEqual(word(dict: "ぱん", kanji: nil).displayTitle, "ぱん")
    }

    func testTheSlotSourceProtocolUsesTheSameTitle() {
        let source: any SlotSource = word(dict: "たべる", kanji: "食べる")
        XCTAssertEqual(source.displayTitle, "たべる (食べる)")
    }
}
