import SwiftUI
import VerbKit

/// One kanji stroke, scaled from KanjiVG's 109-unit box into the rect (uniform scale, centred).
struct KanjiStrokeShape: Shape {
    let stroke: KanjiStroke

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / KanjiStroke.boxSize
        let dx = rect.minX + (rect.width - KanjiStroke.boxSize * scale) / 2
        let dy = rect.minY + (rect.height - KanjiStroke.boxSize * scale) / 2
        return Path(svg: stroke.elements)
            .applying(CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(translationX: dx, y: dy)))
    }
}

/// A kanji's strokes up to `shown`, as the stroke-order boards draw them: the strokes before the
/// current one in ink, the current one in red (drawn on over 0.6 s when `animatesCurrent`, unless
/// Reduce Motion is on), the rest faint; optional dashed centre guides, stroke numbers and a red dot
/// where the current stroke starts. Square; all sizes are in box units so it scales to any frame.
struct KanjiStrokeCanvas: View {
    let strokes: [KanjiStroke]
    /// How many strokes are drawn so far (1-based; 0 shows only the faint strokes).
    var shown: Int
    var highlightsCurrent = true
    var showsGuides = true
    var showsNumbers = true
    var showsStartDot = true
    var showsFutureStrokes = true
    /// Line width in box units.
    var lineWidth: CGFloat = 4
    var animatesCurrent = false

    static let drawDuration = 0.6

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 1

    private var current: Int { shown - 1 }

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let scale = side / KanjiStroke.boxSize
            ZStack(alignment: .topLeading) {
                if showsGuides { guides(side: side, scale: scale) }
                ForEach(strokes.indices, id: \.self) { index in
                    if index < shown || showsFutureStrokes {
                        KanjiStrokeShape(stroke: strokes[index])
                            .trim(from: 0, to: index == current ? progress : 1)
                            .stroke(color(for: index), style: StrokeStyle(lineWidth: lineWidth * scale,
                                                                          lineCap: .round, lineJoin: .round))
                    }
                }
                if showsNumbers {
                    ForEach(0..<min(shown, strokes.count), id: \.self) { index in
                        Text("\(index + 1)")
                            .font(.system(size: 7 * scale, weight: .medium))
                            .foregroundStyle(index == current && highlightsCurrent ? palette.mark : palette.muted)
                            .position(x: strokes[index].labelPoint.x * scale, y: strokes[index].labelPoint.y * scale)
                    }
                }
                if showsStartDot, strokes.indices.contains(current) {
                    Circle()
                        .fill(palette.mark)
                        .frame(width: 5.2 * scale, height: 5.2 * scale)
                        .position(x: strokes[current].start.x * scale, y: strokes[current].start.y * scale)
                }
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear { drawCurrent() }
        .onChange(of: shown) { drawCurrent() }
    }

    private func color(for index: Int) -> Color {
        if index < current { return palette.ink }
        if index == current { return highlightsCurrent ? palette.mark : palette.ink }
        return palette.rule
    }

    private func guides(side: CGFloat, scale: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: side / 2, y: 4 * scale))
            path.addLine(to: CGPoint(x: side / 2, y: side - 4 * scale))
            path.move(to: CGPoint(x: 4 * scale, y: side / 2))
            path.addLine(to: CGPoint(x: side - 4 * scale, y: side / 2))
        }
        .stroke(palette.rule, style: StrokeStyle(lineWidth: max(0.5, 0.6 * scale), dash: [2 * scale, 2 * scale]))
    }

    private func drawCurrent() {
        guard animatesCurrent, !reduceMotion else {
            progress = 1
            return
        }
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { progress = 0 }
        withAnimation(.easeOut(duration: Self.drawDuration)) { progress = 1 }
    }
}

#Preview("食, stroke 4") {
    let strokes = KanjiEntry(character: "食", strokes: [
        "M52.75,10.5c0.11,0.98-0.19,2.67-0.97,3.93C45,25.34,31.75,41.19,14,51.5",
        "M52.75,16.25c5.09,4.8,25.71,19.61,33.7,24.9c2.68,1.78,5.37,2.79,8.55,3.35",
        "M52.25,29.25c1,1,1.5,2.25,1.5,3.5c0,2,0,3,0,5.5",
        "M38,40c0.83,0.47,2.19,1,3.86,0.83c9.39-0.96,21.95-2.76,23.25-2.84c1.67-0.1,3.14,0.88,3.11,2.53C68.2,41.8,67,53.25,66.34,62.4c-0.07,0.94-0.13,1.36-0.13,1.99",
        "M40.83,51.73C47.25,51.25,59.5,50,66,49.75",
    ]).parsedStrokes
    KanjiStrokeCanvas(strokes: strokes, shown: 4, animatesCurrent: true)
        .frame(width: 200, height: 200)
        .themedRoot()
}
