import SwiftUI
import VerbKit

/// The top of a results screen: the score inside the theme half's results stamp (Light: a
/// teacher's red circle; canvas board "Theme personality"), beside "Quiz complete" and a few muted lines. On ruled genkō paper.
struct QuizScoreCard: View {
    let score: Int
    let count: Int
    let lines: [String]
    @Environment(\.palette) private var palette
    @Environment(\.themeHalf) private var half
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var stampSize: CGFloat = 120
    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize: CGFloat = 44
    @ScaledMetric(relativeTo: .largeTitle) private var countSize: CGFloat = 22
    @State private var drawn: CGFloat = 0

    var body: some View {
        // At accessibility sizes the stamp sits above the text, so the lines keep a full width.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 16))
        layout {
            stamp
            VStack(alignment: .leading, spacing: 4) {
                Text("Quiz complete")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(palette.ink)
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(palette.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .paperCard(cornerRadius: 16, ruled: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((["Score \(score) out of \(count)"] + lines).joined(separator: ", "))
        .onAppear {
            if reduceMotion {
                drawn = 1
            } else {
                withAnimation(.easeOut(duration: 0.5)) { drawn = 1 }
            }
        }
    }

    private var stamp: some View {
        ZStack {
            // The theme half's results stamp, drawn in like a pen at the board's widths.
            let stamp = ThemeStamp.stamp(for: half.theme, isDark: half.isDark)
            ForEach(Array(stamp.shape.strokes.enumerated()), id: \.offset) { _, stroke in
                StampStrokeShape(d: stroke.d)
                    .trim(from: 0, to: drawn)
                    .stroke(
                        stroke.usesSecondColor ? stamp.second : stamp.first,
                        style: StrokeStyle(lineWidth: stroke.baseWidth * stampSize / 120, lineCap: .round, lineJoin: .round)
                    )
            }
            // Fixed sizes: the metrics above already scale with Dynamic Type, like the ring, so
            // the score must not scale a second time or it outgrows the ring.
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(score)")
                    .font(.custom("HiraMinProN-W6", fixedSize: scoreSize))
                Text("/\(count)")
                    .font(.custom("HiraMinProN-W6", fixedSize: countSize))
            }
            // Red only inside the teacher's red circle; every other stamp leaves the score in ink.
            .foregroundStyle(half.isTeacher ? palette.mark : palette.ink)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            // The score keeps inside the smallest inner ring (raked, 37 of 120) at every size.
            .padding(stampSize * 0.2)
        }
        .frame(width: stampSize, height: stampSize)
    }
}

/// One stamp stroke from its SVG path data in the 120-unit box, scaled to the frame.
private struct StampStrokeShape: Shape {
    let d: String

    func path(in rect: CGRect) -> Path {
        Path(svg: SVGPathData.parse(d)).applying(
            CGAffineTransform(scaleX: rect.width / 120, y: rect.height / 120)
                .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        )
    }
}

extension View {
    /// A results screen's actions pinned to the bottom on the theme's paper: the primary action
    /// (when there is one) above Done.
    func quizResultsActions(practise: String?, onPractise: @escaping () -> Void, onDone: @escaping () -> Void) -> some View {
        modifier(QuizResultsActions(practise: practise, onPractise: onPractise, onDone: onDone))
    }
}

private struct QuizResultsActions: ViewModifier {
    let practise: String?
    let onPractise: () -> Void
    let onDone: () -> Void
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if let practise {
                    Button(practise, action: onPractise).buttonStyle(.paper)
                }
                Button("Done", action: onDone).buttonStyle(.paperSecondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(palette.paper)
        }
    }
}
