import SwiftUI
import VerbKit

/// The counter page's reading for the selected number: 三本 small above, the preferred reading large,
/// other accepted readings below. A reading whose sound changes is bold and underlined in ink, as in every
/// table. Tapping speaks the reading.
struct ReadingBlock: View {
    let counter: Counter
    let number: CounterNumber
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var readings: [String] { counter.readings(for: number) }
    private var preferred: String { readings.first ?? "" }
    private var changed: Bool { counter.isChanged(number) }

    var body: some View {
        VStack(spacing: 4) {
            Text(counter.written(number))
                .font(.subheadline)
                .foregroundStyle(palette.muted)
            if number.isExtended { UnreviewedLabel() }
            Text(preferred)
                .font(.headword(.largeTitle, scale: 1.3))
                .foregroundStyle(palette.ink)
                .soundChangeMark(changed)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(reduceMotion ? .identity : .numericText())
            if readings.count > 1 {
                Text(readings.dropFirst().joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(palette.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .paperCard(cornerRadius: 12)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .speakOnTap(preferred)
        .textActions(preferred)
        .animation(reduceMotion ? nil : .snappy, value: number)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(counter.written(number)), \(preferred)\(changed ? ", sound changes" : "")\(number.isExtended ? ", unreviewed" : "")")
        .accessibilityHint("Speaks the reading")
        .accessibilityAddTraits(.isButton)
    }
}
