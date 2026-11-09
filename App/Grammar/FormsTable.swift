import SwiftUI
import VerbKit

/// A lesson's forms: Polite beside Casual (`ConjugationTable.rows`), stacked at accessibility sizes.
struct FormsTable: View {
    let conjugations: [GrammarConjugation]

    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Forms")
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 14) {
                        column("Polite", ConjugationTable.rows(conjugations).compactMap(\.polite))
                        column("Casual", ConjugationTable.rows(conjugations).compactMap(\.casual))
                    }
                } else {
                    Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 10) {
                        GridRow {
                            head("Polite")
                            head("Casual")
                        }
                        ForEach(Array(ConjugationTable.rows(conjugations).enumerated()), id: \.offset) { _, row in
                            Divider().overlay(palette.rule)
                            GridRow {
                                cell(row.polite)
                                cell(row.casual)
                            }
                        }
                    }
                }
            }
            .paperCard(cornerRadius: 14)
        }
    }

    private func head(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func cell(_ conjugation: GrammarConjugation?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let conjugation {
                JapaneseText(conjugation.form).font(.headline).foregroundStyle(palette.ink)
                if let note = conjugation.note {
                    JapaneseText(note).font(.footnote).foregroundStyle(palette.muted)
                }
            } else {
                Text("—").foregroundStyle(palette.muted).accessibilityLabel("None")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func column(_ title: String, _ forms: [GrammarConjugation]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            head(title)
            ForEach(Array(forms.enumerated()), id: \.offset) { _, form in cell(form) }
        }
    }
}
