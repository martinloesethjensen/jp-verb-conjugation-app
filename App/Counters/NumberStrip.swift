import SwiftUI
import VerbKit

/// 1 to 10 and 何 in one row; tapping selects the number the reading block shows. Changed numbers are
/// tinted and dotted, so the strip itself shows the pattern. Irregular counters have no pattern (every
/// reading differs), so they get a grid of all eleven readings instead. At accessibility text sizes the
/// strip scrolls sideways.
struct NumberStrip: View {
    let counter: Counter
    @Binding var selection: CounterNumber
    @Environment(\.dynamicTypeSize) private var typeSize

    private var caption: String {
        if counter.sound == "irregular" { return "Irregular: learn each reading" }
        let changed = CounterNumber.allCases.filter(counter.isChanged).map { $0 == .what ? "何" : $0.key }
        guard let last = changed.last else { return "No sound changes" }
        let list = changed.count == 1 ? last : changed.dropLast().joined(separator: ", ") + " and " + last
        return "Orange numbers change sound: \(list)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if counter.sound == "irregular" {
                grid
            } else if typeSize.isAccessibilitySize {
                ScrollView(.horizontal, showsIndicators: false) { strip }
            } else {
                strip
            }
            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func label(_ number: CounterNumber) -> String { number == .what ? "何" : number.key }

    private var strip: some View {
        HStack(spacing: 2) {
            ForEach(CounterNumber.allCases) { number in
                let changed = counter.isChanged(number)
                Button {
                    selection = number
                } label: {
                    Text(label(number))
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .frame(minWidth: typeSize.isAccessibilitySize ? 56 : 0)
                        .background(changed ? Color.orange.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .topTrailing) {
                            if changed {
                                Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(.orange)
                                    .padding(3).accessibilityHidden(true)
                            }
                        }
                        .overlay {
                            if selection == number {
                                RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 2)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(label(number)), \(counter.readings(for: number).first ?? "")\(changed ? ", sound changes" : "")")
                .accessibilityAddTraits(selection == number ? .isSelected : [])
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 1 : 3), spacing: 8) {
            ForEach(CounterNumber.allCases) { number in
                ReadingCell(counter: counter, number: number, style: .large, highlighted: selection == number)
                    .frame(minHeight: 76)
                    .simultaneousGesture(TapGesture().onEnded { selection = number })
            }
        }
    }
}
