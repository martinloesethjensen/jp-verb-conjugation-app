import SwiftUI
import VerbKit

/// Watch: the strokes drawn in order with play/pause and step controls, a strip of frames, the
/// readings and meanings, and the verbs in the app that use the kanji.
struct KanjiWatchView: View {
    let entry: KanjiEntry
    @Binding var step: Int

    private let strokes: [KanjiStroke]
    @State private var isPlaying = false

    @Environment(VerbStore.self) private var verbStore: VerbStore?
    @Environment(\.openRoute) private var openRoute
    @Environment(\.palette) private var palette

    /// How long a stroke stays before the next one while playing.
    static let stepInterval: Duration = .milliseconds(700)

    init(entry: KanjiEntry, step: Binding<Int>) {
        self.entry = entry
        _step = step
        strokes = entry.parsedStrokes
    }

    private var count: Int { strokes.count }
    private var shown: Int { min(max(step, 1), count) }
    private var character: String { String(entry.character) }

    private var verbs: [Verb] {
        Array((verbStore?.verbs ?? []).filter { $0.kanji?.contains(entry.character) == true }.prefix(5))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                controls
                frames
                readings
                Text(KanjiDisplay.credit)
                    .font(.caption2)
                    .foregroundStyle(palette.muted)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .task(id: isPlaying) { await play() }
    }

    // MARK: Header

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                drawing.frame(width: 200, height: 200)
                summary
            }
            VStack(alignment: .leading, spacing: 12) {
                drawing.frame(maxWidth: 260)
                summary
            }
        }
    }

    private var drawing: some View {
        KanjiStrokeCanvas(strokes: strokes, shown: shown, animatesCurrent: true)
            .padding(4)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.rule, lineWidth: 1))
            .accessibilityElement()
            .accessibilityLabel("\(character), \(KanjiDisplay.strokePosition(shown, of: count).lowercased())")
            .accessibilityAdjustableAction { direction in
                stop()
                switch direction {
                case .increment: step = min(shown + 1, count)
                case .decrement: step = max(shown - 1, 1)
                @unknown default: break
                }
            }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(character)
                .font(.headword(.largeTitle, scale: 1.65))
                .foregroundStyle(palette.ink)
                .accessibilityHidden(true)
            if !entry.meanings.isEmpty {
                Text(entry.meanings.joined(separator: ", "))
                    .font(.headline)
                    .foregroundStyle(palette.ink)
            }
            Text(KanjiDisplay.strokeSummary(entry))
                .font(.footnote)
                .foregroundStyle(palette.muted)
        }
        .padding(.top, 4)
    }

    // MARK: Controls

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                buttons
                position
            }
            VStack(alignment: .leading, spacing: 8) {
                buttons
                position
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            circleButton("Previous stroke", systemImage: "chevron.left", filled: false) {
                stop()
                step = max(shown - 1, 1)
            }
            circleButton(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill", filled: true) {
                if isPlaying {
                    stop()
                } else {
                    if shown >= count { step = 1 }
                    isPlaying = true
                }
            }
            circleButton("Next stroke", systemImage: "chevron.right", filled: false) {
                stop()
                step = min(shown + 1, count)
            }
        }
    }

    private var position: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(KanjiDisplay.strokePosition(shown, of: count))
                .font(.headline)
                .foregroundStyle(palette.ink)
            Text("Red dot marks where it starts")
                .font(.footnote)
                .foregroundStyle(palette.muted)
        }
    }

    private func circleButton(_ label: String, systemImage: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // The circles are a fixed 48 pt, so the glyph does not grow with Dynamic Type.
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(filled ? palette.onButton : palette.ink)
                .frame(width: 48, height: 48)
                .background(filled ? palette.button : palette.card, in: Circle())
                .overlay(Circle().stroke(filled ? palette.button : palette.rule, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Frames

    private var frames: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44, maximum: 56), spacing: 6)], spacing: 6) {
            ForEach(1...count, id: \.self) { upTo in
                Button {
                    stop()
                    step = upTo
                } label: {
                    KanjiStrokeCanvas(strokes: strokes, shown: upTo, showsGuides: false, showsNumbers: false,
                                      showsStartDot: false, lineWidth: 6)
                        .frame(width: 36, height: 36)
                        .frame(width: 44, height: 44)
                        .background(palette.card, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(upTo == shown ? palette.ink : palette.rule, lineWidth: upTo == shown ? 2 : 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show stroke \(upTo)")
                .accessibilityAddTraits(upTo == shown ? .isSelected : [])
            }
        }
    }

    // MARK: Readings

    private var readings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
                if !entry.on.isEmpty {
                    readingRow("On", entry.on.joined(separator: "・"))
                }
                if !entry.kun.isEmpty {
                    readingRow("Kun", entry.kun.map(KanjiReading.display).joined(separator: "・"))
                }
            }
            if !verbs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if !entry.on.isEmpty || !entry.kun.isEmpty {
                        Divider().overlay(palette.rule)
                    }
                    Text("In Verb Table")
                        .font(.footnote)
                        .foregroundStyle(palette.muted)
                    ForEach(verbs) { verb in
                        Button {
                            openRoute(.verb(verb.id))
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                JapaneseText(verb.kanji ?? verb.dict)
                                    .font(.headword(.body))
                                    .foregroundStyle(palette.ink)
                                Text(verb.meaning)
                                    .font(.subheadline)
                                    .foregroundStyle(palette.muted)
                                Spacer(minLength: 0)
                                RowChevron()
                            }
                            .frame(minHeight: 36)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .paperCard(cornerRadius: 14)
    }

    private func readingRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .font(.footnote)
                .foregroundStyle(palette.muted)
            Text(value)
                .font(.body)
                .foregroundStyle(palette.ink)
                .environment(\.locale, Locale(identifier: "ja"))
        }
    }

    // MARK: Playback

    private func stop() {
        isPlaying = false
    }

    /// Steps through the strokes while playing; cancelled when playback stops or the sheet closes.
    private func play() async {
        guard isPlaying else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.stepInterval)
            guard !Task.isCancelled, isPlaying else { return }
            if shown >= count {
                isPlaying = false
                return
            }
            step = shown + 1
        }
    }
}
