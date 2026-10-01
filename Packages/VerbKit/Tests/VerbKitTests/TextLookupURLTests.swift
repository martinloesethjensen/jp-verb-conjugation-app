import XCTest
@testable import VerbKit

final class TextLookupURLTests: XCTestCase {
    private let taberu = "%E9%A3%9F%E3%81%B9%E3%82%8B" // 食べる

    func testJishoSearchesTheEncodedText() {
        XCTAssertEqual(TextLookupURL.jisho("食べる")?.absoluteString, "https://jisho.org/search/" + taberu)
    }

    func testDeepLPutsTheEncodedTextInTheFragment() {
        XCTAssertEqual(
            TextLookupURL.deepL("食べる")?.absoluteString,
            "https://www.deepl.com/translator#ja/en/" + taberu
        )
    }

    func testGoogleUsesTheQueryString() {
        XCTAssertEqual(
            TextLookupURL.google("食べる")?.absoluteString,
            "https://translate.google.com/?sl=ja&tl=en&text=" + taberu + "&op=translate"
        )
    }

    func testKanaAndJapanesePunctuationAreEncoded() {
        let url = TextLookupURL.jisho("どうしたんですか。")
        XCTAssertEqual(
            url?.absoluteString,
            "https://jisho.org/search/%E3%81%A9%E3%81%86%E3%81%97%E3%81%9F%E3%82%93%E3%81%A7%E3%81%99%E3%81%8B%E3%80%82"
        )
    }

    func testCharactersThatCouldChangeTheShapeOfTheURLAreEscaped() {
        let text = "a/b?c#d%e&f g=h"
        for url in [TextLookupURL.jisho(text), TextLookupURL.deepL(text), TextLookupURL.google(text)] {
            let string = url?.absoluteString ?? ""
            XCTAssertTrue(string.contains("a%2Fb%3Fc%23d%25e%26f%20g%3Dh"), string)
        }
    }

    func testUnreservedAsciiIsLeftAlone() {
        XCTAssertEqual(TextLookupURL.jisho("Ab-1._~")?.absoluteString, "https://jisho.org/search/Ab-1._~")
    }

    func testTheTextRoundTripsThroughTheURL() throws {
        let sentence = "この曲は無料で聞けます。 / 100%？"
        let google = try XCTUnwrap(TextLookupURL.google(sentence))
        let components = try XCTUnwrap(URLComponents(url: google, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first { $0.name == "text" }?.value, sentence)
        let jisho = try XCTUnwrap(TextLookupURL.jisho(sentence))
        let prefix = "https://jisho.org/search/"
        XCTAssertEqual(String(jisho.absoluteString.dropFirst(prefix.count)).removingPercentEncoding, sentence)
    }

    func testBlankTextHasNoURL() {
        for text in ["", "   ", "\n\t "] {
            XCTAssertNil(TextLookupURL.jisho(text))
            XCTAssertNil(TextLookupURL.deepL(text))
            XCTAssertNil(TextLookupURL.google(text))
        }
    }

    func testSurroundingWhitespaceIsTrimmed() {
        XCTAssertEqual(TextLookupURL.jisho("  食べる \n")?.absoluteString, "https://jisho.org/search/" + taberu)
    }
}
