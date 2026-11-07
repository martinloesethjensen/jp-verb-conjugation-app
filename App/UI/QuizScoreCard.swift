import SwiftUI

/// The top of a results screen: the score inside a red hand-drawn ring, like a teacher's mark on
/// a paper, beside "Quiz complete" and a few muted lines. On ruled genkō paper.
struct QuizScoreCard: View {
    let score: Int
    let count: Int
    let lines: [String]
    @Environment(\.palette) private var palette
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
            StampRing()
                .trim(from: 0, to: drawn)
                .stroke(palette.mark, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            // Fixed sizes: the metrics above already scale with Dynamic Type, like the ring, so
            // the score must not scale a second time or it outgrows the ring.
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(score)")
                    .font(.custom("HiraMinProN-W6", fixedSize: scoreSize))
                Text("/\(count)")
                    .font(.custom("HiraMinProN-W6", fixedSize: countSize))
            }
            .foregroundStyle(palette.mark)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .padding(18)
        }
        .frame(width: stampSize, height: stampSize)
    }
}

/// The board's hand-drawn ring, drawn in a 120 × 120 box and scaled to the frame:
/// M60 8 C88 7 112 30 111 60 c-1 29 -24 52 -53 51 C30 110 8 88 9 59 10 33 30 12 57 9
private struct StampRing: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 60, y: 8))
        path.addCurve(to: CGPoint(x: 111, y: 60), control1: CGPoint(x: 88, y: 7), control2: CGPoint(x: 112, y: 30))
        // Relative "c-1 29 -24 52 -53 51" from (111, 60).
        path.addCurve(to: CGPoint(x: 58, y: 111), control1: CGPoint(x: 110, y: 89), control2: CGPoint(x: 87, y: 112))
        path.addCurve(to: CGPoint(x: 9, y: 59), control1: CGPoint(x: 30, y: 110), control2: CGPoint(x: 8, y: 88))
        path.addCurve(to: CGPoint(x: 57, y: 9), control1: CGPoint(x: 10, y: 33), control2: CGPoint(x: 30, y: 12))
        let scale = CGAffineTransform(scaleX: rect.width / 120, y: rect.height / 120)
        return path.applying(scale.concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
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
