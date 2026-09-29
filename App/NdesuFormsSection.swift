import SwiftUI
import VerbKit

/// The verb's んです forms — polite and casual side by side — plus a link
/// to the lesson. Shown on verb detail only when the verb has `nd_*` data.
struct NdesuFormsSection: View {
    let forms: VerbForms
    @Environment(VerbStore.self) private var verbStore
    @Environment(\.openRoute) private var openRoute
    @State private var isExpanded = false

    private struct Row {
        let label: String
        let polite: String?
        let casual: String?
    }

    private var rows: [Row] {
        [
            Row(label: "Present +", polite: forms.ndPos, casual: forms.ndCasualPos),
            Row(label: "Present −", polite: forms.ndNeg, casual: forms.ndCasualNeg),
            Row(label: "Past +", polite: forms.ndPast, casual: forms.ndCasualPast),
            Row(label: "Past −", polite: forms.ndPastNeg, casual: forms.ndCasualPastNeg),
        ]
    }

    /// The link is hidden until the lesson has synced, so it never dead-ends.
    private var lessonIsAvailable: Bool {
        Route.grammar(GrammarPoint.nDesuID)
            .resolve(verbs: [], grammarPoints: verbStore.grammarPoints) != nil
    }

    var body: some View {
        DisclosureGroup("んです", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow {
                        Text("Polite").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                        Text("Casual").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    }
                    ForEach(rows, id: \.label) { row in
                        // Each tense gets a caption row spanning both
                        // columns, so the forms below can use half the
                        // width each without wrapping.
                        GridRow {
                            Text(row.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 6)
                                .gridCellColumns(2)
                        }
                        GridRow {
                            Text(row.polite ?? "—").font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                            Text(row.casual ?? "—").font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(in: RoundedRectangle(cornerRadius: 8))

                if lessonIsAvailable {
                    Button {
                        openRoute(.grammar(GrammarPoint.nDesuID))
                    } label: {
                        Label("Learn about んです", systemImage: "arrow.right.circle")
                    }
                    .buttonStyle(.glass)
                    .font(.subheadline)
                }
            }
            .padding(.top, 4)
        }
        .font(.subheadline.weight(.semibold))
    }
}
