import SwiftUI
import VerbKit

/// How entries are grouped and sorted in a list.
enum WordBankGrouping: String, CaseIterable, Identifiable {
    case dateAdded, dialect, alphabetical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dateAdded: "Date added"
        case .dialect: "Dialect"
        case .alphabetical: "A–Z"
        }
    }
}

/// The root screen (`place == nil`), one folder, or one of the smart lists (All entries,
/// Unfiled, Recently added). Folders come first, then entries.
struct WordBankListView: View {
    @Environment(WordBankStore.self) private var store
    #if os(iOS)
    @Environment(\.editMode) private var editMode
    #endif
    let place: WordBankPlace?
    @Binding var selection: UUID?
    let onOpen: (UUID) -> Void
    /// Pushes a folder or smart list onto the list column's stack.
    let onPush: (WordBankPlace) -> Void
    let onSettings: () -> Void

    @AppStorage("wordBank.grouping") private var groupingRaw = WordBankGrouping.dateAdded.rawValue
    @State private var chosen = Set<UUID>()
    @State private var folderRequest: FolderNameRequest?
    @State private var editorRequest: WordBankEditorRequest?
    @State private var moveRequest: MoveRequest?
    @State private var deletingFolder: WordBankFolderValue?
    @State private var moveError: String?
    @State private var managingTags = false
    @State private var smartRequest: SmartFolderRequest?
    @State private var deletingSmart: WordBankSmartFolderValue?

    private enum MoveRequest: Identifiable {
        case entries([UUID])
        case folder(WordBankFolderValue)

        var id: String {
            switch self {
            case .entries(let ids): "entries-\(ids.map(\.uuidString).joined())"
            case .folder(let folder): "folder-\(folder.id.uuidString)"
            }
        }
    }

    // MARK: - Data

    private var folderID: UUID? {
        if case .folder(let id)? = place { id } else { nil }
    }

    private var grouping: WordBankGrouping { WordBankGrouping(rawValue: groupingRaw) ?? .dateAdded }

    private var isEditing: Bool {
        #if os(iOS)
        editMode?.wrappedValue.isEditing ?? false
        #else
        false
        #endif
    }

    private var bankIsEmpty: Bool { store.entries.isEmpty && store.folders.isEmpty }

    private var smartFolder: WordBankSmartFolderValue? {
        if case .smart(let id)? = place { store.smartFolders.first { $0.id == id } } else { nil }
    }

    private var title: String {
        switch place {
        case .smart?: smartFolder?.name ?? "Smart folder"
        case nil: "Word Bank"
        case .folder(let id)?: store.tree.folder(id)?.name ?? "Folder"
        case .all?: "All entries"
        case .unfiled?: "Unfiled"
        case .recent?: "Recently added"
        }
    }

    /// "Any of 関西弁, food": what a smart folder matches.
    private var smartSubtitle: String {
        guard let folder = smartFolder else { return "" }
        let names = store.dialectTags.filter { folder.dialectTagIDs.contains($0.id) }.map(\.name)
            + store.customTags.filter { folder.customTagIDs.contains($0.id) }.map(\.name)
        guard !names.isEmpty else { return "No tags" }
        return (folder.match == .any ? "Any of " : "All of ") + names.joined(separator: ", ")
    }

    /// The folder path joined with " › ", empty outside folders and for a top-level
    /// folder, where it would only repeat the title.
    private var subtitle: String {
        if smartFolder != nil { return smartSubtitle }
        guard let folderID else { return "" }
        let path = store.tree.path(of: folderID)
        return path.count > 1 ? path.map(\.name).joined(separator: " › ") : ""
    }

    private var subfolders: [WordBankFolderValue] {
        switch place {
        case nil: store.tree.children(of: nil)
        case .folder(let id)?: store.tree.children(of: id)
        default: []
        }
    }

    private var recentCutoff: Date { Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantPast }

