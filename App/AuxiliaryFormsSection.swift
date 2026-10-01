import SwiftUI
import VerbKit

/// The verb's auxiliary forms: ている in full, the other て-form auxiliaries and
/// the ます-stem ones as plain and polite pairs, and links to the four lessons.
/// Shown on verb detail only when the verb has auxiliary forms; a verb such as
/// ある, which takes no て-form auxiliary, shows only the stem rows.
struct AuxiliaryFormsSection: View {
    let forms: VerbForms
    @Environment(VerbStore.self) private var verbStore
    @Environment(\.openRoute) private var openRoute
    @State private var isExpanded = false

    /// The lessons this section links to, in the order they are taught.
    private let lessonIDs = ["teiru", "teshimau", "temiru", "sugiru"]

    /// (label, value) for the nine ている forms this verb has, in display order.
    /// The labels are the ones the other form sections already use.
    private var teiruTiles: [(String, String)] {
        let all: [(FormKey, String?)] = [
            (.shortPos, forms.teiru),
            (.shortNeg, forms.teiruNeg),
            (.shortPast, forms.teiruPast),
            (.shortPastNeg, forms.teiruPastNeg),
            (.masuPos, forms.teiruMasuPos),
            (.masuNeg, forms.teiruMasuNeg),
            (.masuPast, forms.teiruMasuPast),
            (.masuPastNeg, forms.teiruMasuPastNeg),
            (.te, forms.teiruTe),
        ]
        return all.compactMap { key, value in
            guard let value, let label = formLabels[key] else { return nil }
            return (label, value)
        }
    }

    private struct Row: Identifiable {
        let label: String
        let plain: String
        let polite: String?
        var id: String { label }
    }

    /// The pair rows that exist for this verb, in display order.
    private var rows: [Row] {
        let all: [(String, String?, String?)] = [
            ("てしまう", forms.teshimau, forms.teshimauPolite),
            ("ておく", forms.teoku, forms.teokuPolite),
            ("てみる", forms.temiru, forms.temiruPolite),
            ("ながら", forms.nagara, nil),
            ("すぎる", forms.sugiru, forms.sugiruPolite),
            ("やすい", forms.yasui, forms.yasuiPolite),
            ("にくい", forms.nikui, forms.nikuiPolite),
        ]
        return all.compactMap { label, plain, polite in
            plain.map { Row(label: label, plain: $0, polite: polite) }
        }
    }

    /// Lessons that have synced, so a link never dead-ends.
    private var lessons: [GrammarPoint] {
        lessonIDs.compactMap { id in
            Route.grammar(id).resolve(verbs: [], grammarPoints: verbStore.grammarPoints).flatMap {
                if case let .grammar(point) = $0 { return point }
                return nil
            }
        }
    }

    var body: some View {
        DisclosureGroup("Auxiliaries", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                if !teiruTiles.isEmpty {
                    Text("ている")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(teiruTiles, id: \.0) { label, value in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(value)
                                    .font(.headline)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .glassEffect(in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Text("")
                        Text("Plain").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                        Text("Polite").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    }
                    ForEach(rows) { row in
                        GridRow {
                            Text(row.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(row.plain)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(row.polite ?? "—")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(in: RoundedRectangle(cornerRadius: 8))

                ForEach(lessons) { lesson in
                    Button {
                        openRoute(.grammar(lesson.id))
                    } label: {
                        Label {
                            JapaneseText("Learn about \(lesson.title)")
                        } icon: {
                            Image(systemName: "arrow.right.circle")
                        }
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
