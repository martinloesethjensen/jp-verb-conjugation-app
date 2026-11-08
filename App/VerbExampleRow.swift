import SwiftUI
import VerbKit

/// One example sentence of a verb on genkō paper: the form it shows as a small tag, the sentence
/// in Mincho with that form bold and underlined, the English under it, and a speak button.
/// Used on the verb page, in the examples sheet and on the Potential page.
struct VerbExampleRow: View {
    let example: VerbExample
    let verb: Verb
    @Environment(\.palette) private var palette
    @Environment(FormCatalogueStore.self) private var formCatalogueStore
    @AppStorage(showReviewStatusKey, store: .appGroup) private var showReviewStatus = true

    private var emphasis: Range<Int>? {
        verb.forms[id: example.form].flatMap { FormHighlight.range(of: $0, for: verb, in: example.jp) }
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(Self.formLabel(example.form, catalogue: formCatalogueStore.catalogue))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(palette.muted)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .overlay(Capsule().strokeBorder(palette.rule, lineWidth: 1))
                    if showReviewStatus, let review = example.review {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(palette.good)
                            .accessibilityLabel("Reviewed by \(review.by.displayName) on \(review.on)")
                    }
                }
                JapaneseText(example.jp, emphasizing: emphasis)
                    .font(.sentence(.title3))
                    .foregroundStyle(palette.ink)
                Text(example.en)
                    .font(.subheadline)
                    .foregroundStyle(palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .textActions(example.jp, translate: true)
            SpeakButton(text: example.jp)
        }
        .padding(.vertical, 4)
    }

    /// The nine basic forms keep their short labels; any other form uses the catalogue's.
    static func formLabel(_ id: FormID, catalogue: FormCatalogue) -> String {
        guard let key = FormKey(rawValue: id.rawValue) else {
            return catalogue.label(for: id)
        }
        switch key {
        case .masuPos: return "ます (polite +)"
        case .masuNeg: return "ません (polite −)"
        case .masuPast: return "ました (polite past +)"
        case .masuPastNeg: return "ませんでした (polite past −)"
        case .te: return "て-form"
        case .shortPos: return "short (present +)"
        case .shortNeg: return "short (present −)"
        case .shortPast: return "short (past +)"
        case .shortPastNeg: return "short (past −)"
        }
    }
}

/// Example rows divided by rule lines on one ruled paper card.
struct VerbExampleCard: View {
    let examples: [VerbExample]
    let verb: Verb
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(examples.enumerated()), id: \.offset) { index, example in
                if index > 0 { Divider().overlay(palette.rule) }
                VerbExampleRow(example: example, verb: verb)
            }
        }
        .paperCard(cornerRadius: 14, ruled: true)
    }
}
