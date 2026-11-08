import Foundation

/// Which way a stroke runs, from its start to its end, in eight 45° sectors (y points down, so
/// `downLeft` is towards the lower left of the box).
public enum StrokeDirection: Equatable, Sendable {
    case right, downRight, down, downLeft, left, upLeft, up, upRight

    /// The sector of the vector (`dx`, `dy`); `right` covers −22.5° to 22.5°.
    init(dx: Double, dy: Double) {
        let degrees = atan2(dy, dx) * 180 / .pi
        switch degrees {
        case -22.5..<22.5: self = .right
        case 22.5..<67.5: self = .downRight
        case 67.5..<112.5: self = .down
        case 112.5..<157.5: self = .downLeft
        case -67.5 ..< -22.5: self = .upRight
        case -112.5 ..< -67.5: self = .up
        case -157.5 ..< -112.5: self = .upLeft
        default: self = .left
        }
    }
}

/// One stroke of a kanji, parsed from its KanjiVG path in the 109 × 109 box.
public struct KanjiStroke: Equatable, Sendable {
    /// The box's size: KanjiVG draws every kanji in 109 × 109 units.
    public static let boxSize = 109.0
    /// Numbers stay this far inside the box.
    static let labelRange = 4.0...105.0
    /// How far before the start, against the stroke's first direction, its number sits.
    static let labelOffset = 6.0

    public let d: String
    public let elements: [SVGPathElement]
    public let start: SVGPoint
    public let end: SVGPoint
    public let direction: StrokeDirection
    /// Where the stroke's number is drawn.
    public let labelPoint: SVGPoint

    public init(d: String) {
        self.d = d
        let elements = SVGPathData.parse(d)
        self.elements = elements
        var start = SVGPoint.zero
        var end = SVGPoint.zero
        var tangent: SVGPoint?
        for element in elements {
            switch element {
            case let .move(p):
                if tangent == nil && end == .zero { start = p }
                end = p
            case let .line(p):
                if tangent == nil { tangent = p }
                end = p
            case let .quad(p, c):
                if tangent == nil { tangent = c == end ? p : c }
                end = p
            case let .cubic(p, c1, _):
                if tangent == nil { tangent = c1 == end ? p : c1 }
                end = p
            case .close:
                break
            }
        }
        self.start = start
        self.end = end
        self.direction = StrokeDirection(dx: end.x - start.x, dy: end.y - start.y)
        let toward = tangent ?? end
        let dx = toward.x - start.x, dy = toward.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        let label = length > 0
            ? SVGPoint(x: start.x - dx / length * Self.labelOffset, y: start.y - dy / length * Self.labelOffset)
            : SVGPoint(x: start.x - Self.labelOffset, y: start.y)
        self.labelPoint = SVGPoint(x: min(max(label.x, Self.labelRange.lowerBound), Self.labelRange.upperBound),
                                   y: min(max(label.y, Self.labelRange.lowerBound), Self.labelRange.upperBound))
    }
}

extension KanjiEntry {
    /// Every stroke, parsed, in stroke order.
    public var parsedStrokes: [KanjiStroke] {
        strokes.map(KanjiStroke.init(d:))
    }
}
