import SwiftUI
import VerbKit

/// The root screen (`folderID == nil`) or one folder's screen. Filled out in Task 7.
struct WordBankListView: View {
    @Environment(WordBankStore.self) private var store
    let folderID: UUID?
    @Binding var selection: UUID?
    let onOpen: (UUID) -> Void
    let onSettings: () -> Void

    var body: some View {
        List {}
            .navigationTitle("Word Bank")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu("More", systemImage: "ellipsis") {
                        Button("Settings", systemImage: "gearshape", action: onSettings)
                        ReportProblemButton(item: "")
                    }
                }
            }
            .overlay {
                if store.entries.isEmpty && store.folders.isEmpty {
                    ContentUnavailableView {
                        Label("Your Word Bank is empty", systemImage: "books.vertical")
                    } description: {
                        Text("Save dialect words, phrases and sentences you learn outside the app.")
                    } actions: {
                        Button("Add your first entry") {}
                            .buttonStyle(.glassProminent)
                    }
                }
            }
    }
}
