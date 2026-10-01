import SwiftUI
import VerbKit

/// The extended groups as rows that push their own page, each previewing one
/// form. A row is left out when the verb has none of that group's forms.
struct MoreRowsCard: View {
    let verb: Verb

    private struct Row: Identifiable {
        let page: VerbSubPage
        let preview: String
        var id: VerbSubPage { page }
    }

    private var rows: [Row] {
        let f = verb.forms
        var rows: [Row] = []
        if f.hasPotentialForms, let preview = f.potential {
            rows.append(Row(page: .potential, preview: preview))
        }
        if f.hasNdForms, let preview = f.ndPos {
            rows.append(Row(page: .nDesu, preview: preview))
        }
        return rows
    }

    var body: some View {
        if !rows.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider() }
                    NavigationLink(value: row.page) {
                        HStack {
                            Text(row.page.title)
                            Spacer()
                            Text(row.preview).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .formCard()
        }
    }
}
