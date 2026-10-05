import SwiftUI
import VerbKit

/// Picks tags for an entry, or (with no bindings) just creates them from Manage tags.
/// One field does everything: typing shows your own tags first (so nothing is duplicated),
/// then dialects from the bundled catalogue, then custom tag ideas, then "Create". With
/// the field empty it shows recently used tags and dialects related to the ones you have.
struct TagPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WordBankStore.self) private var store
    var dialectIDs: Binding<[UUID]>?
    var customIDs: Binding<[UUID]>?
    @State private var query = ""
    @State private var message: String?
    @State private var newDialect: NewDialectRequest?
    /// The last eight tag ids used, newest first, one per line. This device only.
    @AppStorage("wordBank.recentTags") private var recentRaw = ""
    private let suggester = TagSuggester()

    private var applying: Bool { dialectIDs != nil }

    private var appliedIDs: Set<UUID> {
        Set((dialectIDs?.wrappedValue ?? []) + (customIDs?.wrappedValue ?? []))
    }

    private var recent: [UUID] { recentRaw.split(separator: "\n").compactMap { UUID(uuidString: String($0)) } }

    private var appliedDialects: [DialectTagValue] {
        let ids = dialectIDs?.wrappedValue ?? []
        return ids.compactMap { id in store.dialectTags.first { $0.id == id } }
    }

    private var appliedCustom: [CustomTagValue] {
        let ids = customIDs?.wrappedValue ?? []
        return ids.compactMap { id in store.customTags.first { $0.id == id } }
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            List {
                if applying, !appliedDialects.isEmpty || !appliedCustom.isEmpty {
                    Section("On this entry") {
                        ForEach(appliedDialects) { tag in
                            removeRow(TagPill(tag)) { dialectIDs?.wrappedValue.removeAll { $0 == tag.id } }
                        }
                        ForEach(appliedCustom) { tag in
                            removeRow(TagPill(tag)) { customIDs?.wrappedValue.removeAll { $0 == tag.id } }
                        }
                    }
                }
                Section {
                    TextField("New tag…", text: $query)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .submitLabel(.done)
                } footer: {
                    if let message {
                        Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    }
                }
                if trimmed.isEmpty { emptyFieldSections } else { suggestionSections }
            }
            .navigationTitle(applying ? "Tags" : "Add Tag")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onChange(of: query) { message = nil }
            .sheet(item: $newDialect) { request in
                NewDialectTagSheet(request: request) { created in
                    use(created)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Sections

    @ViewBuilder
    private var emptyFieldSections: some View {
        let related = suggester.related(
            to: appliedDialects, recent: recent,
            allDialectTags: store.dialectTags, allCustomTags: store.customTags
        ).filter { suggestion in
            switch suggestion {
            case .existingDialect(let tag): !appliedIDs.contains(tag.id)
            case .existingCustom(let tag): !appliedIDs.contains(tag.id)
            default: true
            }
        }
        let used = related.filter { if case .existingDialect = $0 { true } else if case .existingCustom = $0 { true } else { false } }
        let ideas = related.filter { if case .dialect = $0 { true } else { false } }
        if !used.isEmpty {
            Section("Recently used") { ForEach(used, id: \.self) { suggestionRow($0) } }
        }
        if !ideas.isEmpty {
            Section(appliedDialects.isEmpty ? "Dialects" : "Related dialects") {
                ForEach(Array(ideas.prefix(12)), id: \.self) { suggestionRow($0) }
            }
        }
        if used.isEmpty, ideas.isEmpty, !applying || (appliedDialects.isEmpty && appliedCustom.isEmpty) {
            Section {
                Text("Type a dialect (kuma, osaka, 大阪弁) or any tag you like.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var suggestionSections: some View {
        let result = suggester.suggestions(
            for: trimmed, dialectTags: store.dialectTags, customTags: store.customTags, excluding: applying ? [] : appliedIDs
        )
        if !result.yours.isEmpty {
            Section("Already yours") { ForEach(result.yours, id: \.self) { suggestionRow($0) } }
        }
        if !result.dialects.isEmpty {
            Section("Dialects") { ForEach(result.dialects, id: \.self) { suggestionRow($0) } }
        }
        if !result.ideas.isEmpty {
            Section("Ideas") { ForEach(result.ideas, id: \.self) { suggestionRow($0) } }
        }
        if result.isDuplicate {
            Section { Label("Already exists", systemImage: "checkmark.circle").foregroundStyle(.secondary) }
        } else if !result.create.isEmpty {
            Section("Create “\(trimmed)”") { ForEach(result.create, id: \.self) { suggestionRow($0) } }
        }
    }

    // MARK: - Rows

    private func removeRow(_ pill: TagPill, remove: @escaping () -> Void) -> some View {
        HStack {
            pill
            Spacer()
            Button("Remove", systemImage: "minus.circle.fill", role: .destructive, action: remove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
        }
    }

    private func suggestionRow(_ suggestion: TagSuggestion) -> some View {
        let applied: Bool = {
            switch suggestion {
            case .existingDialect(let tag): appliedIDs.contains(tag.id)
            case .existingCustom(let tag): appliedIDs.contains(tag.id)
            default: false
            }
        }()
        return Button { choose(suggestion) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    switch suggestion {
                    case .existingDialect(let tag): TagPill(tag)
                    case .existingCustom(let tag): TagPill(tag)
                    case .dialect(let record):
                        Text(record.name).font(.body.weight(.semibold))
                        Text(subtitle(record)).font(.caption).foregroundStyle(.secondary)
                    case .prefecture(let prefecture):
                        Text(prefecture.name).font(.body.weight(.semibold))
                        Text("Prefecture tag · \(prefecture.region.name)").font(.caption).foregroundStyle(.secondary)
                    case .customIdea(let name, let color): TagPill(name, color: color.color, systemImage: "number")
                    case .createCustom(let name): Text("Tag “\(name)”").font(.body)
                    case .createDialect(let name, _): Text("Dialect tag “\(name)”…").font(.body)
                    }
                }
                Spacer()
                if applied { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!applying && isExisting(suggestion))
    }

    private func isExisting(_ suggestion: TagSuggestion) -> Bool {
        switch suggestion {
        case .existingDialect, .existingCustom: true
        default: false
        }
    }

    private func subtitle(_ record: DialectRecord) -> String {
        let places = record.prefectures.count > 2 ? record.region.name : record.prefectures.map(\.name).joined(separator: "・")
        return "\(record.romaji) · \(places) · \(record.region.name)"
    }

    // MARK: - Actions

    private func choose(_ suggestion: TagSuggestion) {
        do {
            switch suggestion {
            case .existingDialect(let tag): toggle(dialect: tag)
            case .existingCustom(let tag): toggle(custom: tag)
            case .dialect(let record): use(try store.createDialectTag(from: record))
            case .prefecture(let prefecture):
                use(try store.createDialectTag(DialectTagValue(
                    name: prefecture.name, romaji: prefecture.romaji, prefectures: [prefecture], region: prefecture.region
                )))
            case .customIdea(let name, let color): use(try store.createCustomTag(named: name, color: color))
            case .createCustom(let name): use(try store.createCustomTag(named: name, color: .gray))
            case .createDialect(let name, let preselected): newDialect = NewDialectRequest(name: name, preselected: preselected)
            }
        } catch let failure as WordBankError {
            message = failure == .duplicateTagName ? "A tag with this name already exists." : FolderNameSheet.message(failure)
        } catch {}
    }

    private func toggle(dialect tag: DialectTagValue) {
        guard let ids = dialectIDs else { return }
        if ids.wrappedValue.contains(tag.id) { ids.wrappedValue.removeAll { $0 == tag.id } } else { ids.wrappedValue.append(tag.id) }
        remember(tag.id)
        query = ""
    }

    private func toggle(custom tag: CustomTagValue) {
        guard let ids = customIDs else { return }
        if ids.wrappedValue.contains(tag.id) { ids.wrappedValue.removeAll { $0 == tag.id } } else { ids.wrappedValue.append(tag.id) }
        remember(tag.id)
        query = ""
    }

    /// A tag was just created: apply it (when picking for an entry) and clear the field.
    private func use(_ tag: DialectTagValue) {
        if let ids = dialectIDs, !ids.wrappedValue.contains(tag.id) { ids.wrappedValue.append(tag.id) }
        remember(tag.id)
        query = ""
    }

    private func use(_ tag: CustomTagValue) {
        if let ids = customIDs, !ids.wrappedValue.contains(tag.id) { ids.wrappedValue.append(tag.id) }
        remember(tag.id)
        query = ""
    }

    private func remember(_ id: UUID) {
        let ids = ([id] + recent.filter { $0 != id }).prefix(8)
        recentRaw = ids.map(\.uuidString).joined(separator: "\n")
    }
}
