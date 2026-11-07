import XCTest
@testable import VerbKit

final class KanjiStrokeTests: XCTestCase {
    // 食's strokes 1 and 9, from data/kanji.json (KanjiVG).
    private let first = KanjiStroke(d: "M52.75,10.5c0.11,0.98-0.19,2.67-0.97,3.93C45,25.34,31.75,41.19,14,51.5")
    private let ninth = KanjiStroke(d: "M51.5,71C55.75,71,77,90,81,92.75c2.49,1.71,4.62,2.62,7.5,3.5")

    private func p(_ x: Double, _ y: Double) -> SVGPoint { SVGPoint(x: x, y: y) }

    private func assertNear(_ a: SVGPoint, _ b: SVGPoint, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: 0.01, file: file, line: line)
    }

    func testStartEndAndDirection() {
        assertNear(first.start, p(52.75, 10.5))
        assertNear(first.end, p(14, 51.5))
        XCTAssertEqual(first.direction, .downLeft)
        assertNear(ninth.end, p(88.5, 96.25))
        XCTAssertEqual(ninth.direction, .downRight)
        XCTAssertEqual(KanjiStroke(d: "M10,50c10,0,20,0,40,0").direction, .right)
        XCTAssertEqual(KanjiStroke(d: "M50,10c0,10,0,20,0,40").direction, .down)
        XCTAssertEqual(KanjiStroke(d: "M90,50c-10,0,-20,0,-40,0").direction, .left)
        XCTAssertEqual(KanjiStroke(d: "M10,90c10,-10,20,-20,40,-40").direction, .upRight)
    }

    func testLabelPointSitsBeforeTheStart() {
        // Stroke 1 starts heading almost straight down, so its number sits above the start.
        XCTAssertLessThan(first.labelPoint.y, first.start.y)
        XCTAssertEqual(first.labelPoint.x, first.start.x, accuracy: 1)
    }

    func testLabelPointStaysInTheBox() {
        let corner = KanjiStroke(d: "M2,2c1,1,2,2,3,3")
        XCTAssertTrue((4...105).contains(corner.labelPoint.x))
        XCTAssertTrue((4...105).contains(corner.labelPoint.y))
    }

    func testEntryParsesEveryStroke() {
        let entry = KanjiEntry(character: "食", strokes: [first, ninth].map(\.d))
        XCTAssertEqual(entry.parsedStrokes, [first, ninth])
    }

    func testAcceptsATraceNearTheStroke() {
        let drawn = [p(53, 72), p(65, 80), p(78, 89), p(87, 95)]
        XCTAssertEqual(StrokeMatcher.judge(drawn, against: ninth), .accepted)
    }

    func testATapIsTooShortNotAMiss() {
        XCTAssertEqual(StrokeMatcher.judge([p(52, 11)], against: first), .tooShort)
        XCTAssertEqual(StrokeMatcher.judge([p(52, 11), p(53, 12), p(53, 12.5)], against: first), .tooShort)
        XCTAssertEqual(StrokeMatcher.judge([], against: first), .tooShort)
    }

    func testReversedTraceIsReversed() {
        let drawn = [p(87, 95), p(78, 89), p(65, 80), p(53, 72)]
        XCTAssertEqual(StrokeMatcher.judge(drawn, against: ninth), .reversed)
    }

    func testFarStartIsWrongPlace() {
        let drawn = [p(82.75, 10.5), p(50, 30), p(14, 51.5)]
        XCTAssertEqual(StrokeMatcher.judge(drawn, against: first), .wrongPlace)
    }

    func testShortTickAtTheStartIsWrongPlace() {
        let drawn = [p(52, 11), p(46, 17), p(40, 23)]
        XCTAssertEqual(StrokeMatcher.judge(drawn, against: first), .wrongPlace)
    }

    func testSessionAdvancesOnlyOnAccepted() {
        var session = KanjiTraceSession(strokeCount: 3)
        session.submit(.reversed)
        XCTAssertEqual(session.step, 0)
        XCTAssertEqual(session.lastVerdict, .reversed)
        session.submit(.tooShort)
        XCTAssertEqual(session.lastVerdict, .reversed, "a tap does not clear or replace the last message")
        session.submit(.wrongPlace)
        XCTAssertEqual(session.lastVerdict, .wrongPlace)
        session.submit(.accepted)
        XCTAssertEqual(session.step, 1)
        XCTAssertEqual(session.lastVerdict, .accepted)
    }

    func testSessionFinishesAfterTheLastStroke() {
        var session = KanjiTraceSession(strokeCount: 2)
        XCTAssertFalse(session.isFinished)
        session.submit(.accepted)
        session.submit(.accepted)
        XCTAssertTrue(session.isFinished)
        session.submit(.accepted)
        XCTAssertEqual(session.step, 2, "nothing past the last stroke")
    }

    func testResetStartsOver() {
        var session = KanjiTraceSession(strokeCount: 2)
        session.submit(.accepted)
        session.submit(.reversed)
        session.reset()
        XCTAssertEqual(session, KanjiTraceSession(strokeCount: 2))
    }

    func testKunNotation() {
        XCTAssertEqual(KanjiReading.display("た.べる"), "た(べる)")
        XCTAssertEqual(KanjiReading.display("-かた"), "かた")
        XCTAssertEqual(KanjiReading.display("ひと-"), "ひと")
        XCTAssertEqual(KanjiReading.display("ひと"), "ひと")
    }
}
