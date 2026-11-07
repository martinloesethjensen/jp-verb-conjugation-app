import SwiftUI
import VerbKit

/// The extended groups as rows that push their own page, each previewing the
/// first form that exists. A row is left out when the verb has none of the group's forms.
struct MoreRowsCard: View {
    let verb: Verb
    @Environment(VerbStore.self) private var verbStore
    @Environment(\.palette) private var palette

    struct Row: Identifiable {
        let page: VerbSubPage
        let preview: String
        var id: VerbSubPage { page }
    }

    private static func firstForm(_ forms: [String?]) -> String? {
        forms.compactMap { $0 }.first
    }

    private var rows: [Row] {
        Self.rows(for: verb, lessonCount: verbStore.grammarPoints.attachingToVerbs.count)
    }

    /// The rows in their fixed order (Potential, んです, Auxiliaries, Advanced, then lessons),
    /// leaving out a group the verb has no form of. The verb page also asks, to head the card.
    static func rows(for verb: Verb, lessonCount: Int) -> [Row] {
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
                                   f.causativePassiveShort, f.conditionalBa, f.conditionalTara,
                                   f.imperative, f.tai, f.masuVolitional, f.negTe, f.nakute,
                                   f.teMoIi, f.teWaIkenai, f.teChaDame, f.nakerebaNaranai,
                                   f.nakuteWaIkenai, f.nakya, f.nakucha, f.nakuteMoIi,
                                   f.negImperative, f.nasai, f.conditionalTo, f.conditionalNara])),
        ]
        for (page, preview) in groups {
            if let preview { rows.append(Row(page: page, preview: preview)) }
        }
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
                    if index > 0 { Divider().overlay(palette.rule) }
                    NavigationLink(value: row.page) {
                        HStack {
                            // Title and preview side by side while they fit; the preview moves
                            // under the title at large text sizes instead of breaking words.
                            ViewThatFits(in: .horizontal) {
                                HStack {
                                    Text(row.page.title).foregroundStyle(palette.ink).fixedSize()
                                    Spacer()
                                    Text(row.preview).foregroundStyle(palette.muted).fixedSize()
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.page.title).foregroundStyle(palette.ink)
                                    Text(row.preview).foregroundStyle(palette.muted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            RowChevron()
                        }
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .formCard()
        }
    }
}
