import XCTest
@testable import VerbKit

final class SVGPathDataTests: XCTestCase {
    private func p(_ x: Double, _ y: Double) -> SVGPoint { SVGPoint(x: x, y: y) }

    private func end(_ e: SVGPathElement) -> SVGPoint? {
        switch e {
        case let .move(q), let .line(q): q
        case let .quad(q, _): q
        case let .cubic(q, _, _): q
        case .close: nil
        }
    }

    func testAbsoluteAndRelativeCubics() {
        let e = SVGPathData.parse("M60 10C87 9 110 31 109 60c-1 28-23 50-51 49")
        XCTAssertEqual(e.first, .move(p(60, 10)))
        XCTAssertEqual(e[1], .cubic(to: p(109, 60), control1: p(87, 9), control2: p(110, 31)))
        XCTAssertEqual(e[2], .cubic(to: p(58, 109), control1: p(108, 88), control2: p(86, 110)))
    }

    func testImplicitRepeatAndSmoothCubic() {
        let repeated = SVGPathData.parse("M0 0C1 1 2 2 3 3 4 4 5 5 6 6")
        XCTAssertEqual(repeated.count, 3)
        XCTAssertEqual(repeated[2], .cubic(to: p(6, 6), control1: p(4, 4), control2: p(5, 5)))
        // s reflects the previous second control (40,10 about 50,20 → 60,30).
        let smooth = SVGPathData.parse("M0 0C10 0 40 10 50 20s22 44 46 46")
        XCTAssertEqual(smooth[2], .cubic(to: p(96, 66), control1: p(60, 30), control2: p(72, 64)))
    }

    func testArcBecomesCubicsEndingAtTheEndpoint() {
        let e = SVGPathData.parse(StampShape.ring(48))
        XCTAssertGreaterThan(e.count, 2)
        let last = end(e.last!)!
        XCTAssertEqual(last.x, 59.9, accuracy: 0.001)
        XCTAssertEqual(last.y, 12, accuracy: 0.001)
        for element in e { if let q = end(element) {
            XCTAssertEqual(hypot(q.x - 60, q.y - 60), 48, accuracy: 0.5)
        } }
    }

    func testHorizontalDotAndClose() {
        XCTAssertEqual(SVGPathData.parse("M22 30h.01"), [.move(p(22, 30)), .line(p(22.01, 30))])
        XCTAssertEqual(SVGPathData.parse("M0 0L1 1z").last, .close)
    }

    func testGarbageStopsWithoutCrashing() {
        XCTAssertEqual(SVGPathData.parse("M1 2 X 3"), [.move(p(1, 2))])
    }
}
