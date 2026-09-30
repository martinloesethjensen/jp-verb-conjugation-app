import XCTest
@testable import VerbKit

final class FuriganaDictionaryTests: XCTestCase {
    private let dictionary = FuriganaDictionary(readings: [
        "食": "た", "日本語": "にほんご", "来": "く", "来ら": "こ", "来た": "き",
        "今日": "きょう", "今夜": "こんや", "何": "なに", "毎日": "まいにち", "学校": "がっこう",
        "買": "か", "昨日": "きのう", "行": "い", "遅": "おそ", "遅れ": "おく", "三": "さん",
    ])

    private func plain(_ text: String, glue: Bool = false) -> TextUnit {
        TextUnit(text: text, reading: nil, glueToPrevious: glue)
    }

    private func ruby(_ text: String, _ reading: String) -> TextUnit {
        TextUnit(text: text, reading: reading, glueToPrevious: false)
    }

    // MARK: basics

    func testEmptyStringHasNoUnits() {
        XCTAssertEqual(dictionary.units(for: ""), [])
    }

    func testKanaOnlyTextIsChunkedAFewCharactersAtATime() {
        XCTAssertEqual(dictionary.units(for: "たべる"), [plain("たべる")])
        XCTAssertEqual(
            dictionary.units(for: "ありがとうございます"),
            [plain("ありが"), plain("とうご"), plain("ざいま"), plain("す")]
        )
    }

    // MARK: kanji matching

    func testKanjiGetsItsReadingAndOkuriganaStaysPlain() {
        XCTAssertEqual(dictionary.units(for: "食べる"), [ruby("食", "た"), plain("べる", glue: true)])
    }

    func testOneEntryCoversEveryConjugationOfAVerb() {
        XCTAssertEqual(dictionary.units(for: "食べた"), [ruby("食", "た"), plain("べた", glue: true)])
        // "べられる" is four plain characters, so it is cut into pieces of at most three.
        XCTAssertEqual(dictionary.units(for: "食べられる"), [ruby("食", "た"), plain("べられ", glue: true), plain("る")])
    }

    func testKanaAfterTheKanjiCanSelectADifferentReading() {
        XCTAssertEqual(dictionary.units(for: "来る"), [ruby("来", "く"), plain("る", glue: true)])
        XCTAssertEqual(dictionary.units(for: "来られる"), [ruby("来", "こ"), plain("られる", glue: true)])
        XCTAssertEqual(dictionary.units(for: "来た"), [ruby("来", "き"), plain("た", glue: true)])
    }

    func testTheLongestKeyWins() {
        XCTAssertEqual(dictionary.units(for: "遅れた"), [ruby("遅", "おく"), plain("れた", glue: true)])
        XCTAssertEqual(dictionary.units(for: "遅い"), [ruby("遅", "おそ"), plain("い", glue: true)])
    }

    func testACompoundIsReadAsOneUnit() {
        XCTAssertEqual(dictionary.units(for: "日本語が"), [ruby("日本語", "にほんご"), plain("が", glue: true)])
        XCTAssertEqual(dictionary.units(for: "今日は"), [ruby("今日", "きょう"), plain("は", glue: true)])
    }

    func testWordsWrittenBackToBackAreSplitAtTheirBoundaries() {
        XCTAssertEqual(
            dictionary.units(for: "毎日学校"),
            [ruby("毎日", "まいにち"), ruby("学校", "がっこう")]
        )
        XCTAssertEqual(
            dictionary.units(for: "昨日買った"),
            [ruby("昨日", "きのう"), ruby("買", "か"), plain("った", glue: true)]
        )
        XCTAssertEqual(
            dictionary.units(for: "今夜何"),
            [ruby("今夜", "こんや"), ruby("何", "なに")]
        )
    }

    func testOkuriganaIsGluedToItsKanjiSoALineNeverBreaksBetweenThem() {
        let units = dictionary.units(for: "食べる")
        XCTAssertFalse(units[0].glueToPrevious)
        XCTAssertTrue(units[1].glueToPrevious)
    }

