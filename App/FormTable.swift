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
/// separators in `rule`, on the paper card.
struct FormTable: View {
    let columns: [String]
    let rows: [FormTableRow]
    /// The verb's kana dictionary form, which the cells compare each form with.
    let dict: String
    @Environment(\.palette) private var palette

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text("")
                ForEach(columns, id: \.self) { column in
                    Text(column)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(palette.muted)
                }
            }
            ForEach(rows) { row in
                Divider().overlay(palette.rule)
                GridRow {
                    Text(row.label)
                        .font(.footnote)
                        .foregroundStyle(palette.muted)
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
    /// The card surface for groups of forms: the theme's `card`, outlined in `rule`.
    func formCard() -> some View {
        paperCard(cornerRadius: 14)
    }
}
