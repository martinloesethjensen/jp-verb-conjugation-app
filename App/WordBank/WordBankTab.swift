import SwiftUI
import VerbKit

/// A screen pushed onto the Word Bank list's own navigation stack.
enum WordBankPlace: Hashable {
    case folder(UUID)
    case all
    case unfiled
    case recent
}

/// The Word Bank as a tab: a `NavigationSplitView` like Verbs and Grammar. The list column
/// is its own `NavigationStack` (one screen per folder); the detail column shows the
/// selected entry. Selection is an entry id, so a deleted entry just clears the detail.
/// Folder rows push by appending to `path` rather than with `NavigationLink`: inside a
/// split view's sidebar on iPhone, a link is taken over by the split view and lands in
/// the detail column.
struct WordBankTab: View {
    @Environment(WordBankStore.self) private var store
    @Binding var selection: UUID?
    @Binding var preferredColumn: NavigationSplitViewColumn
    let onSettings: () -> Void
    @State private var path: [WordBankPlace] = []

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredColumn) {
            NavigationStack(path: $path) {
                WordBankListView(place: nil, selection: $selection, onOpen: open, onPush: { path.append($0) }, onSettings: onSettings)
                    .navigationDestination(for: WordBankPlace.self) { place in
                        WordBankListView(place: place, selection: $selection, onOpen: open, onPush: { path.append($0) }, onSettings: onSettings)
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
