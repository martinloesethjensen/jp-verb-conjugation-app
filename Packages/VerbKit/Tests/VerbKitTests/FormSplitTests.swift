import XCTest
@testable import VerbKit

final class FormSplitTests: XCTestCase {
    private func split(_ form: String, _ dict: String) -> FormSplit {
        FormSplit.split(form, from: dict)
    }

    func testARuVerbKeepsItsStem() {
        XCTAssertEqual(split("たべられる", "たべる"), FormSplit(stem: "たべ", ending: "られる"))
        XCTAssertEqual(split("たべます", "たべる"), FormSplit(stem: "たべ", ending: "ます"))
        XCTAssertEqual(split("たべていた", "たべる"), FormSplit(stem: "たべ", ending: "ていた"))
    }

    func testAUVerbKeepsOnlyTheLettersBeforeTheChangingKana() {
        XCTAssertEqual(split("のめる", "のむ"), FormSplit(stem: "の", ending: "める"))
        XCTAssertEqual(split("のみます", "のむ"), FormSplit(stem: "の", ending: "みます"))
        XCTAssertEqual(split("のんでいる", "のむ"), FormSplit(stem: "の", ending: "んでいる"))
        XCTAssertEqual(split("かって", "かう"), FormSplit(stem: "か", ending: "って"))
        XCTAssertEqual(split("いって", "いく"), FormSplit(stem: "い", ending: "って"))
    }

    func testIrregularVerbs() {
        // No shared prefix (する starts with す, しま with し): the whole form is the ending.
        XCTAssertEqual(split("します", "する"), FormSplit(stem: "", ending: "します"))
        XCTAssertEqual(split("した", "する"), FormSplit(stem: "", ending: "した"))
        XCTAssertEqual(split("きます", "くる"), FormSplit(stem: "", ending: "きます"))
        XCTAssertEqual(split("できる", "する"), FormSplit(stem: "", ending: "できる"))
    }

    func testAFormIdenticalToTheDictionaryFormHasNoEnding() {
        let result = split("たべる", "たべる")
        XCTAssertEqual(result, FormSplit(stem: "たべる", ending: ""))
        XCTAssertFalse(result.hasEnding)
    }

    func testAFormThatExtendsTheDictionaryFormKeepsItAsTheStem() {
        XCTAssertEqual(split("たべるんです", "たべる"), FormSplit(stem: "たべる", ending: "んです"))
    }

    func testAnEmptyFormAndAnEmptyDictionaryForm() {
        XCTAssertEqual(split("", "たべる"), FormSplit(stem: "", ending: ""))
        XCTAssertEqual(split("たべる", ""), FormSplit(stem: "", ending: "たべる"))
    }

    func testHasEndingIsTrueWhenSomethingChanged() {
        XCTAssertTrue(split("たべない", "たべる").hasEnding)
        XCTAssertTrue(split("きます", "くる").hasEnding)
    }
}
