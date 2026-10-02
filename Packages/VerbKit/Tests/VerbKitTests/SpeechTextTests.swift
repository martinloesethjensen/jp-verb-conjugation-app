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

    /// Fixed vectors shared with scripts/test_generate_audio.py.
    func testClipNameMatchesGeneratorScript() {
        XCTAssertEqual(SpeechText.clipName(for: "たべます"), "1a593dff4eea79de")
        XCTAssertEqual(SpeechText.clipName(for: "頭が痛いんです。"), "da00c4fac207a253")
    }
}
