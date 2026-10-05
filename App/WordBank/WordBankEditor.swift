import SwiftUI
import VerbKit

/// A request to open the editor: a new entry (optionally filed in a folder or with
/// the text prefilled), or an existing one.
struct WordBankEditorRequest: Identifiable {
    let id = UUID()
    var entry: WordBankEntryValue?
    var folderID: UUID?
    var text: String = ""
}

/// Placeholder until Task 8 builds the real editor: text and nothing else.
struct WordBankEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WordBankStore.self) private var store
    let request: WordBankEditorRequest
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form { TextField("Text", text: $text) }
                .navigationTitle(request.entry == nil ? "New Entry" : "Edit Entry")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            var entry = request.entry ?? WordBankEntryValue(text: "", folderID: request.folderID)
                            entry.text = text
                            if (try? store.save(entry)) != nil { dismiss() }
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .onAppear { text = request.entry?.text ?? request.text }
        }
    }
}
