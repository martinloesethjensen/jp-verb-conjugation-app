import SwiftUI
import VerbKit

struct ExamplesView: View {
    let verb: Verb
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(verb.examples, id: \.self) { example in
                VStack(alignment: .leading, spacing: 4) {
                    Text(formLabel(example.form))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    JapaneseText(example.jp)
                        .font(.title3)
                    Text(example.en)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("\(verb.dict) — Examples")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func formLabel(_ key: FormKey) -> String {
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
