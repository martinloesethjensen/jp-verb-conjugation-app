import SwiftUI
import VerbKit

/// The verb's nine potential forms, plain and polite, and the link to the lesson.
struct PotentialPage: View {
    let verb: Verb

    private var rows: [FormTableRow] {
        let f = verb.forms
        return [
            FormTableRow(label: "present +", values: [f.potential, f.potMasuPos]),
            FormTableRow(label: "present −", values: [f.potShortNeg, f.potMasuNeg]),
            FormTableRow(label: "past +", values: [f.potShortPast, f.potMasuPast]),
            FormTableRow(label: "past −", values: [f.potShortPastNeg, f.potMasuPastNeg]),
            FormTableRow(label: "て-form", values: [f.potTe, nil]),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FormTable(columns: ["Plain", "Polite"], rows: rows, dict: verb.dict)
                LessonLinks(ids: [GrammarPoint.potentialID])
            }
            .padding()
        }
        .navigationTitle(VerbSubPage.potential.title)
    }
}
