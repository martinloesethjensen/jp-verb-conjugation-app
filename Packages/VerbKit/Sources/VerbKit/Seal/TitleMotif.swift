import Foundation

/// Which colour a motif stroke takes: one of its theme half's three motif colours, or a fixed
/// colour the board gives every half (the bubbles and the sprinkles).
public enum MotifColor: Hashable, Sendable {
    case first, second, third
    case fixed(UInt32)
}

/// One stroke of a title motif: SVG path data in the motif's 64×40 box, its colour and width.
public struct MotifStroke: Equatable, Sendable {
    public let d: String
    public let color: MotifColor
    public let width: Double
}

/// The small still motif beside a tab's large title, one per theme (canvas board "Theme
/// personality"). Path data only; the colours per theme half belong to App.
public enum TitleMotif: String, CaseIterable, Sendable {
    case hanko, brush, bubbles, rake, enso, heart, steam, sprinkles, aurora, moon, pumpkin, snow

    public var strokes: [MotifStroke] {
        func s(_ d: String, _ c: MotifColor, _ w: Double) -> MotifStroke { MotifStroke(d: d, color: c, width: w) }
        switch self {
        case .hanko:
            return [s("M40 8h16v16H40z", .first, 2), s("M44 13h8M48 13v7M44 20h8", .first, 1.6)]
        case .brush:
            return [s("M8 30C20 22 36 14 56 10", .first, 5), s("M50 26h.01", .first, 5)]
        case .bubbles:
            return [
                s("M18 20a7 7 0 1 1-0.1 0", .fixed(0x7CD4FD), 2.5),
                s("M34 12a6 6 0 1 1-0.1 0", .fixed(0xFDCA3E), 2.5),
                s("M48 22a8 8 0 1 1-0.1 0", .fixed(0xF87166), 2.5),
            ]
        case .rake:
            return [14, 22, 30].map { s("M4 \($0)c10-4 18-4 28 0s18 4 28 0", .first, 1.8) }
        case .enso:
            return [s("M48 8c-12-6-30 0-32 14s14 18 26 12c8-4 10-12 6-18", .first, 3)]
        case .heart:
            return [s("M32 33C20 25 17 17 21 12c3-3 8-2 11 2 3-4 8-5 11-2 4 5 1 13-11 21z", .first, 2.2)]
        case .steam:
            return [22, 32, 42].map { s("M\($0) 36c-4-6 4-10 0-16s4-10 0-16", .first, 2) }
        case .sprinkles:
            return [
                s("M12 10l5 3", .fixed(0xE07AA0), 3), s("M28 6l-2 5", .fixed(0x4FB393), 3),
                s("M44 12l5-1", .fixed(0xE0A92E), 3), s("M18 26l3 4", .fixed(0x4FB393), 3),
                s("M36 28l-4 3", .fixed(0xE07AA0), 3), s("M52 30l4 2", .fixed(0xE0A92E), 3),
            ]
        case .aurora:
            return [
                s("M4 32c10-12 18-12 28-4s20 8 28-6", .first, 2.5),
                s("M4 23c10-10 20-10 28-2s18 6 28-8", .second, 2.5),
                s("M4 14c12-8 20-6 28 0s18 4 28-8", .third, 2.5),
            ]
        case .moon:
            return [
                s("M46 6a14 14 0 1 0 12 22a11 11 0 1 1-12-22z", .first, 1.8),
                s("M14 12h.01", .second, 3), s("M26 28h.01", .second, 2.5), s("M8 30h.01", .second, 2),
            ]
        case .pumpkin:
            return [
                s("M32 14c-12 0-20 6-20 14s8 10 20 10 20-2 20-10-8-14-20-14z", .first, 2),
                s("M32 14c0-5 2-8 6-9", .second, 2),
            ]
        case .snow:
            return [s("M32 4v32M17 12l30 16M17 28l30-16M28 6l4 3 4-3M28 34l4-3 4 3", .first, 2)]
        }
    }
}
