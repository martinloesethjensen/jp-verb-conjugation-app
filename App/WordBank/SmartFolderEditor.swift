import SwiftUI
import VerbKit

/// What the smart-folder sheet is for.
enum SmartFolderRequest: Identifiable {
    case create
    case edit(WordBankSmartFolderValue)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let folder): "edit-\(folder.id.uuidString)"
        }
    }
}

extension SmartFolderMatch {
    var title: String { self == .any ? "Any tag" : "All tags" }
}

/// Name, tags and Any/All for a smart folder.
struct SmartFolderEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WordBankStore.self) private var store
    let request: SmartFolderRequest
    @State private var name = ""
    @State private var match: SmartFolderMatch = .any
    @State private var dialectIDs = Set<UUID>()
    @State private var customIDs = Set<UUID>()
    @State private var error: WordBankError?

    private var chosenCount: Int { dialectIDs.count + customIDs.count }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && chosenCount > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.sentences)
                        #endif
                } footer: {
                    if let error {
                        Label(FolderNameSheet.message(error), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    }
                }
                Section {
                    Picker("Show entries with", selection: $match) {
                        ForEach(SmartFolderMatch.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(match == .any
                         ? "An entry shows up if it has at least one of the tags you pick."
                         : "An entry shows up only if it has every tag you pick.")
                }
                tagSection
            }
            .navigationTitle(isEditing ? "Edit Smart Folder" : "New Smart Folder")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!canSave) }
            }
            .onChange(of: name) { error = nil }
            .onAppear(perform: load)
        }
    }

    private var isEditing: Bool {
        if case .edit = request { true } else { false }
    }

    @ViewBuilder
    private var tagSection: some View {
        if store.dialectTags.isEmpty && store.customTags.isEmpty {
            Section("Tags") {
                Text("You have no tags yet. Add tags to your entries first (More › Manage Tags).")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } else {
            if !store.dialectTags.isEmpty {
                Section("Dialects") {
                    ForEach(store.dialectTags.sorted { $0.name < $1.name }) { tag in
                        tagRow(TagPill(tag), selected: dialectIDs.contains(tag.id)) { toggle(&dialectIDs, tag.id) }
                    }
                }
            }
            if !store.customTags.isEmpty {
                Section("Tags") {
                    ForEach(store.customTags.sorted { $0.name < $1.name }) { tag in
                        tagRow(TagPill(tag), selected: customIDs.contains(tag.id)) { toggle(&customIDs, tag.id) }
                    }
                }
            }
        }
    }

    private func tagRow(_ pill: TagPill, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                pill
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func toggle(_ set: inout Set<UUID>, _ id: UUID) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }

    private func load() {
        guard case .edit(let folder) = request else { return }
        name = folder.name
        match = folder.match
        dialectIDs = Set(folder.dialectTagIDs)
        customIDs = Set(folder.customTagIDs)
    }

    private func save() {
        // Keep the tag order stable: the order the tags are listed in.
        let dialect = store.dialectTags.map(\.id).filter(dialectIDs.contains)
        let custom = store.customTags.map(\.id).filter(customIDs.contains)
        do {
            switch request {
            case .create:
                try store.createSmartFolder(named: name, dialectTagIDs: dialect, customTagIDs: custom, match: match)
            case .edit(var folder):
                folder.name = name
                folder.dialectTagIDs = dialect
                folder.customTagIDs = custom
                folder.match = match
                try store.update(smartFolder: folder)
            }
            dismiss()
        } catch let failure as WordBankError {
            error = failure
        } catch {}
    }
}
