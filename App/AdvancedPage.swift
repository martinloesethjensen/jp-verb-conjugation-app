import SwiftUI
import VerbKit

/// The optional advanced forms (volitional, passive, causative, conditionals,
/// imperative, たい). No verb in the data has them yet, so the row that opens
/// this page stays hidden until one does.
struct AdvancedPage: View {
    let verb: Verb

    private var rows: [FormTableRow] {
        let f = verb.forms
        let all: [(String, String?)] = [
            ("Volitional", f.volitional),
            ("Passive", f.passive),
            ("Causative", f.causative),
            ("Causative-passive", f.causativePassive),
            ("Conditional (ば)", f.conditionalBa),
            ("Conditional (たら)", f.conditionalTara),
            ("Imperative", f.imperative),
            ("たい (want to)", f.tai),
        ]
        return all.compactMap { label, value in
            value.map { FormTableRow(label: label, values: [$0]) }
        }
    }

    var body: some View {
        ScrollView {
            FormTable(columns: ["Form"], rows: rows, dict: verb.dict)
                .padding()
        }
        .navigationTitle(VerbSubPage.advanced.title)
    }
}

extension VerbForms {
    /// True when at least one advanced form is populated.
    var hasAdvancedForms: Bool {
        [volitional, passive, causative, causativePassive, conditionalBa, conditionalTara, imperative, tai]
            .contains { $0 != nil }
    }
}
