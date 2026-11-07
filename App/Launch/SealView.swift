import SwiftUI
import VerbKit

/// The 活 seal: a theme's stamp around 活, drawn exactly like the launch image and the app icon
/// (one 120-unit box: the stamp scaled 0.84 about the centre at the board's width × 1.8, then
/// 活 from `SealGlyph`). Fixed at 122 pt, the launch image's size; it never scales with text size.
struct SealView: View {
    let stamp: ThemeStamp
    let ink: Color

    static let side: CGFloat = 122

    var body: some View {
        Canvas { context, size in
            let unit = size.width / 120
            for stroke in stamp.shape.strokes {
                let path = Self.path(for: SVGPathData.parse(stroke.d))
                    .applying(CGAffineTransform(translationX: -60, y: -60)
                        .concatenating(CGAffineTransform(scaleX: 0.84 * unit, y: 0.84 * unit))
                        .concatenating(CGAffineTransform(translationX: 60 * unit, y: 60 * unit)))
                context.stroke(
                    path,
                    with: .color(stroke.usesSecondColor ? stamp.second : stamp.first),
                    style: StrokeStyle(lineWidth: stroke.baseWidth * 1.8 * 0.84 * unit, lineCap: .round, lineJoin: .round)
                )
            }
            context.fill(SealGlyph.path(in: CGRect(origin: .zero, size: size)), with: .color(ink))
        }
        .frame(width: Self.side, height: Self.side)
        .accessibilityHidden(true)
    }

    private static func path(for elements: [SVGPathElement]) -> Path {
        func cg(_ p: SVGPoint) -> CGPoint { CGPoint(x: p.x, y: p.y) }
        var path = Path()
        for element in elements {
            switch element {
            case let .move(to): path.move(to: cg(to))
            case let .line(to): path.addLine(to: cg(to))
            case let .quad(to, control): path.addQuadCurve(to: cg(to), control: cg(control))
            case let .cubic(to, c1, c2): path.addCurve(to: cg(to), control1: cg(c1), control2: cg(c2))
            case .close: path.closeSubpath()
            }
        }
        return path
    }
}
