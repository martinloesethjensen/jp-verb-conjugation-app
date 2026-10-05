import SwiftUI
import VerbKit

/// What a folder-name sheet is for.
enum FolderNameRequest: Identifiable {
    case create(parent: UUID?)
    case rename(WordBankFolderValue)

    var id: String {
        switch self {
        case .create(let parent): "create-\(parent?.uuidString ?? "root")"
        case .rename(let folder): "rename-\(folder.id.uuidString)"
        }
    }
}

/// Name field for a new or renamed folder. A duplicate or blank name stays on screen
/// with the reason; the store decides what is allowed.
struct FolderNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WordBankStore.self) private var store
    let request: FolderNameRequest
    @State private var name = ""
    @State private var error: WordBankError?
    @FocusState private var focused: Bool

    private var title: String {
        if case .rename = request { "Rename Folder" } else { "New Folder" }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Folder name", text: $name)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.sentences)
                        #endif
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(save)
                } footer: {
                    if let error {
                        Label(Self.message(error), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: name) { error = nil }
            .onAppear {
                if case .rename(let folder) = request { name = folder.name }
                focused = true
            }
        }
        .presentationDetents([.height(220)])
    }

    private func save() {
        do {
            switch request {
            case .create(let parent): try store.createFolder(named: name, in: parent)
            case .rename(let folder): try store.rename(folder: folder.id, to: name)
            }
            dismiss()
        } catch let failure as WordBankError {
            error = failure
        } catch {}
    }

    static func message(_ error: WordBankError) -> String {
        switch error {
        case .duplicateFolderName: "A folder with this name already exists here."
        case .blankName, .blankText: "Enter a name."
        case .invalidMove: "A folder can't go inside itself."
        case .duplicateTagName: "A tag with this name already exists."
        case .saveFailed: "Couldn't save. Try again."
        }
    }
}

extension View {
    /// The confirmation dialog for deleting a folder: keep what's inside (the default)
    /// or delete everything, with the entry count shown.
    func folderDeleteDialog(_ folder: Binding<WordBankFolderValue?>, store: WordBankStore) -> some View {
        let presented = folder.wrappedValue
        let tree = store.tree
        let doomed = presented.map { tree.descendants(of: $0.id).union([$0.id]) } ?? []
        let entryCount = store.entries.filter { $0.folderID.map(doomed.contains) ?? false }.count
        return confirmationDialog(
            presented.map { "Delete “\($0.name)”?" } ?? "",
            isPresented: Binding(get: { folder.wrappedValue != nil }, set: { if !$0 { folder.wrappedValue = nil } }),
            titleVisibility: .visible
        ) {
            if let presented {
                Button("Keep entries") { store.delete(folder: presented.id, .keepContents) }
                Button(entryCount == 0 ? "Delete folder" : "Delete folder and \(entryCount) \(entryCount == 1 ? "entry" : "entries")", role: .destructive) {
                    store.delete(folder: presented.id, .deleteContents)
                }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            Text("Keep entries moves what's inside up one level.")
        }
    }
}
