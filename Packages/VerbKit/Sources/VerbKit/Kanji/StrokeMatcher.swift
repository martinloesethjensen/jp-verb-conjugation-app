import Foundation

/// How a drawn stroke compares with the one that was due.
public enum TraceVerdict: Equatable, Sendable {
    case accepted
    /// Too few points or too short to judge: a tap, not a mistake.
    case tooShort
    /// Drawn from the end towards the start.
    case reversed
    /// Started or ended too far from the stroke that was due.
    case wrongPlace
}

/// Judges a traced stroke by its ends and direction, in the 109-unit box. The rules are in
/// `docs/superpowers/specs/2026-11-07-kanji-stroke-order-design.md`.
public enum StrokeMatcher {
    static let minimumPoints = 3
    static let minimumLength = 6.0
    static let startTolerance = 24.0
    static let endTolerance = 30.0

    public static func judge(_ drawn: [SVGPoint], against stroke: KanjiStroke) -> TraceVerdict {
        guard drawn.count >= minimumPoints, let a = drawn.first, let b = drawn.last,
              length(of: drawn) >= minimumLength else { return .tooShort }
        let s = stroke.start, e = stroke.end
        if distance(a, e) + distance(b, s) < distance(a, s) + distance(b, e) {
            return .reversed
        }
        if distance(a, s) > startTolerance || distance(b, e) > endTolerance {
            return .wrongPlace
        }
        return .accepted
    }

    static func distance(_ a: SVGPoint, _ b: SVGPoint) -> Double {
        let dx = a.x - b.x, dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    static func length(of points: [SVGPoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }
}
