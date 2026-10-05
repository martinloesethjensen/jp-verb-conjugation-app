import SwiftUI
import VerbKit

/// A folder pushed onto the Word Bank list's own navigation stack.
struct FolderRoute: Hashable {
    let id: UUID
}

/// The Word Bank as a tab: a `NavigationSplitView` like Verbs and Grammar. The list column
/// is its own `NavigationStack` (one screen per folder); the detail column shows the
/// selected entry. Selection is an entry id, so a deleted entry just clears the detail.
struct WordBankTab: View {
    @Environment(WordBankStore.self) private var store
    @Binding var selection: UUID?
    @Binding var preferredColumn: NavigationSplitViewColumn
    let onSettings: () -> Void
    @State private var path: [FolderRoute] = []

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredColumn) {
            NavigationStack(path: $path) {
                WordBankListView(folderID: nil, selection: $selection, onOpen: open, onSettings: onSettings)
                    .navigationDestination(for: FolderRoute.self) { route in
                        WordBankListView(folderID: route.id, selection: $selection, onOpen: open, onSettings: onSettings)
                    }
            }
        } detail: {
            if let selection, let entry = store.entries.first(where: { $0.id == selection }) {
                WordBankDetailView(entry: entry, selection: $selection)
            } else {
                ContentUnavailableView("Select an Entry", systemImage: "books.vertical")
            }
        }
        .onChange(of: preferredColumn) { _, column in
            // Back to the list on iPhone: nothing is selected any more.
            if column == .sidebar { selection = nil }
        }
        .onChange(of: store.entries) { _, entries in
            if let selection, !entries.contains(where: { $0.id == selection }) {
                self.selection = nil
                preferredColumn = .sidebar
            }
        }
    }

    /// Shows an entry in the detail column (on iPhone, pushes it).
    private func open(_ id: UUID) {
        selection = id
        preferredColumn = .detail
    }
}
