import SwiftUI
import VerbKit

/// The extended groups as rows that push their own page, each previewing the
/// first form that exists. A row is left out when the verb has none of the group's forms.
struct MoreRowsCard: View {
    let verb: Verb
    @Environment(VerbStore.self) private var verbStore

    private struct Row: Identifiable {
        let page: VerbSubPage
        let preview: String
        var id: VerbSubPage { page }
    }

    private func firstForm(_ forms: [String?]) -> String? {
        forms.compactMap { $0 }.first
    }

    private var rows: [Row] {
        let f = verb.forms
        var rows: [Row] = []
        let groups: [(VerbSubPage, String?)] = [
            (.potential, firstForm([f.potential, f.potMasuPos, f.potMasuNeg, f.potMasuPast,
                                    f.potMasuPastNeg, f.potTe, f.potShortNeg, f.potShortPast,
                                    f.potShortPastNeg])),
            (.nDesu, firstForm([f.ndPos, f.ndNeg, f.ndPast, f.ndPastNeg, f.ndCasualPos,
                                f.ndCasualNeg, f.ndCasualPast, f.ndCasualPastNeg])),
            (.auxiliaries, firstForm([f.teiru, f.teiruNeg, f.teiruPast, f.teiruPastNeg,
                                      f.teiruMasuPos, f.teiruMasuNeg, f.teiruMasuPast,
                                      f.teiruMasuPastNeg, f.teiruTe, f.teshimau, f.teshimauPolite,
                                      f.teoku, f.teokuPolite, f.temiru, f.temiruPolite,
                                      f.sugiru, f.sugiruPolite, f.yasui, f.yasuiPolite,
                                      f.nikui, f.nikuiPolite, f.nagara])),
            (.advanced, firstForm([f.volitional, f.passive, f.causative, f.causativePassive,
                                   f.conditionalBa, f.conditionalTara, f.imperative, f.tai])),
        ]
        for (page, preview) in groups {
            if let preview { rows.append(Row(page: page, preview: preview)) }
        }
        let lessonCount = verbStore.grammarPoints.attachingToVerbs.count
        if lessonCount > 0 {
            rows.append(Row(page: .lessons,
                            preview: lessonCount == 1 ? "1 lesson" : "\(lessonCount) lessons"))
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
