import XCTest
@testable import VerbKit

final class JapaneseNormalizerTests: XCTestCase {
    // MARK: key

    func testFullAndHalfWidthFold() {
        XCTAssertEqual(JapaneseNormalizer.key("ＡＢＣ"), "abc")
        XCTAssertEqual(JapaneseNormalizer.key("ｶﾀｶﾅ"), "かたかな")
        XCTAssertEqual(JapaneseNormalizer.key("ｶﾞｲﾄﾞ"), "がいど")
    }

    func testKatakanaBecomesHiragana() {
        XCTAssertEqual(JapaneseNormalizer.key("カタカナ"), "かたかな")
        XCTAssertEqual(JapaneseNormalizer.key("ヴ"), "ゔ")
    }

    func testLatinIsLowercasedAndDiacriticsFolded() {
        XCTAssertEqual(JapaneseNormalizer.key("Ōsaka"), "osaka")
        XCTAssertEqual(JapaneseNormalizer.key("Kyūshū"), "kyushu")
    }

    func testDakutenAreNotFolded() {
        XCTAssertNotEqual(JapaneseNormalizer.key("が"), JapaneseNormalizer.key("か"))
        XCTAssertNotEqual(JapaneseNormalizer.key("ぱ"), JapaneseNormalizer.key("は"))
    }

    func testWhitespaceIsTrimmedAndCollapsed() {
        XCTAssertEqual(JapaneseNormalizer.key("  thank   you \n"), "thank you")
        XCTAssertEqual(JapaneseNormalizer.key("お腹\u{3000}すいた"), "お腹 すいた")
    }

    // MARK: looseKey

    func testLooseKeyFoldsLongVowels() {
        XCTAssertEqual(JapaneseNormalizer.looseKey("おおきに"), JapaneseNormalizer.looseKey("おきに"))
        XCTAssertEqual(JapaneseNormalizer.looseKey("コーヒー"), JapaneseNormalizer.looseKey("こひ"))
        XCTAssertEqual(JapaneseNormalizer.looseKey("せんせい"), JapaneseNormalizer.looseKey("せんせ"))
        XCTAssertEqual(JapaneseNormalizer.looseKey("おねえさん"), JapaneseNormalizer.looseKey("おねさん"))
    }

    func testLooseKeyKeepsDakuten() {
        XCTAssertNotEqual(JapaneseNormalizer.looseKey("がっこう"), JapaneseNormalizer.looseKey("かっこう"))
    }

    // MARK: tagKey

    func testTagKeyMatchesRomajiKanaAndSuffixVariants() {
        let expected = JapaneseNormalizer.tagKey("おおさか")
        for variant in ["Osaka-ben", "osaka ben", "OSAKA", "おおさかべん", "Ōsaka", "Oosaka"] {
            XCTAssertEqual(JapaneseNormalizer.tagKey(variant), expected, variant)
        }
    }

    func testTagKeyDropsTheDialectSuffixFromKanji() {
        XCTAssertEqual(JapaneseNormalizer.tagKey("大阪弁"), JapaneseNormalizer.tagKey("大阪"))
        XCTAssertEqual(JapaneseNormalizer.tagKey("沖縄方言"), JapaneseNormalizer.tagKey("沖縄"))
        XCTAssertEqual(JapaneseNormalizer.tagKey("名古屋ことば"), JapaneseNormalizer.tagKey("名古屋"))
    }

    func testTagKeyDoesNotConvertKanjiToKana() {
        XCTAssertNotEqual(JapaneseNormalizer.tagKey("大阪弁"), JapaneseNormalizer.tagKey("Osaka-ben"))
    }

    func testTagKeyKeepsASuffixThatIsTheWholeName() {
        XCTAssertFalse(JapaneseNormalizer.tagKey("弁").isEmpty)
    }

    // MARK: kanaForm

    func testKanaFormConvertsLatinOnly() {
        XCTAssertEqual(JapaneseNormalizer.kanaForm("ookini"), "おおきに")
        XCTAssertEqual(JapaneseNormalizer.kanaForm("Ookini"), "おおきに")
        XCTAssertNil(JapaneseNormalizer.kanaForm("おおきに"))
        XCTAssertNil(JapaneseNormalizer.kanaForm(""))
    }
}
