import SwiftUI
import VerbKit

/// One counted form: 三本 small above (large style only; in a table the row and column say it), the
/// preferred reading, and any other accepted readings below. A number whose preferred reading is in the counter's `changed` list is bold and underlined in
/// ink (`soundChangeMark`), so the change never relies on colour.
///
/// Readings come straight from counters.json; nothing here asks the furigana dictionary, which
/// would read 三本 as さん + ほん.
struct ReadingCell: View {
    @Environment(\.palette) private var palette
    enum Style {
        case compact, large
    }

    let counter: Counter
    let number: CounterNumber
    var style: Style = .compact
    var highlighted = false

    private var readings: [String] { counter.readings(for: number) }
    private var preferred: String { readings.first ?? "" }
    private var changed: Bool { counter.isChanged(number) }

    var body: some View {
        VStack(spacing: 2) {
            if style == .large {
                Text(counter.written(number))
                    .font(.caption)
                    .foregroundStyle(palette.muted)
            }
            Text(preferred)
                .font(style == .large ? .title3 : .body)
                .foregroundStyle(palette.ink)
                .soundChangeMark(changed)
            if readings.count > 1 {
                Text(readings.dropFirst().joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(palette.muted)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 4)
        .overlay {
            if highlighted {
                RoundedRectangle(cornerRadius: 10).strokeBorder(palette.button, lineWidth: 2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .speakOnTap(preferred)
        .textActions(preferred)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(counter.written(number)), \(preferred)\(changed ? ", sound changes" : "")")
        .accessibilityAddTraits(.isButton)
    }
}
