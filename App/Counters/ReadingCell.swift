import SwiftUI
import VerbKit

/// One counted form: 三本 small above, the preferred reading, and any other accepted readings
/// below. A number whose preferred reading is in the counter's `changed` list gets a tint over the
/// whole reading and a corner dot, so the change never relies on colour alone.
///
/// Readings come straight from counters.json; nothing here asks the furigana dictionary, which
/// would read 三本 as さん + ほん.
struct ReadingCell: View {
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
            Text(counter.written(number))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(preferred)
                .font(style == .large ? .title3.weight(.semibold) : .body.weight(.semibold))
            if readings.count > 1 {
                Text(readings.dropFirst().joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 4)
        .background(changed ? Color.orange.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .topTrailing) {
            if changed {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(.orange)
                    .padding(6)
                    .accessibilityHidden(true)
            }
        }
        .overlay {
            if highlighted {
                RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: 2)
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
