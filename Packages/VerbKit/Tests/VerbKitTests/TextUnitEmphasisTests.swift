import XCTest
@testable import VerbKit

final class TextUnitEmphasisTests: XCTestCase {
    func testSplitsPlainUnitAtBoundaries() {
        let units = [TextUnit(text: "あさごはんをたべます。")]
        XCTAssertEqual(TextUnit.emphasizing(units, characters: 6..<10), [
            TextUnit(text: "あさごはんを"),
            TextUnit(text: "たべます", glueToPrevious: true, isEmphasized: true),
            TextUnit(text: "。", glueToPrevious: true),
        ])
    }

    func testEmphasizesWholeRubyUnitWhenPartlyCovered() {
        let units = [TextUnit(text: "食べ", reading: "たべ"), TextUnit(text: "てから")]
        XCTAssertEqual(TextUnit.emphasizing(units, characters: 1..<3), [
            TextUnit(text: "食べ", reading: "たべ", isEmphasized: true),
            TextUnit(text: "て", isEmphasized: true),
            TextUnit(text: "から", glueToPrevious: true),
        ])
    }

    func testEmptyRangeLeavesUnitsUnchanged() {
        let units = [TextUnit(text: "食", reading: "た"), TextUnit(text: "べる")]
        XCTAssertEqual(TextUnit.emphasizing(units, characters: 2..<2), units)
    }

    func testRangePastEndIsClamped() {
        let units = [TextUnit(text: "たべます。")]
        XCTAssertEqual(TextUnit.emphasizing(units, characters: 3..<99), [
            TextUnit(text: "たべま"),
            TextUnit(text: "す。", glueToPrevious: true, isEmphasized: true),
        ])
    }
}
