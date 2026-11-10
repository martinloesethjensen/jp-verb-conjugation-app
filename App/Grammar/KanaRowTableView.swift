import SwiftUI
import VerbKit

/// A rule's kana-row table (`KanaRowTable`): one line per example verb, its ending in the five
/// rows あ to お with the rule's row tinted, then the built form with the moved ending underlined.
/// Too wide for the space (large Dynamic Type), it scrolls sideways.
struct KanaRowTableView: View {
    @Environment(\.palette) private var palette
    let table: KanaRowTable

    private static let headers: [KanaRow: String] = ["あ", "い", "う", "え", "お"]
        .enumerated().reduce(into: [:]) { $0[KanaRow.allCases[$1.offset]] = $1.element }

    /// What each row feeds, for the legend under the table.
    private static func use(_ row: KanaRow) -> String {
        switch row {
        case .a: "あ before ない (う → わ)"
        case .i: "い before ます"
        case .u: "う the dictionary form"
        case .e: "え the potential and ば"
        case .o: "お the volitional"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                grid
                ScrollView(.horizontal) { grid }
            }
            JapaneseText(KanaRow.allCases.map(Self.use).joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(palette.muted)
        }
    }

    private var grid: some View {
        Grid(alignment: .center, horizontalSpacing: 4, verticalSpacing: 4) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                ForEach(KanaRow.allCases, id: \.self) { row in
                    Text(Self.headers[row] ?? "")
                        .font(.caption.weight(row == table.target ? .bold : .regular))
                        .foregroundStyle(row == table.target ? palette.ink : palette.muted)
                }
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
            .accessibilityHidden(true)
            ForEach(table.rows, id: \.self) { row in
                GridRow {
                    JapaneseText(row.base)
                        .gridColumnAlignment(.leading)
                        .padding(.trailing, 6)
                    ForEach(Array(zip(KanaRow.allCases, row.kana)), id: \.0) { kanaRow, kana in
                        cell(kana, isTarget: kanaRow == table.target, isDictionary: kanaRow == .u)
                    }
                    JapaneseText(row.built, emphasizing: max(0, row.base.count - 1)..<row.built.count)
                        .font(.sentence(.body))
                        .gridColumnAlignment(.leading)
                        .padding(.leading, 6)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(row))
            }
        }
    }

    private func cell(_ kana: Character, isTarget: Bool, isDictionary: Bool) -> some View {
        Text(String(kana))
            .font(.sentence(.title3).weight(isTarget ? .bold : .regular))
            .foregroundStyle(isTarget || isDictionary ? palette.ink : palette.muted)
            .frame(minWidth: 32, minHeight: 32)
            .background(isTarget ? palette.button.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6))
    }

    private func accessibilityLabel(_ row: KanaRowTable.Row) -> String {
        let moved = KanaRow.allCases.firstIndex(of: table.target).map { String(row.kana[$0]) } ?? ""
        return "\(row.base): \(row.ending) becomes \(moved), \(row.built)"
    }
}
