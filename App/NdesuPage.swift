import SwiftUI
import VerbKit

/// The verb's んです forms, polite and casual, and the link to the lesson.
struct NdesuPage: View {
    let verb: Verb

    private var rows: [FormTableRow] {
        let f = verb.forms
        return [
            FormTableRow(label: "present +", values: [f.ndPos, f.ndCasualPos]),
            FormTableRow(label: "present −", values: [f.ndNeg, f.ndCasualNeg]),
            FormTableRow(label: "past +", values: [f.ndPast, f.ndCasualPast]),
            FormTableRow(label: "past −", values: [f.ndPastNeg, f.ndCasualPastNeg]),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FormTable(columns: ["Polite", "Casual"], rows: rows, dict: verb.dict)
                LessonLinks(ids: [GrammarPoint.nDesuID])
            }
            .padding()
        }
        .navigationTitle(VerbSubPage.nDesu.title)
    }
}
