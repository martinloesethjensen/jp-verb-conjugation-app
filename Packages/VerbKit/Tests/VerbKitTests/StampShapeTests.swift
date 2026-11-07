import XCTest
@testable import VerbKit

final class StampShapeTests: XCTestCase {
    func testRingMatchesBoardString() {
        XCTAssertEqual(StampShape.ring(48), "M60 12a48 48 0 1 1-0.1 0")
    }

    func testScallopAndWavyRingStartLikeTheBoard() {
        XCTAssertTrue(StampShape.scallop(cx: 60, cy: 60, r: 44, n: 14).hasPrefix("M104.0,60.0Q"))
        XCTAssertTrue(StampShape.wavyRing(r: 46, amp: 2.5, n: 7).hasPrefix("M106.0,60.0L"))
    }

    func testStrokeTable() {
        XCTAssertEqual(StampShape.teacher.strokes.map(\.baseWidth), [3])
        XCTAssertEqual(StampShape.teacher.strokes.map(\.usesSecondColor), [false])
        XCTAssertEqual(StampShape.rings.strokes.map(\.baseWidth), [5, 2])
        XCTAssertEqual(StampShape.rings.strokes.map(\.usesSecondColor), [false, true])
        XCTAssertEqual(StampShape.moon.strokes.map(\.baseWidth), [1.8, 2, 3])
        XCTAssertEqual(StampShape.moon.strokes.map(\.usesSecondColor), [false, true, true])
    }

    /// Widened on 2026-11-07 so the brush circle no longer touches the foot of 活 (measured
    /// against the generated outline: 2.79 units clear, like the teacher's circle).
    func testSumiSweepsWideAtTheLowerLeft() {
        XCTAssertEqual(StampShape.sumi.strokes.first?.d, "M98 34C88 16 70 9 52 12 28 16 12 38 14 62s6 48 46 48c22 0 40-12 47-32")
    }

    func testEveryShapeParses() {
        for shape in StampShape.allCases {
            for stroke in shape.strokes {
                XCTAssertFalse(SVGPathData.parse(stroke.d).isEmpty, "\(shape) \(stroke.d)")
            }
        }
    }
}
