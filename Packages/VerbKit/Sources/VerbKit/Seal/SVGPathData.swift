import Foundation

/// A point in SVG user units. VerbKit stays Foundation-only; App converts to `CGPoint`.
public struct SVGPoint: Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public static let zero = SVGPoint(x: 0, y: 0)
}

/// One drawing step of a parsed SVG path, in absolute coordinates.
public enum SVGPathElement: Equatable, Sendable {
    case move(SVGPoint)
    case line(SVGPoint)
    case quad(to: SVGPoint, control: SVGPoint)
    case cubic(to: SVGPoint, control1: SVGPoint, control2: SVGPoint)
    case close
}

/// Reads SVG path data (`d` strings), so the canvas's stamp drawings can be drawn natively.
/// Handles M L H V C S Q A Z in both cases and implicit repeats; arcs become cubics.
public enum SVGPathData {
    /// The elements of `d`. Parsing stops at anything it can't read and returns what it has.
    public static func parse(_ d: String) -> [SVGPathElement] {
        var scanner = Tokens(Array(d))
        var out: [SVGPathElement] = []
        var current = SVGPoint.zero, start = SVGPoint.zero
        var lastCubicControl: SVGPoint?
        var command: Character?

        while true {
            scanner.skipSeparators()
            guard let next = scanner.peek() else { break }
            if next.isLetter {
                command = next
                scanner.advance()
            } else if command == nil {
                break
            }
            guard let cmd = command else { break }
            let relative = cmd.isLowercase
            func pt(_ x: Double, _ y: Double) -> SVGPoint {
                relative ? SVGPoint(x: current.x + x, y: current.y + y) : SVGPoint(x: x, y: y)
            }
            var smoothControl: SVGPoint?
            switch cmd.uppercased() {
            case "M":
                guard let x = scanner.number(), let y = scanner.number() else { return out }
                current = pt(x, y); start = current
                out.append(.move(current))
                command = relative ? "l" : "L"   // further pairs are line-tos
            case "L":
                guard let x = scanner.number(), let y = scanner.number() else { return out }
                current = pt(x, y); out.append(.line(current))
            case "H":
                guard let x = scanner.number() else { return out }
                current = SVGPoint(x: relative ? current.x + x : x, y: current.y); out.append(.line(current))
            case "V":
                guard let y = scanner.number() else { return out }
                current = SVGPoint(x: current.x, y: relative ? current.y + y : y); out.append(.line(current))
            case "C":
                guard let n = scanner.numbers(6) else { return out }
                let c1 = pt(n[0], n[1]), c2 = pt(n[2], n[3]), to = pt(n[4], n[5])
                out.append(.cubic(to: to, control1: c1, control2: c2))
                current = to; smoothControl = c2
            case "S":
                guard let n = scanner.numbers(4) else { return out }
                let c1 = lastCubicControl.map { SVGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let c2 = pt(n[0], n[1]), to = pt(n[2], n[3])
                out.append(.cubic(to: to, control1: c1, control2: c2))
                current = to; smoothControl = c2
            case "Q":
                guard let n = scanner.numbers(4) else { return out }
                let c = pt(n[0], n[1]), to = pt(n[2], n[3])
                out.append(.quad(to: to, control: c)); current = to
            case "A":
                guard let r = scanner.numbers(3), let large = scanner.flag(), let sweep = scanner.flag(),
                      let e = scanner.numbers(2) else { return out }
                let to = pt(e[0], e[1])
                out += arc(from: current, to: to, rx: r[0], ry: r[1], rotation: r[2], largeArc: large, sweep: sweep)
                current = to
            case "Z":
                out.append(.close); current = start
            default:
                return out
            }
            lastCubicControl = smoothControl
        }
        return out
    }

    /// SVG implementation notes F.6.5/F.6.6: endpoint to centre parameterisation, then one
    /// cubic per segment of at most 90°.
    private static func arc(from p1: SVGPoint, to p2: SVGPoint, rx rxIn: Double, ry ryIn: Double,
                            rotation: Double, largeArc: Bool, sweep: Bool) -> [SVGPathElement] {
        var rx = abs(rxIn), ry = abs(ryIn)
        guard rx > 0, ry > 0, p1 != p2 else { return [.line(p2)] }
        let phi = rotation * .pi / 180, cosP = cos(phi), sinP = sin(phi)
        let dx = (p1.x - p2.x) / 2, dy = (p1.y - p2.y) / 2
        let x1p = cosP * dx + sinP * dy, y1p = -sinP * dx + cosP * dy
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var coef = sqrt(max(0, num / den))
        if largeArc == sweep { coef = -coef }
        let cxp = coef * rx * y1p / ry, cyp = -coef * ry * x1p / rx
        let cx = cosP * cxp - sinP * cyp + (p1.x + p2.x) / 2
        let cy = sinP * cxp + cosP * cyp + (p1.y + p2.y) / 2
        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return a
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2) - 1e-9)))
        let step = delta / Double(segments)
        let k = 4 / 3 * tan(step / 4)
        func point(_ t: Double) -> SVGPoint {
            SVGPoint(x: cx + rx * cos(t) * cosP - ry * sin(t) * sinP, y: cy + rx * cos(t) * sinP + ry * sin(t) * cosP)
        }
        func derivative(_ t: Double) -> SVGPoint {
            SVGPoint(x: -rx * sin(t) * cosP - ry * cos(t) * sinP, y: -rx * sin(t) * sinP + ry * cos(t) * cosP)
        }
        var out: [SVGPathElement] = []
        var t = theta1
        for i in 0..<segments {
            let t2 = t + step
            let a = point(t), b = i == segments - 1 ? p2 : point(t2)
            let da = derivative(t), db = derivative(t2)
            out.append(.cubic(to: b,
                              control1: SVGPoint(x: a.x + k * da.x, y: a.y + k * da.y),
                              control2: SVGPoint(x: b.x - k * db.x, y: b.y - k * db.y)))
            t = t2
        }
        return out
    }

    private struct Tokens {
        let chars: [Character]
        var i = 0
        init(_ chars: [Character]) { self.chars = chars }

        func peek() -> Character? { i < chars.count ? chars[i] : nil }
        mutating func advance() { i += 1 }
        mutating func skipSeparators() {
            while let c = peek(), c == " " || c == "," || c == "\n" || c == "\t" || c == "\r" { i += 1 }
        }

        mutating func number() -> Double? {
            skipSeparators()
            var s = ""
            var seenDot = false, seenExp = false
            if let c = peek(), c == "-" || c == "+" { s.append(c); i += 1 }
            while let c = peek() {
                if c.isNumber { s.append(c); i += 1 }
                else if c == ".", !seenDot, !seenExp { seenDot = true; s.append(c); i += 1 }
                else if c == "e" || c == "E", !seenExp, !s.isEmpty {
                    seenExp = true; s.append(c); i += 1
                    if let sign = peek(), sign == "-" || sign == "+" { s.append(sign); i += 1 }
                } else { break }
            }
            return Double(s)
        }

        mutating func numbers(_ n: Int) -> [Double]? {
            var out: [Double] = []
            for _ in 0..<n { guard let v = number() else { return nil }; out.append(v) }
            return out
        }

        /// Arc flags may be written without separators ("0 1 1-0.1").
        mutating func flag() -> Bool? {
            skipSeparators()
            guard let c = peek(), c == "0" || c == "1" else { return nil }
            i += 1
            return c == "1"
        }
    }
}
