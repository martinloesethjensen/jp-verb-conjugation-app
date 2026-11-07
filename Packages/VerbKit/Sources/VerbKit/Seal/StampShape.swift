import Foundation

/// One stroke of a stamp: SVG path data in the seal's 120-unit box, which of the theme's two
/// stamp colours it uses, and its width before the icon/seal weight factor.
public struct StampStroke: Equatable, Sendable {
    public let d: String
    public let usesSecondColor: Bool
    public let baseWidth: Double
}

/// The twelve results stamps from the canvas ("Theme personality", "App icons", "Themed first
/// frame"), as path data around 活 in a 120-unit box. Colours belong to the themes, in App.
public enum StampShape: String, CaseIterable, Sendable {
    case teacher, sumi, rings, raked, enso, heart, mug, scoop, aurora, moon, pumpkin, wreath

    public var strokes: [StampStroke] {
        func a(_ d: String, _ w: Double) -> StampStroke { StampStroke(d: d, usesSecondColor: false, baseWidth: w) }
        func b(_ d: String, _ w: Double) -> StampStroke { StampStroke(d: d, usesSecondColor: true, baseWidth: w) }
        switch self {
        case .teacher: return [a(Self.teacherPath, 3)]
        case .sumi: return [a(Self.sumiPath, 7)]
        case .rings: return [a(Self.ring(48), 5), b(Self.ring(40), 2)]
        case .raked: return [a(Self.ring(48), 1.6), a(Self.ring(42.5), 1.6), a(Self.ring(37), 1.6)]
        case .enso: return [a(Self.ensoPath, 6)]
        case .heart: return [a(Self.heartPath, 3)]
        case .mug: return [a(Self.ring(48), 6), a("M68 15a46 46 0 1 1-36 10", 2)]
        case .scoop: return [a(Self.scallop(cx: 60, cy: 60, r: 44, n: 14), 3)]
        case .aurora: return [a(Self.wavyRing(r: 46, amp: 2.5, n: 7), 2.5), b(Self.wavyRing(r: 39, amp: 2, n: 9), 1.5)]
        case .moon: return [a(Self.ring(46), 1.8), b(Self.moonPath, 2), b("M22 30h.01M30 100h.01M100 88h.01", 3)]
        case .pumpkin: return [a(Self.pumpkinPath, 3), b("M60 20c0-8 3-12 9-14", 3), b("M69 9c5-3 10-1 11 3", 2)]
        case .wreath: return [a(Self.ring(48), 7), b("M54 12h.01M62 10h.01M58 18h.01", 7)]
        }
    }

    static let teacherPath = "M60 10C87 9 110 31 109 60c-1 28-23 50-51 49C31 108 10 87 11 59 12 34 31 14 57 11"
    /// The lower-left sweep keeps 活's left stroke clear by the same gap as the teacher's circle.
    static let sumiPath = "M98 34C88 16 70 9 52 12 28 16 12 38 14 62s6 48 46 48c22 0 40-12 47-32"
    static let ensoPath = "M86 22C70 8 38 9 22 30S14 90 44 104s66 0 70-36c2-18-6-32-14-40"
    static let heartPath = "M60 110C24 86 4 62 12 36c6-18 32-24 48-6 16-18 42-12 48 6 8 26-12 50-48 74z"
    static let moonPath = "M95 13a13 13 0 1 0 10 21a10 10 0 1 1-10-21z"
    static let pumpkinPath = "M60 20C34 20 14 34 14 62s20 46 46 46 46-18 46-46-20-42-46-42z"

    /// A full circle of radius `r` about (60, 60), as the board writes it.
    public static func ring(_ r: Double) -> String {
        "M60 \(trim(60 - r))a\(trim(r)) \(trim(r)) 0 1 1-0.1 0"
    }

    /// An ice-cream scoop edge: `n` quadratic bumps around a circle.
    public static func scallop(cx: Double, cy: Double, r: Double, n: Int) -> String {
        var d = ""
        for i in 0...n {
            let a = Double(i) / Double(n) * 2 * .pi
            let x = Double(cx) + Double(r) * cos(a), y = Double(cy) + Double(r) * sin(a)
            if i == 0 { d += "M\(fixed1(x)),\(fixed1(y))"; continue }
            let m = (Double(i) - 0.5) / Double(n) * 2 * .pi
            let qx = Double(cx) + Double(r + 8) * cos(m), qy = Double(cy) + Double(r + 8) * sin(m)
            d += "Q\(fixed1(qx)),\(fixed1(qy)) \(fixed1(x)),\(fixed1(y))"
        }
        return d
    }

    /// A rippling ring: radius `r` waving by `amp`, `n` times around, in 96 straight steps.
    public static func wavyRing(r: Double, amp: Double, n: Int) -> String {
        var d = ""
        for i in 0...96 {
            let a = Double(i) / 96 * 2 * .pi
            let rr = Double(r) + Double(amp) * sin(a * Double(n))
            d += (i == 0 ? "M" : "L") + "\(fixed1(60 + rr * cos(a))),\(fixed1(60 + rr * sin(a)))"
        }
        return d
    }

    /// JavaScript's `toFixed(1)`.
    private static func fixed1(_ v: Double) -> String {
        let s = String(format: "%.1f", v)
        return s == "-0.0" ? "0.0" : s
    }

    /// JavaScript's default number formatting for the ring radii (48, 42.5).
    private static func trim(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(Double(v))
    }
}