    private var entries: [WordBankEntryValue] {
        switch place {
        case nil, .unfiled?: store.entries.filter { $0.folderID == nil }
        case .folder(let id)?: store.entries.filter { $0.folderID == id }
        case .all?: store.entries
        case .recent?: store.entries.filter { $0.createdAt >= recentCutoff }
        case .smart?: smartFolder.map(store.entries(in:)) ?? []
        }
    }

    private struct EntryGroup: Identifiable {
        let title: String?
        let entries: [WordBankEntryValue]
        var id: String { title ?? "" }
    }

    private func groups(of entries: [WordBankEntryValue]) -> [EntryGroup] {
        if entries.isEmpty { return [] }
        if place == .recent { return [EntryGroup(title: nil, entries: entries.sorted { $0.createdAt > $1.createdAt })] }
        switch grouping {
        case .dateAdded:
            return [EntryGroup(title: nil, entries: entries.sorted { $0.createdAt > $1.createdAt })]
        case .alphabetical:
            return [EntryGroup(title: nil, entries: entries.sorted {
                JapaneseNormalizer.key($0.reading ?? $0.text) < JapaneseNormalizer.key($1.reading ?? $1.text)
            })]
        case .dialect:
            let regionOrder = Dictionary(uniqueKeysWithValues: Region.allCases.enumerated().map { ($1, $0) })
            var buckets: [String: (order: Int, entries: [WordBankEntryValue])] = [:]
            var untagged: [WordBankEntryValue] = []
            for entry in entries {
                let tags = store.dialectTags.filter { entry.dialectTagIDs.contains($0.id) }
                    .sorted { (regionOrder[$0.region] ?? 0, $0.name) < (regionOrder[$1.region] ?? 0, $1.name) }
                guard let tag = tags.first else { untagged.append(entry); continue }
                let name = "\(tag.region.name) › \(tag.name)"
                buckets[name, default: ((regionOrder[tag.region] ?? 0), [])].entries.append(entry)
            }
            var result = buckets.sorted { ($0.value.order, $0.key) < ($1.value.order, $1.key) }
                .map { EntryGroup(title: $0.key, entries: $0.value.entries.sorted { $0.createdAt > $1.createdAt }) }
            if !untagged.isEmpty {
                result.append(EntryGroup(title: result.isEmpty ? nil : "Untagged", entries: untagged.sorted { $0.createdAt > $1.createdAt }))
            }
            return result
        }
    }

    private func entryCount(in folder: UUID) -> Int {
        let subtree = store.tree.descendants(of: folder).union([folder])
        return store.entries.filter { $0.folderID.map(subtree.contains) ?? false }.count
    }

    // MARK: - Body