    func testOnlyKanaRightAfterAReadKanjiIsGlued() {
        // "ありがとう" is plain text far from any kanji; "猫" is unread, so nothing is glued to it.
        XCTAssertTrue(dictionary.units(for: "ありがとう").allSatisfy { !$0.glueToPrevious })
        XCTAssertTrue(dictionary.units(for: "猫が").allSatisfy { !$0.glueToPrevious })
        // Only the first piece after the kanji is glued, not the whole tail.
        let tail = dictionary.units(for: "食べられるのです")
        XCTAssertEqual(tail.map(\.glueToPrevious), [false, true, false, false])
    }

    func testAnUnknownKanjiStaysPlainAndDoesNotStopTheRest() {
        XCTAssertEqual(dictionary.units(for: "猫が食べる"), [plain("猫"), plain("が"), ruby("食", "た"), plain("べる", glue: true)])
    }

    // MARK: English, punctuation and spacing

    func testEnglishWordsKeepTheirTrailingSpace() {
        XCTAssertEqual(
            dictionary.units(for: "Drop the 食 now"),
            [plain("Drop "), plain("the "), ruby("食", "た"), plain(" "), plain("now")]
        )
    }

    func testMixedJapaneseAndEnglish() {
        XCTAssertEqual(
            dictionary.units(for: "Written 来られる and read こられる."),
            [
                plain("Written "), ruby("来", "こ"), plain("られる", glue: true), plain(" "), plain("and "),
                plain("read "), plain("こられ"), plain("る"), plain(".", glue: true),
            ]
        )
    }

    func testClosingPunctuationAttachesToThePreviousUnit() {
        XCTAssertEqual(
            dictionary.units(for: "行く。"),
            [ruby("行", "い"), plain("く", glue: true), plain("。", glue: true)]
        )
        XCTAssertEqual(
            dictionary.units(for: "行く？"),
            [ruby("行", "い"), plain("く", glue: true), plain("？", glue: true)]
        )
    }

    func testPunctuationAfterARubyUnitAttachesToo() {
        XCTAssertEqual(dictionary.units(for: "三。"), [ruby("三", "さん"), plain("。", glue: true)])
    }

    func testPunctuationAtTheVeryStartHasNothingToAttachToSoItIsOrdinaryText() {
        XCTAssertEqual(dictionary.units(for: "。あ"), [plain("。あ")])
    }

    func testSpaceAndArrowBetweenJapaneseIsOrdinaryBreakableText() {
        // Plain text is chunked three characters at a time, spaces included.
        XCTAssertEqual(
            dictionary.units(for: "食べる → 食べた"),
            [ruby("食", "た"), plain("べる ", glue: true), plain("→ "), ruby("食", "た"), plain("べた", glue: true)]
        )
    }

    // MARK: helpers

    func testContainsKanji() {
        XCTAssertTrue(dictionary.containsKanji("食べる"))
        XCTAssertTrue(dictionary.containsKanji("Drop the 猫"))
        XCTAssertFalse(dictionary.containsKanji("たべる"))
        XCTAssertFalse(dictionary.containsKanji("plain English"))
        XCTAssertFalse(dictionary.containsKanji(""))
    }

    func testHasUnreadKanji() {
        XCTAssertFalse(dictionary.hasUnreadKanji(in: "食べる"))
        XCTAssertFalse(dictionary.hasUnreadKanji(in: "たべる"))
        XCTAssertTrue(dictionary.hasUnreadKanji(in: "猫が食べる"))
    }

    func testAnEmptyDictionaryReadsNothing() {
        XCTAssertTrue(FuriganaDictionary.empty.units(for: "食べる").allSatisfy { $0.reading == nil })
        XCTAssertTrue(FuriganaDictionary.empty.hasUnreadKanji(in: "食べる"))
    }

    // MARK: data file

    func testDecodesTheDataFile() throws {
        let json = """
        { "version": "1.0.0", "description": "d", "readings": { "食": "た", "来ら": "こ" } }
        """
        let file = try JSONDecoder().decode(FuriganaDataFile.self, from: Data(json.utf8))
        XCTAssertEqual(file.version, "1.0.0")
        XCTAssertEqual(file.readings, ["食": "た", "来ら": "こ"])
        XCTAssertEqual(FuriganaDictionary(file: file).units(for: "来らい").first, ruby("来", "こ"))
    }
}
