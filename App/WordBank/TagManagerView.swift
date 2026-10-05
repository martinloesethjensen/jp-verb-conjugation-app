import SwiftUI
import VerbKit

/// All tags, with how many entries use each. Add tags (the same suggestion field as the
/// entry editor), rename, change a dialect's place or a custom tag's colour, or delete.
struct TagManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WordBankStore.self) private var store
    @State private var adding = false
    @State private var editingDialect: DialectTagValue?
    @State private var editingCustom: CustomTagValue?
    @State private var deletingDialect: DialectTagValue?
    @State private var deletingCustom: CustomTagValue?

    private func count(dialect id: UUID) -> Int { store.entries.filter { $0.dialectTagIDs.contains(id) }.count }
    private func count(custom id: UUID) -> Int { store.entries.filter { $0.customTagIDs.contains(id) }.count }

    private var dialectsByRegion: [(region: Region, tags: [DialectTagValue])] {
        Region.allCases.compactMap { region in
            let tags = store.dialectTags.filter { $0.region == region }.sorted { $0.name < $1.name }
            return tags.isEmpty ? nil : (region, tags)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(dialectsByRegion, id: \.region) { group in
                    Section(group.region.name) {
                        ForEach(group.tags) { tag in
                            tagRow(TagPill(tag), count: count(dialect: tag.id)) { editingDialect = tag }
                                .swipeActions { Button("Delete", systemImage: "trash", role: .destructive) { deletingDialect = tag } }
                        }
                    }
                }
                if !store.customTags.isEmpty {
                    Section("Tags") {
                        ForEach(store.customTags.sorted { $0.name < $1.name }) { tag in
                            tagRow(TagPill(tag), count: count(custom: tag.id)) { editingCustom = tag }
                                .swipeActions { Button("Delete", systemImage: "trash", role: .destructive) { deletingCustom = tag } }
                        }
                    }
                }
            }
            .overlay {
                if store.dialectTags.isEmpty && store.customTags.isEmpty {
                    ContentUnavailableView {
                        Label("No tags yet", systemImage: "tag")
                    } description: {
                        Text("Tag entries with a dialect, like 関西弁, or anything else you like.")
                    } actions: {
                        Button("Add a tag") { adding = true }.buttonStyle(.glassProminent)
                    }
                }
            }
            .navigationTitle("Tags")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add tag", systemImage: "plus") { adding = true }
                }
            }
            .sheet(isPresented: $adding) { TagPicker() }
            .sheet(item: $editingDialect) { DialectTagEditSheet(tag: $0) }
            .sheet(item: $editingCustom) { CustomTagEditSheet(tag: $0) }
            .confirmationDialog(
                "Delete “\(deletingDialect?.name ?? "")”?",
                isPresented: Binding(get: { deletingDialect != nil }, set: { if !$0 { deletingDialect = nil } }),
                titleVisibility: .visible
            ) {
                if let tag = deletingDialect {
                    Button("Delete tag", role: .destructive) { store.delete(dialectTag: tag.id) }
                }
            } message: {
                Text(removalMessage(deletingDialect.map { count(dialect: $0.id) } ?? 0))
            }
            .confirmationDialog(
                "Delete “\(deletingCustom?.name ?? "")”?",
                isPresented: Binding(get: { deletingCustom != nil }, set: { if !$0 { deletingCustom = nil } }),
                titleVisibility: .visible
            ) {
                if let tag = deletingCustom {
                    Button("Delete tag", role: .destructive) { store.delete(customTag: tag.id) }
                }
            } message: {
                Text(removalMessage(deletingCustom.map { count(custom: $0.id) } ?? 0))
            }
        }
    }

    private func removalMessage(_ count: Int) -> String {
        count == 0 ? "No entries use it." : "Removes the tag from \(count) \(count == 1 ? "entry" : "entries"). The entries stay."
    }

    private func tagRow(_ pill: TagPill, count: Int, edit: @escaping () -> Void) -> some View {
        Button(action: edit) {
            HStack {
                pill
                Spacer()
                Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Rename a dialect tag and change where it's spoken.
private struct DialectTagEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WordBankStore.self) private var store
    let tag: DialectTagValue
    @State private var draft: DialectTagValue
    @State private var prefecture: Prefecture?
    @State private var error: WordBankError?

    init(tag: DialectTagValue) {
        self.tag = tag
        _draft = State(initialValue: tag)
        _prefecture = State(initialValue: tag.prefectures.count == 1 ? tag.prefectures.first : nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name).autocorrectionDisabled()
                    TextField("Romaji", text: Binding(get: { draft.romaji ?? "" }, set: { draft.romaji = $0.isEmpty ? nil : $0 }))
                        .autocorrectionDisabled()
                }
                Section {
                    if draft.prefectures.count > 1 {
                        LabeledContent("Prefectures", value: draft.prefectures.map(\.name).joined(separator: "・"))
                    } else {
                        Picker("Prefecture", selection: $prefecture) {
                            Text("None (region only)").tag(Prefecture?.none)
                            ForEach(Region.allCases, id: \.self) { region in
                                Section(region.name) {
                                    ForEach(region.prefectures, id: \.self) { Text($0.name).tag(Prefecture?.some($0)) }
                                }
                            }
                        }
                    }
                    if prefecture == nil, draft.prefectures.count <= 1 {
                        Picker("Region", selection: $draft.region) {
                            ForEach(Region.allCases, id: \.self) { Text($0.name).tag($0) }
                        }
                    }
                } footer: {
                    if let error {
                        Label(FolderNameSheet.message(error), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Tag")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: draft.name) { error = nil }
            .onChange(of: prefecture) { _, new in
                guard draft.prefectures.count <= 1 else { return }
                draft.prefectures = new.map { [$0] } ?? []
                if let new { draft.region = new.region }
            }
        }
    }

    private func save() {
        do {
            try store.update(dialectTag: draft)
            dismiss()
        } catch let failure as WordBankError {
            error = failure
        } catch {}
    }
}

/// Rename a custom tag and pick its colour.
private struct CustomTagEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WordBankStore.self) private var store
    let tag: CustomTagValue
    @State private var draft: CustomTagValue
    @State private var error: WordBankError?

    init(tag: CustomTagValue) {
        self.tag = tag
        _draft = State(initialValue: tag)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name).autocorrectionDisabled()
                } footer: {
                    if let error {
                        Label(FolderNameSheet.message(error), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    }
                }
                Section("Colour") {
                    Picker("Colour", selection: $draft.color) {
                        ForEach(CustomTagColor.allCases, id: \.self) { color in
                            Label(color.title, systemImage: "circle.fill").foregroundStyle(color.color).tag(color)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("Edit Tag")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: draft.name) { error = nil }
        }
    }

    private func save() {
        do {
            try store.update(customTag: draft)
            dismiss()
        } catch let failure as WordBankError {
            error = failure
        } catch {}
    }
}