    var body: some View {
        List(selection: $chosen) {
            if place == nil, !bankIsEmpty {
                Section {
                    smartRow("All entries", systemImage: "tray.full", place: .all, count: store.entries.count)
                    smartRow("Unfiled", systemImage: "tray", place: .unfiled, count: store.entries.filter { $0.folderID == nil }.count)
                    smartRow("Recently added", systemImage: "clock", place: .recent,
                             count: store.entries.filter { $0.createdAt >= recentCutoff }.count)
                }
            }
            if !subfolders.isEmpty {
                Section(place == nil ? "Folders" : "") {
                    ForEach(subfolders) { folderRow($0) }
                }
            }
            if place == nil, !store.smartFolders.isEmpty {
                Section("Smart folders") {
                    ForEach(store.smartFolders) { smartFolderRow($0) }
                }
            }
            ForEach(groups(of: entries)) { group in
                Section(group.title ?? (subfolders.isEmpty && place != nil ? "" : "Entries")) {
                    ForEach(group.entries) { entryRow($0) }
                }
            }
        }
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        .toolbar { toolbar }
        .overlay { emptyState }
        .sheet(item: $editorRequest) { WordBankEditor(request: $0, onOpenExisting: onOpen) }
        .sheet(isPresented: $managingTags) { TagManagerView() }
        .sheet(item: $smartRequest) { SmartFolderEditor(request: $0) }
        .confirmationDialog(
            "Delete “\(deletingSmart?.name ?? "")”?",
            isPresented: Binding(get: { deletingSmart != nil }, set: { if !$0 { deletingSmart = nil } }),
            titleVisibility: .visible
        ) {
            if let folder = deletingSmart {
                Button("Delete smart folder", role: .destructive) { store.delete(smartFolder: folder.id) }
            }
        } message: {
            Text("Your entries and tags stay as they are.")
        }
        .sheet(item: $folderRequest) { FolderNameSheet(request: $0) }
        .sheet(item: $moveRequest) { request in
            switch request {
            case .entries(let ids):
                FolderPicker(current: store.entries.first { $0.id == ids.first }?.folderID) { target in
                    store.move(entryIDs: ids, to: target)
                    chosen = []
                }
            case .folder(let folder):
                FolderPicker(
                    title: "Move “\(folder.name)” to…", current: folder.parentID,
                    disabled: store.tree.descendants(of: folder.id).union([folder.id])
                ) { target in
                    do { try store.move(folder: folder.id, to: target) } catch {
                        moveError = (error as? WordBankError) == .duplicateFolderName
                            ? "A folder named “\(folder.name)” already exists there."
                            : "That folder can't go there."
                    }
                }
            }
        }
        .folderDeleteDialog($deletingFolder, store: store)
        .alert("Couldn't move the folder", isPresented: Binding(get: { moveError != nil }, set: { if !$0 { moveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(moveError ?? "")
        }
        #if os(iOS)
        .toolbar(isEditing ? .hidden : .automatic, for: .tabBar)
        #endif
    }

    // MARK: - Rows

    /// A row that pushes `place`. Looks like a disclosure row.
    private func placeRow(_ title: String, systemImage: String, place: WordBankPlace, count: Int) -> some View {
        Button { onPush(place) } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isLink)
    }

    private func smartRow(_ title: String, systemImage: String, place: WordBankPlace, count: Int) -> some View {
        placeRow(title, systemImage: systemImage, place: place, count: count)
    }

    private func smartFolderRow(_ folder: WordBankSmartFolderValue) -> some View {
        placeRow(folder.name, systemImage: "gearshape.2", place: .smart(folder.id), count: store.entries(in: folder).count)
            .contextMenu {
                Button("Edit…", systemImage: "pencil") { smartRequest = .edit(folder) }
                Button("Delete…", systemImage: "trash", role: .destructive) { deletingSmart = folder }
            }
    }

    private func folderRow(_ folder: WordBankFolderValue) -> some View {
        placeRow(folder.name, systemImage: "folder", place: .folder(folder.id), count: entryCount(in: folder.id))
        .contextMenu {
            Button("Rename", systemImage: "pencil") { folderRequest = .rename(folder) }
            Button("Move to…", systemImage: "folder") { moveRequest = .folder(folder) }
            Button("Delete…", systemImage: "trash", role: .destructive) { deletingFolder = folder }
        }
        .draggable("folder:\(folder.id.uuidString)")
        .dropDestination(for: String.self) { items, _ in drop(items, onto: folder.id) }
    }

    @ViewBuilder
    private func entryRow(_ entry: WordBankEntryValue) -> some View {
        Group {
            if isEditing {
                WordBankRow(entry: entry)
            } else {
                Button { onOpen(entry.id) } label: {
                    WordBankRow(entry: entry, folderPath: showsFolderPath ? folderPath(of: entry) : nil)
                }
                .buttonStyle(.plain)
            }
        }
        .tag(entry.id)
        .listRowBackground(selection == entry.id ? Color.accentColor.opacity(0.15) : nil)
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) { store.delete(entryIDs: [entry.id]) }
        }
        .contextMenu {
            Button("Edit", systemImage: "pencil") { editorRequest = WordBankEditorRequest(entry: entry) }
            Button("Move to…", systemImage: "folder") { moveRequest = .entries([entry.id]) }
            Button("Delete", systemImage: "trash", role: .destructive) { store.delete(entryIDs: [entry.id]) }
        }
        .draggable("entry:\(entry.id.uuidString)")
    }

