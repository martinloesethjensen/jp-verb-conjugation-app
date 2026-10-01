import SwiftUI
import VerbKit

/// The everyday forms in one Plain / Polite table: present and past, positive and
/// negative, and the て-form.
struct VerbFormsCard: View {
    let verb: Verb

    private var rows: [FormTableRow] {
        let f = verb.forms
        return [
            FormTableRow(label: "present +", values: [f.shortPos, f.masuPos]),
            FormTableRow(label: "present −", values: [f.shortNeg, f.masuNeg]),
            FormTableRow(label: "past +", values: [f.shortPast, f.masuPast]),
            FormTableRow(label: "past −", values: [f.shortPastNeg, f.masuPastNeg]),
            FormTableRow(label: "て-form", values: [f.te, nil]),
        ]
    }

    var body: some View {
        FormTable(columns: ["Plain", "Polite"], rows: rows, dict: verb.dict)
    }
}
