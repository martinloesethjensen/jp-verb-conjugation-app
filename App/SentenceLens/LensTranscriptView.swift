import SwiftUI
import VerbKit

/// The sentence with its verbs highlighted. It reflows like `JapaneseText`, with furigana
/// when the setting is on. Each verb is a button in its verb group's colour with an
/// underline that says what kind of form it is, so colour is never the only cue; a verb
/// the app doesn't have is grey with a dotted underline, and an ambiguous one has a "?".
///
/// VoiceOver reads each verb as its own element ("食べさせられなかった, verb 食べる,
/// ru-verb, …") and the "Verbs" rotor moves between them. The text between verbs is
/// hidden from it: the whole sentence is read once, by the caller's heading.
struct LensTranscriptView: View {
    let segments: [LensSegment]
    var showLabels = false
    let onTap: (FormLookup.Item) -> Void
    @Environment(\.furiganaEnabled) private var furiganaEnabled
    @Environment(\.furiganaDictionary) private var dictionary
    @Namespace private var rotorNamespace

    /// A verb is laid out unit by unit like the text around it, so a long one (or any verb
    /// at the largest text sizes) wraps instead of pushing the sentence off screen.
    private enum Piece {
        case text(TextUnit)
        case verb(FormLookup.Item, TextUnit, first: Bool, last: Bool)
    }

    private var units: FuriganaDictionary {
        furiganaEnabled ? dictionary ?? .empty : .empty
    }

    private var pieces: [Piece] {
        var pieces: [Piece] = []
        for segment in segments {
            switch segment {
            case .text(let text):
                for (index, var unit) in units.units(for: text).enumerated() {
                    // 。 straight after a verb stays on the verb's line.
                    if index == 0, let first = unit.text.first, Self.closing.contains(first) {
                        unit.glueToPrevious = true
                    }
                    pieces.append(.text(unit))
                }
            case .verb(let item):
                let verbUnits = units.units(for: item.surface)
                for (index, unit) in verbUnits.enumerated() {
                    pieces.append(.verb(item, unit, first: index == 0, last: index == verbUnits.count - 1))
                }
            }
        }
        return pieces
    }

    private static let closing: Set<Character> = ["。", "、", "，", "．", "！", "？", "」", "』", "）", "…", ",", ".", "!", "?"]

    private var items: [FormLookup.Item] {
        segments.compactMap { if case .verb(let item) = $0 { item } else { nil } }
    }

    var body: some View {
        let pieces = pieces
        RubyFlowLayout(glue: pieces.map(glue), alignment: .leading, maxLines: nil) {
            ForEach(pieces.indices, id: \.self) { index in
                switch pieces[index] {
                case .text(let unit):
                    RubyUnitView(unit: unit)
                        .padding(.vertical, LensHighlight.verticalPadding)
                        .accessibilityHidden(true)
                case .verb(let item, let unit, let first, let last):
                    let highlight = LensHighlight(item: item, unit: unit, first: first, last: last, showLabel: showLabels) {
                        onTap(item)
                    }
                    // The first unit stands for the whole verb to VoiceOver.
                    if first {
                        highlight.accessibilityRotorEntry(id: item.id, in: rotorNamespace)
                    } else {
                        highlight.accessibilityHidden(true)
                    }
                }
            }
        }
        .font(.title2)
        .accessibilityElement(children: .contain)
        .accessibilityRotor("Verbs") {
            ForEach(items) { item in
                AccessibilityRotorEntry(Text(item.surface), id: item.id, in: rotorNamespace)
            }
        }
    }

    private func glue(_ piece: Piece) -> Bool {
        if case .text(let unit) = piece { unit.glueToPrevious } else { false }
    }
}

/// One unit of a highlighted verb; the units side by side make one pill and one underline.
private struct LensHighlight: View {
    let item: FormLookup.Item
    let unit: TextUnit
    let first: Bool
    let last: Bool
    let showLabel: Bool
    let action: () -> Void

    /// Room under every unit for the underline, so verbs and text share a baseline.
    static let verticalPadding: CGFloat = 6

    private var verb: Verb? { item.readings.first?.verb }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                if first, showLabel, let verb {
                    Text(verb.type.groupMark)
                        .font(.caption2.weight(.bold))
                        .padding(.trailing, 2)
                }
                RubyUnitView(unit: unit)
            }
            .padding(.leading, first ? 3 : 0)
            .padding(.trailing, last ? 3 : 0)
            .background { pill }
            .overlay(alignment: .topTrailing) {
                if last, item.status == .ambiguous {
                    Text("?")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(.primary)
                        .padding(2)
                        .background(.background, in: Circle())
                        .offset(x: 6, y: -6)
                }
            }
            .padding(.vertical, Self.verticalPadding)
            .overlay(alignment: .bottom) {
                LensUnderline(highlight: item.highlight)
                    .frame(height: 5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(item.status == .notInApp ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.black.opacity(0.85)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityDescription)
        .accessibilityHint("Double-tap for forms")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var pill: some View {
        if item.status != .notInApp, let verb {
            let corner: CGFloat = 6
            UnevenRoundedRectangle(
                topLeadingRadius: first ? corner : 0, bottomLeadingRadius: first ? corner : 0,
                bottomTrailingRadius: last ? corner : 0, topTrailingRadius: last ? corner : 0
            )
            .fill(verb.type.accentColor.opacity(0.85))
        }
    }
}

/// The non-colour cue under a highlight: solid for a basic form, double for an auxiliary
/// chain, dashed for potential, passive and causative, dotted for a verb not in the app.
struct LensUnderline: View {
    let highlight: FormLookup.Highlight

    var body: some View {
        Canvas { context, size in
            func line(at y: CGFloat, dash: [CGFloat] = []) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1.5, lineCap: dash.isEmpty ? .butt : .round, dash: dash))
            }
            switch highlight {
            case .basic:
                line(at: size.height / 2)
            case .chain:
                line(at: 1)
                line(at: size.height - 1)
            case .voice:
                line(at: size.height / 2, dash: [6, 3])
            case .notInApp:
                line(at: size.height / 2, dash: [0.5, 3.5])
            }
        }
        .foregroundStyle(highlight == .notInApp ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        .accessibilityHidden(true)
    }
}

/// What each underline means, for the key under the transcript.
extension FormLookup.Highlight {
    var keyLabel: String {
        switch self {
        case .basic: "Plain or polite form"
        case .chain: "Built with an auxiliary (ている, てしまう…)"
        case .voice: "Potential, passive or causative"
        case .notInApp: "Not in the app yet"
        }
    }
}

extension VerbType {
    /// The group letter "Show labels" adds before a verb: る, う or ! for irregular.
    var groupMark: String {
        switch self {
        case .ru: "る"
        case .u: "う"
        case .irregular: "!"
        }
    }
}
