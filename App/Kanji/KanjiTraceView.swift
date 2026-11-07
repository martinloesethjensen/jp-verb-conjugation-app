import SwiftUI
import VerbKit

/// Trace: draw each stroke in order. A stroke drawn backwards or in the wrong place is shown in red
/// with the expected stroke and tried again; after the last stroke a red ring marks it finished.
struct KanjiTraceView: View {
    let entry: KanjiEntry
    /// Shows the given stroke (1-based) in Watch; the VoiceOver way through a stroke.
    let showStroke: (Int) -> Void

    private let strokes: [KanjiStroke]
    @State private var session: KanjiTraceSession
    @State private var points: [SVGPoint] = []
    @State private var miss: [SVGPoint]?
    @State private var showsGuide = true

    @Environment(\.palette) private var palette

    init(entry: KanjiEntry, showStroke: @escaping (Int) -> Void) {
        self.entry = entry
        self.showStroke = showStroke
        strokes = entry.parsedStrokes
        _session = State(initialValue: KanjiTraceSession(strokeCount: entry.strokes.count))
    }

    private var character: String { String(entry.character) }
    private var due: KanjiStroke? { strokes.indices.contains(session.step) ? strokes[session.step] : nil }
    private var stepNumber: Int { min(session.step + 1, strokes.count) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                message
                square
                marks
                actions
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .scrollDisabled(!points.isEmpty)
    }

    // MARK: Message

    private var message: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.isFinished ? "Well done" : KanjiDisplay.strokePosition(stepNumber, of: strokes.count))
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.ink)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(isMiss ? palette.mark : palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var isMiss: Bool {
        miss != nil && (session.lastVerdict == .reversed || session.lastVerdict == .wrongPlace)
    }

    private var subtitle: String {
        if session.isFinished { return KanjiDisplay.finished(strokes.count) }
        guard let due else { return "" }
        if isMiss {
            return session.lastVerdict == .reversed ? KanjiDisplay.reversed(due.direction) : KanjiDisplay.wrongPlace(stepNumber)
        }
        return KanjiDisplay.traceHint(due.direction)
    }

    // MARK: Square

    private var square: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let scale = side / KanjiStroke.boxSize
            ZStack(alignment: .topLeading) {
                // Centre guides, and the faint whole kanji while the guide is on.
                KanjiStrokeCanvas(strokes: strokes, shown: 0, showsNumbers: false, showsStartDot: false,
                                  showsFutureStrokes: showsGuide, lineWidth: 5)
                // Accepted strokes, in ink.
                KanjiStrokeCanvas(strokes: strokes, shown: session.step, highlightsCurrent: false, showsGuides: false,
                                  showsNumbers: false, showsStartDot: false, showsFutureStrokes: false)
                if let miss, isMiss, let due {
                    KanjiStrokeShape(stroke: due)
                        .stroke(palette.mark.opacity(0.6), style: StrokeStyle(lineWidth: 1.6 * scale, lineCap: .round, lineJoin: .round))
                    path(miss, scale: scale)
                        .stroke(palette.mark, style: StrokeStyle(lineWidth: 3 * scale, lineCap: .round, lineJoin: .round,
                                                                 dash: [3 * scale, 2 * scale]))
                }
                if !points.isEmpty {
                    path(points, scale: scale)
                        .stroke(palette.ink, style: StrokeStyle(lineWidth: 4 * scale, lineCap: .round, lineJoin: .round))
                } else if let due {
                    Circle()
                        .fill(palette.mark)
                        .frame(width: 6 * scale, height: 6 * scale)
                        .position(x: due.start.x * scale, y: due.start.y * scale)
                    Text("\(stepNumber)")
                        .font(.system(size: 7 * scale, weight: .semibold))
                        .foregroundStyle(palette.mark)
                        .position(x: (due.start.x + 5) * scale, y: (due.start.y - 4) * scale)
                }
                if session.isFinished {
                    Circle()
                        .stroke(palette.mark.opacity(0.85), lineWidth: 2.2 * scale)
                        .frame(width: 92 * scale, height: 92 * scale)
                        .position(x: side / 2, y: side / 2)
                }
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .gesture(drawing(scale: scale))
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 350)
        .padding(6)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.rule, lineWidth: 1))
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel(session.isFinished
            ? "Tracing square for \(character). All strokes drawn."
            : "Tracing square for \(character). Draw stroke \(stepNumber) with your finger.")
        .accessibilityAction(named: "Show this stroke") { showStroke(stepNumber) }
    }

    private func path(_ points: [SVGPoint], scale: CGFloat) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: CGPoint(x: first.x * scale, y: first.y * scale))
            for point in points.dropFirst() {
                path.addLine(to: CGPoint(x: point.x * scale, y: point.y * scale))
            }
        }
    }

    private func drawing(scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard !session.isFinished, scale > 0 else { return }
                points.append(SVGPoint(x: value.location.x / scale, y: value.location.y / scale))
            }
            .onEnded { _ in
                defer { points = [] }
                guard let due, !session.isFinished else { return }
                let verdict = StrokeMatcher.judge(points, against: due)
                session.submit(verdict)
                switch verdict {
                case .accepted: miss = nil
                case .reversed, .wrongPlace: miss = points
                case .tooShort: break
                }
            }
    }

    // MARK: Marks and actions

    private var marks: some View {
        WrappingFlowLayout(spacing: 5) {
            ForEach(strokes.indices, id: \.self) { index in
                let done = index < session.step
                let current = index == session.step && !session.isFinished
                Text("\(index + 1)")
                    .font(.caption)
                    .foregroundStyle(done ? palette.ink : palette.muted)
                    .frame(width: 30, height: 30)
                    .background(palette.card, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(current ? palette.ink : palette.rule, lineWidth: 1))
                    .overlay {
                        if done { Circle().stroke(palette.mark, lineWidth: 1.6).padding(5) }
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(session.step) of \(strokes.count) strokes drawn")
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { guideButton; restartButton }
            VStack(spacing: 10) { guideButton; restartButton }
        }
    }

    private var guideButton: some View {
        Button(showsGuide ? "Hide guide" : "Show guide") { showsGuide.toggle() }
            .buttonStyle(.paperSecondary)
    }

    private var restartButton: some View {
        Button("Start again") {
            session.reset()
            miss = nil
            points = []
        }
        .buttonStyle(.paper)
    }
}
