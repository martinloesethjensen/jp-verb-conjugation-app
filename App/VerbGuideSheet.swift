import SwiftUI
import VerbKit

/// What the list's colours mean, the three verb types and every て-form rule.
struct VerbGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Reading the list") {
                    Text("The pill shows a verb's type. The dot beside the name shows its て-form group, so verbs that make the same て-form share a colour. Ru-verbs and irregulars have no such group, so they have no dot.")
                }
                Section("Verb types") {
                    typeRow(.ru, "Ru-verb (一段)", "Ends in -eru or -iru. Drop る and add the ending. Exceptions: はいる, かえる, きる look like ru-verbs but are u-verbs.")
                    typeRow(.u, "U-verb (五段)", "Ends in any -u sound. If it is not -eru/-iru, it is a u-verb.")
                    typeRow(.irregular, "Irregular", "Only する and くる, and compounds like べんきょうする.")
                }
                Section("て-form rules") {
                    ruleRow(color: VerbType.ru.accentColor, from: "Ru-verb", to: "drop る + て", example: "たべる → たべて")
                    ruleRow(color: VerbType.irregular.accentColor, from: "する / くる", to: "して / きて", example: "べんきょうする → べんきょうして")
                    ForEach(TeFormRule.all, id: \.group) { rule in
                        ruleRow(color: rule.group.accentColor, from: rule.endings, to: rule.result,
                                example: "\(rule.example.dict) → \(rule.example.te)")
                    }
                }
            }
            .navigationTitle("Guide")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func typeRow(_ type: VerbType, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.bold))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .accentPill(type.accentColor)
            Text(text).font(.callout).foregroundStyle(.secondary)
        }
    }

    private func ruleRow(color: Color, from: String, to: String, example: String) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(from) → \(to)").font(.body.weight(.semibold))
                Text(example).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
