import SwiftUI
import VerbKit

/// The editor's "More" page: what most entries leave alone — kind, word class, kanji spelling and
/// notes — in paper sections.
struct WordBankEditorMore: View {
    @Binding var draft: WordBankEntryValue

    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PaperFieldSection("Kind") {
                    Picker("Kind", selection: $draft.kind) {
                        ForEach(EntryKind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(12)
                    if draft.kind == .word {
                        PaperDivider()
                        Picker("Word class", selection: $draft.wordClass) {
                            Text("None").tag(WordClass?.none)
                            ForEach(WordClass.allCases, id: \.self) { Text($0.rawValue.capitalized).tag(WordClass?.some($0)) }
                        }
                        .tint(palette.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                    }
                }
                PaperFieldSection {
                    PaperField("Kanji spelling", placeholder: "大きに", text: optional($draft.kanjiSpelling))
                        .autocorrectionDisabled()
                    PaperDivider()
                    PaperField("Source or notes", placeholder: "Heard in Osaka", text: optional($draft.notes), axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .padding(16)
        }
        .paperBackground()
        .navigationTitle("More")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func optional(_ binding: Binding<String?>) -> Binding<String> {
        Binding(get: { binding.wrappedValue ?? "" }, set: { binding.wrappedValue = $0.isEmpty ? nil : $0 })
    }
}
