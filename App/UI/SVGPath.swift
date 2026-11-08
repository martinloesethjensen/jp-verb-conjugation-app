import SwiftUI
import VerbKit

extension Path {
    /// A SwiftUI path from parsed SVG path data (`SVGPathData.parse`), in the same units.
    init(svg elements: [SVGPathElement]) {
        func cg(_ p: SVGPoint) -> CGPoint { CGPoint(x: p.x, y: p.y) }
        self.init()
        for element in elements {
            switch element {
            case let .move(to): move(to: cg(to))
            case let .line(to): addLine(to: cg(to))
            case let .quad(to, control): addQuadCurve(to: cg(to), control: cg(control))
            case let .cubic(to, c1, c2): addCurve(to: cg(to), control1: cg(c1), control2: cg(c2))
            case .close: closeSubpath()
            }
        }
    }
}
