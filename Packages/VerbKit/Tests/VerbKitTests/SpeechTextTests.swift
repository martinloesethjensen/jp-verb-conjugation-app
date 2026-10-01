import XCTest
@testable import VerbKit

final class SpeechTextTests: XCTestCase {
    func testKeepsKanaAndKanji() {
        XCTAssertEqual(SpeechText.spoken("たべます"), "たべます")
        XCTAssertEqual(SpeechText.spoken("食べる"), "食べる")
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(SpeechText.spoken("  たべる \n"), "たべる")
    }

    func testBlankIsNil() {
        XCTAssertNil(SpeechText.spoken(""))
        XCTAssertNil(SpeechText.spoken("   "))
    }

    func testReplacesSeparators() {
        XCTAssertEqual(SpeechText.spoken("たべる / のむ"), "たべる、のむ")
        XCTAssertEqual(SpeechText.spoken("~てしまう"), "てしまう")
    }

    func testKeepsSentencePunctuation() {
        XCTAssertEqual(SpeechText.spoken("頭が痛いんです。"), "頭が痛いんです。")
    }

    func testOnlySeparatorsIsNil() {
        XCTAssertNil(SpeechText.spoken(" ~ / "))
    }
}
