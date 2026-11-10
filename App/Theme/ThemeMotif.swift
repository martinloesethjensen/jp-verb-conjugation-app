import SwiftUI
import VerbKit

/// The theme half that is showing: what `themedRoot()` resolved, with the seasonal override.
struct ThemeHalf: Equatable {
    let theme: ThemeID
    let isDark: Bool

    /// Light's light half: the teacher's red circle, the one stamp whose score is red.
    var isTeacher: Bool { theme == .light && !isDark }
}

extension EnvironmentValues {
    @Entry var themeHalf = ThemeHalf(theme: .light, isDark: false)
}

/// A theme half's title motif and its three colours, from the canvas board "Theme personality".
struct ThemeMotif: Equatable {
    let motif: TitleMotif
    let colors: [Color]

    private init(_ motif: TitleMotif, _ hexes: UInt32...) {
        self.motif = motif
        self.colors = hexes.map { Color(hex: $0) }
    }

    func color(_ slot: MotifColor) -> Color {
        func at(_ i: Int) -> Color { colors.isEmpty ? .clear : colors[min(i, colors.count - 1)] }
        switch slot {
        case .first: return at(0)
        case .second: return at(1)
        case .third: return at(2)
        case let .fixed(hex): return Color(hex: hex)
        }
    }

    static func motif(for theme: ThemeID, isDark: Bool) -> ThemeMotif {
        switch (theme, isDark) {
        case (.light, false): ThemeMotif(.hanko, 0xC2372B)
        case (.light, true): ThemeMotif(.brush, 0xE9EBE6)
        case (.pastel, _): ThemeMotif(.bubbles)
        case (.sand, false): ThemeMotif(.rake, 0xA8743A)
        case (.sand, true): ThemeMotif(.rake, 0xC08A4A)
        case (.matcha, false): ThemeMotif(.enso, 0x4A6B35)
        case (.matcha, true): ThemeMotif(.enso, 0x8FBF6A)
        case (.latte, false): ThemeMotif(.heart, 0xA8714A)
        case (.latte, true): ThemeMotif(.steam, 0xB8A796)
        case (.iceCream, _): ThemeMotif(.sprinkles)
        case (.northernLights, false): ThemeMotif(.aurora, 0x1FAE84, 0x2A8FB0, 0x7C5FD6)
        case (.northernLights, true): ThemeMotif(.aurora, 0x5FE3B0, 0x4CC3D9, 0xA78BFA)
        case (.nocturnal, false): ThemeMotif(.moon, 0x7A70E0, 0x3D3680)
        case (.nocturnal, true): ThemeMotif(.moon, 0xB9B3FF, 0xD9D7F0)
        case (.halloween, false): ThemeMotif(.pumpkin, 0xE2701A, 0x4D7A2A)
        case (.halloween, true): ThemeMotif(.pumpkin, 0xFF8A2A, 0x9AD36A)
        case (.christmas, false): ThemeMotif(.snow, 0x1F6B45)
        case (.christmas, true): ThemeMotif(.snow, 0xF1ECE0)
        }
    }
}

/// The showing theme half's motif, still, in the board's 64×40 box scaled to 56×35 pt.
struct TitleMotifView: View {
    @Environment(\.themeHalf) private var half

    static let size = CGSize(width: 56, height: 35)

    var body: some View {
        let motif = ThemeMotif.motif(for: half.theme, isDark: half.isDark)
        Canvas { context, size in
            let scale = size.width / 64
            for stroke in motif.motif.strokes {
                let path = Path(svg: SVGPathData.parse(stroke.d))
                    .applying(CGAffineTransform(scaleX: scale, y: scale))
                context.stroke(
                    path,
                    with: .color(motif.color(stroke.color)),
                    style: StrokeStyle(lineWidth: stroke.width * scale, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityHidden(true)
    }
}
