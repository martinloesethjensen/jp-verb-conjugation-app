import SwiftUI
import VerbKit

/// The counter page's reading for the selected number: 三本 small above, the preferred reading large,
/// other accepted readings below. A number whose sound changes gets the tint and corner dot used in every
/// table, so the change never relies on colour alone. Tapping speaks the reading.
struct ReadingBlock: View {
    let counter: Counter
    let number: CounterNumber
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var readings: [String] { counter.readings(for: number) }
    private var preferred: String { readings.first ?? "" }
    private var changed: Bool { counter.isChanged(number) }

    var body: some View {
        VStack(spacing: 4) {
            Text(counter.written(number))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(preferred)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(reduceMotion ? .identity : .numericText())
            if readings.count > 1 {
                Text(readings.dropFirst().joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(changed ? Color.orange.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            if changed {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.orange)
                    .padding(8)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .speakOnTap(preferred)
        .textActions(preferred)
        .animation(reduceMotion ? nil : .snappy, value: number)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(counter.written(number)), \(preferred)\(changed ? ", sound changes" : "")")
        .accessibilityHint("Speaks the reading")
        .accessibilityAddTraits(.isButton)
    }
}
