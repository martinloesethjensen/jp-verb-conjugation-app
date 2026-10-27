import SwiftUI
import VerbKit

/// − 10, − 1, the number, + 1, + 10 for the numbers above 10 that the counter has readings for. It
/// steps only to numbers in the data, so it cannot ask for 150円; the strip above keeps 1 to 10. Hidden for a
/// counter with nothing above 10.
struct NumberStepper: View {
    let counter: Counter
    @Binding var selection: CounterNumber

    private struct Step: Identifiable {
        let title: String
        let label: String
        let delta: Int
        var id: Int { delta }
    }

    private static let down = [Step(title: "−10", label: "Back ten", delta: -10), Step(title: "−1", label: "Back one", delta: -1)]
    private static let up = [Step(title: "+1", label: "Forward one", delta: 1), Step(title: "+10", label: "Forward ten", delta: 10)]

    var body: some View {
        if !counter.extendedNumbers.isEmpty {
            HStack(spacing: 6) {
                ForEach(Self.down) { button($0) }
                Text(selection.isExtended ? selection.key : "11")
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(selection.isExtended ? .primary : .tertiary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(selection.isExtended ? "Number \(selection.key)" : "Numbers above ten")
                ForEach(Self.up) { button($0) }
            }
        }
    }

    private func button(_ step: Step) -> some View {
        let target = counter.step(selection, by: step.delta)
        return Button {
            if let target { selection = target }
        } label: {
            Text(step.title)
                .font(.callout.weight(.semibold).monospacedDigit())
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.glass)
        .disabled(target == nil)
        .accessibilityLabel(step.label)
    }
}
