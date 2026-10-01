import SwiftUI
import VerbKit

/// The verb's auxiliary forms: ている in full, then a row per other auxiliary,
/// and the four lesson links. A verb with no て-form auxiliaries (ある) shows only
/// the stem-based rows.
struct AuxiliariesPage: View {
    let verb: Verb

    private var teiruRows: [FormTableRow] {
        let f = verb.forms
        guard f.teiru != nil else { return [] }
        return [
            FormTableRow(label: "present +", values: [f.teiru, f.teiruMasuPos]),
            FormTableRow(label: "present −", values: [f.teiruNeg, f.teiruMasuNeg]),
            FormTableRow(label: "past +", values: [f.teiruPast, f.teiruMasuPast]),
            FormTableRow(label: "past −", values: [f.teiruPastNeg, f.teiruMasuPastNeg]),
            FormTableRow(label: "て-form", values: [f.teiruTe, nil]),
        ]
    }

    /// One row per auxiliary the verb has, in teaching order.
    private var otherRows: [FormTableRow] {
        let f = verb.forms
        let all: [(String, String?, String?)] = [
            ("てしまう", f.teshimau, f.teshimauPolite),
            ("ておく", f.teoku, f.teokuPolite),
            ("てみる", f.temiru, f.temiruPolite),
            ("ながら", f.nagara, nil),
            ("すぎる", f.sugiru, f.sugiruPolite),
            ("やすい", f.yasui, f.yasuiPolite),
            ("にくい", f.nikui, f.nikuiPolite),
        ]
        return all.compactMap { label, plain, polite in
            plain.map { FormTableRow(label: label, values: [$0, polite]) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !teiruRows.isEmpty {
                    Text("ている")
                        .font(.headline)
                    FormTable(columns: ["Plain", "Polite"], rows: teiruRows, dict: verb.dict)
                }
                Text("Others")
                    .font(.headline)
                FormTable(columns: ["Plain", "Polite"], rows: otherRows, dict: verb.dict)
                LessonLinks(ids: ["teiru", "teshimau", "temiru", "sugiru"])
            }
            .padding()
        }
        .navigationTitle(VerbSubPage.auxiliaries.title)
    }
}
