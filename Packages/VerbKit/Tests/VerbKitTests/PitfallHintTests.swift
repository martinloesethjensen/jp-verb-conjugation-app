import XCTest
@testable import VerbKit

final class PitfallHintTests: XCTestCase {
    private func pitfall(_ heading: String, _ explanation: String) -> CounterPitfall {
        CounterPitfall(heading: heading, explanation: explanation)
    }

    func testTheHeadingIsKeptAndTheFirstSentenceIsCutAtTheStop() {
        let hint = pitfallHint(pitfall("Not さんほん", "After 3 the ほ turns into ぼ: さんぼん. The same happens at 何."))
        XCTAssertEqual(hint.heading, "Not さんほん")
        XCTAssertEqual(hint.firstSentence, "After 3 the ほ turns into ぼ: さんぼん.")
    }

    func testAJapaneseStopEndsTheSentenceToo() {
        XCTAssertEqual(pitfallHint(pitfall("h", "三本です。次の文。")).firstSentence, "三本です。")
    }

    func testWithoutAStopTheWholeTrimmedTextIsUsed() {
        XCTAssertEqual(pitfallHint(pitfall("h", "  Only up to ten  \n")).firstSentence, "Only up to ten")
    }
}
