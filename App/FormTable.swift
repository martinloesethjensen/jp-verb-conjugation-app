import SwiftUI
import VerbKit

/// One row of a `FormTable`: a caption and a value per column. A `nil` value
/// leaves its cell empty (for example the て-form has no polite value).
struct FormTableRow: Identifiable {
    let label: String
    let values: [String?]
    var id: String { label }
}

/// The table every group of forms is drawn with: bold column headers, then a row
/// per form with a caption on the left, the values on the right and hairline
/// separators, on a quiet system-secondary card.
struct FormTable: View {
    let columns: [String]
    let rows: [FormTableRow]
    /// The verb's kana dictionary form, which the cells compare each form with.
    let dict: String

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("")
                ForEach(columns, id: \.self) { column in
                    Text(column)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(rows) { row in
                Divider()
                GridRow {
                    Text(row.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(Array(row.values.enumerated()), id: \.offset) { _, value in
                        if let value {
                            FormCell(form: value, dict: dict)
                                .font(.body)
                        } else {
                            Text("")
                        }
                    }
                }
            }
        }
        .formCard()
    }
}

extension View {
    /// The quiet card surface for groups of forms: the system's secondary
    /// background, which adapts to light and dark on iOS and macOS.
    func formCard() -> some View {
        self
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }
}
