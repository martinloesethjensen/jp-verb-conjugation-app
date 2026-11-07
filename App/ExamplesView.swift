import SwiftUI
import VerbKit

/// Every example of a verb, on one ruled paper card, in a sheet.
struct ExamplesView: View {
    let verb: Verb
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VerbExampleCard(examples: verb.examples, verb: verb)
                    .padding()
            }
            .paperBackground()
            .navigationTitle("\(verb.dict) — Examples")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
