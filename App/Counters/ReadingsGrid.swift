import SwiftUI
import VerbKit

/// All eleven numbers of a counter as large cells, with the changed ones marked. `focus` is
/// ringed (it is where a Forms search result lands).
struct ReadingsGrid: View {
    let counter: Counter
    var focus: CounterNumber?
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: sizeClass == .regular ? 4 : 2)
    }

    /// "Marked numbers change sound: 1, 3, 6, 8, 10 and 何", built from the counter's data.
    private var footer: String {
        if counter.sound == "irregular" { return "Irregular: learn each reading" }
        let changed = CounterNumber.allCases.filter(counter.isChanged).map { $0 == .what ? "何" : $0.key }
        guard let last = changed.last else { return "No sound changes" }
        let list = changed.count == 1 ? last : changed.dropLast().joined(separator: ", ") + " and " + last
        return "Marked numbers change sound: \(list)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(CounterNumber.allCases) { number in
                    ReadingCell(counter: counter, number: number, style: .large, highlighted: number == focus)
                        .frame(minHeight: 76)
                        .id(number)
                }
            }
            Text(footer)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
