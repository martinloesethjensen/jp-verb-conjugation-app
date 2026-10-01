import XCTest
@testable import VerbKit

final class RomajiTests: XCTestCase {
    private func kana(_ text: String) -> String? { Romaji.toHiragana(text) }

    func testBasicWords() {
        XCTAssertEqual(kana("taberu"), "たべる")
        XCTAssertEqual(kana("tabemashita"), "たべました")
        XCTAssertEqual(kana("nomu"), "のむ")
        XCTAssertEqual(kana("ikimasu"), "いきます")
    }

    func testHepburnAndNihonShikiVariants() {
        XCTAssertEqual(kana("shi"), "し")
        XCTAssertEqual(kana("si"), "し")
        XCTAssertEqual(kana("chi"), "ち")
        XCTAssertEqual(kana("ti"), "ち")
        XCTAssertEqual(kana("tsu"), "つ")
        XCTAssertEqual(kana("tu"), "つ")
        XCTAssertEqual(kana("fu"), "ふ")
        XCTAssertEqual(kana("hu"), "ふ")
        XCTAssertEqual(kana("ja"), "じゃ")
        XCTAssertEqual(kana("zya"), "じゃ")
        XCTAssertEqual(kana("jya"), "じゃ")
        XCTAssertEqual(kana("sha"), "しゃ")
        XCTAssertEqual(kana("sya"), "しゃ")
        XCTAssertEqual(kana("cho"), "ちょ")
        XCTAssertEqual(kana("tyo"), "ちょ")
        XCTAssertEqual(kana("kyu"), "きゅ")
        XCTAssertEqual(kana("wo"), "を")
    }

    func testLongVowels() {
        XCTAssertEqual(kana("ou"), "おう")
        XCTAssertEqual(kana("oo"), "おお")
        XCTAssertEqual(kana("ō"), "おう")
        XCTAssertEqual(kana("kyō"), "きょう")
        XCTAssertEqual(kana("aa"), "ああ")
        XCTAssertEqual(kana("ī"), "いい")
    }

    func testDoubledConsonants() {
        XCTAssertEqual(kana("kka"), "っか")
        XCTAssertEqual(kana("kitte"), "きって")
        XCTAssertEqual(kana("zasshi"), "ざっし")
        XCTAssertEqual(kana("matchi"), "まっち")
        XCTAssertEqual(kana("ippai"), "いっぱい")
    }

    func testNRules() {
        XCTAssertEqual(kana("kan"), "かん")
        XCTAssertEqual(kana("kanji"), "かんじ")
        XCTAssertEqual(kana("kanna"), "かんな")
        XCTAssertEqual(kana("konnichiwa"), "こんにちわ")
        XCTAssertEqual(kana("kin'en"), "きんえん")
        XCTAssertEqual(kana("n'a"), "んあ")
        XCTAssertEqual(kana("na"), "な")
        XCTAssertEqual(kana("nya"), "にゃ")
        XCTAssertEqual(kana("shinbun"), "しんぶん")
        XCTAssertEqual(kana("annai"), "あんない")
        XCTAssertEqual(kana("onna"), "おんな")
    }

    func testSmallKana() {
        XCTAssertEqual(kana("xtu"), "っ")
        XCTAssertEqual(kana("ltu"), "っ")
        XCTAssertEqual(kana("xa"), "ぁ")
        XCTAssertEqual(kana("xya"), "ゃ")
    }

    func testCaseAndWhitespace() {
        XCTAssertEqual(kana("TaBeRu"), "たべる")
        XCTAssertEqual(kana("tabe ru"), "たべ る")
    }

    func testPartialEndingIsDropped() {
        XCTAssertEqual(kana("tab"), "た")
        XCTAssertEqual(kana("tabesh"), "たべ")
        XCTAssertEqual(kana("tabets"), "たべ")
        XCTAssertEqual(kana("tabeky"), "たべ")
    }

    func testMixedKanaAndLatinPassesKanaThrough() {
        XCTAssertEqual(kana("食beru"), "食べる")
        XCTAssertEqual(kana("たべru"), "たべる")
    }

    func testNilWhenNothingToConvert() {
        XCTAssertNil(kana(""))
        XCTAssertNil(kana("   "))
        XCTAssertNil(kana("たべる"))
        XCTAssertNil(kana("食べる"))
        XCTAssertNil(kana("k"))
        XCTAssertNil(kana("sh"))
    }

    func testNilForUnconvertibleLetters() {
        XCTAssertNil(kana("qux"))
        XCTAssertNil(kana("tabeqru"))
    }
}
