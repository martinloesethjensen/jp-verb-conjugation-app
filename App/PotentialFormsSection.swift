import SwiftUI
import VerbKit

/// The verb's nine potential forms — plain, then polite, then て-form — plus a
/// link to the lesson. Shown on verb detail only when the verb has potential
/// forms, so ある (which has none) shows nothing.
struct PotentialFormsSection: View {
    let forms: VerbForms
    @Environment(VerbStore.self) private var verbStore
    @Environment(\.openRoute) private var openRoute
    @State private var isExpanded = false

    /// (label, value) for every form this verb has, in display order. The
    /// labels are the ones the other form sections already use.
    private var tiles: [(String, String)] {
        let all: [(FormKey, String?)] = [
            (.shortPos, forms.potential),
            (.shortNeg, forms.potShortNeg),
            (.shortPast, forms.potShortPast),
            (.shortPastNeg, forms.potShortPastNeg),
            (.masuPos, forms.potMasuPos),
            (.masuNeg, forms.potMasuNeg),
            (.masuPast, forms.potMasuPast),
            (.masuPastNeg, forms.potMasuPastNeg),
            (.te, forms.potTe),
        ]
        return all.compactMap { key, value in
            guard let value, let label = formLabels[key] else { return nil }
            return (label, value)
        }
    }

    /// The link is hidden until the lesson has synced, so it never dead-ends.
    private var lessonIsAvailable: Bool {
        Route.grammar(GrammarPoint.potentialID)
            .resolve(verbs: [], grammarPoints: verbStore.grammarPoints) != nil
    }

    var body: some View {
        DisclosureGroup("Potential", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(tiles, id: \.0) { label, value in
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

                if lessonIsAvailable {
                    Button {
                        openRoute(.grammar(GrammarPoint.potentialID))
                    } label: {
                        Label("Learn about the potential form", systemImage: "arrow.right.circle")
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