    /// Smart lists mix folders, so each row says where its entry is filed.
    private var showsFolderPath: Bool {
        switch place {
        case .all?, .recent?, .smart?: true
        default: false
        }
    }

    private func folderPath(of entry: WordBankEntryValue) -> String? {
        entry.folderID.map { store.tree.path(of: $0).map(\.name).joined(separator: " › ") }
    }

    // MARK: - Drag and drop

    private func drop(_ items: [String], onto folder: UUID) -> Bool {
        var handled = false
        for item in items {
            if item.hasPrefix("entry:"), let id = UUID(uuidString: String(item.dropFirst(6))) {
                store.move(entryIDs: [id], to: folder)
                handled = true
            } else if item.hasPrefix("folder:"), let id = UUID(uuidString: String(item.dropFirst(7))) {
                handled = ((try? store.move(folder: id, to: folder)) != nil) || handled
            }
        }
        return handled
    }

    // MARK: - Toolbar and empty states

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if !isEditing {
                Menu("Add", systemImage: "plus") {
                    Button("New Entry", systemImage: "square.and.pencil") {
                        editorRequest = WordBankEditorRequest(folderID: folderID)
                    }
                    Button("New Folder", systemImage: "folder.badge.plus") { folderRequest = .create(parent: folderID) }
                    Button("New Smart Folder", systemImage: "gearshape.2") { smartRequest = .create }
                }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            if isEditing {
                #if os(iOS)
                Button("Done") { editMode?.wrappedValue = .inactive; chosen = [] }
                #endif
            } else {
                Menu("More", systemImage: "ellipsis") {
                    #if os(iOS)
                    if !entries.isEmpty {
                        Button("Select Entries", systemImage: "checkmark.circle") { editMode?.wrappedValue = .active }
                    }
                    #endif
                    Picker("Group by", selection: $groupingRaw) {
                        ForEach(WordBankGrouping.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Button("Manage Tags", systemImage: "tag") { managingTags = true }
                    Button("Settings", systemImage: "gearshape", action: onSettings)
                    ReportProblemButton(item: "Word Bank")
                }
            }
        }
        #if os(iOS)
        ToolbarItemGroup(placement: .bottomBar) {
            if isEditing {
                Button("Move", systemImage: "folder") { moveRequest = .entries(Array(chosen)) }
                    .disabled(chosen.isEmpty)
                Spacer()
                Button("Delete", systemImage: "trash", role: .destructive) {
                    store.delete(entryIDs: Array(chosen))
                    chosen = []
                }
                .disabled(chosen.isEmpty)
            }
        }
        #endif
    }

    @ViewBuilder
    private var emptyState: some View {
        if store.entries.isEmpty && store.folders.isEmpty {
            ContentUnavailableView {
                Label("Your Word Bank is empty", systemImage: "books.vertical")
            } description: {
                Text("Save dialect words, phrases and sentences you learn outside the app.")
            } actions: {
                Button("Add your first entry") { editorRequest = WordBankEditorRequest(folderID: folderID) }
                    .buttonStyle(.glassProminent)
            }
        } else if let folder = smartFolder, entries.isEmpty {
            ContentUnavailableView {
                Label("No entries match", systemImage: "gearshape.2")
            } description: {
                Text(folder.tagCount == 0 ? "This smart folder has no tags left. Edit it to pick some." : "Entries with these tags will show up here.")
            } actions: {
                Button("Edit smart folder") { smartRequest = .edit(folder) }
            }
        } else if place != nil, subfolders.isEmpty, entries.isEmpty {
            ContentUnavailableView(
                folderID == nil ? "Nothing here yet" : "This folder is empty",
                systemImage: folderID == nil ? "tray" : "folder"
            )
        }
    }
}
