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

/// Adds or edits an entry. Only the text is required. The reading is filled from the
/// furigana dictionary when the text has kanji and the reading hasn't been typed by hand.
struct WordBankEditor: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.furiganaDictionary) private var dictionary
    @Environment(WordBankStore.self) private var store
    @Environment(FormLookupStore.self) private var formLookup: FormLookupStore?
    let request: WordBankEditorRequest
    /// Opens another entry instead (from the "you already have this" banner).
    var onOpenExisting: (UUID) -> Void = { _ in }

    @State private var draft: WordBankEntryValue
    /// The reading the dictionary filled in, so a later text edit can refresh it but a
    /// hand-typed reading is never overwritten.
    @State private var autoReading: String?
    @State private var suggestions: EntrySuggestionModel
    @AppStorage(WordBankSuggestions.enabledKey, store: .appGroup) private var suggestionsOn = true
    @State private var choosingFolder = false
    @State private var choosingTags = false
    @State private var failed = false

    init(request: WordBankEditorRequest, onOpenExisting: @escaping (UUID) -> Void = { _ in }) {
        self.request = request
        self.onOpenExisting = onOpenExisting
        _draft = State(initialValue: request.entry ?? WordBankEntryValue(text: request.text, folderID: request.folderID))
        let enabled = UserDefaults.appGroup.object(forKey: WordBankSuggestions.enabledKey) as? Bool ?? true
        _suggestions = State(initialValue: EntrySuggestionModel(suggester: enabled ? OnDeviceEntrySuggester() : nil))
    }

    private var isNew: Bool { request.entry == nil }

    private var trimmedText: String { draft.text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The dictionary form to offer when the text is one conjugated verb the app has
    /// (食べさせられなかった → 食べる), so captured words are saved the way dictionaries list them.
    private var dictionaryForms: [Verb] {
        guard let formLookup else { return [] }
        return FormLookup.dictionaryForms(of: draft.text, in: formLookup.items(in: draft.text))
    }

    private var duplicate: WordBankEntryValue? {
        store.entryWithSameText(as: draft.text, excluding: draft.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                textSection
                suggestionsSection
                equivalentsSection
                sensesSection
                detailsSection
                tagsSection
                moreSection
            }
            .navigationTitle(isNew ? "New Entry" : "Edit Entry")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(trimmedText.isEmpty)
                }
            }
            .sheet(isPresented: $choosingFolder) {
                FolderPicker(title: "Folder", current: draft.folderID) { draft.folderID = $0 }
            }
            .sheet(isPresented: $choosingTags) {
                TagPicker(dialectIDs: $draft.dialectTagIDs, customIDs: $draft.customTagIDs)
            }
            .alert("Couldn't save", isPresented: $failed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The entry needs some text.")
            }
            .onChange(of: draft.text) {
                refreshReading()
                if suggestionsOn { suggestions.textChanged(draft.text) }
            }
            .onAppear {
                if suggestionsOn, !isNew { suggestions.textChanged(draft.text) }
            }
        }
    }

    // MARK: - Sections

    private var textSection: some View {
        Section {
            TextField("Text (おおきに)", text: $draft.text, axis: .vertical)
                .autocorrectionDisabled()
            if let duplicate {
                HStack {
                    Label("You already have “\(duplicate.text)”", systemImage: "exclamationmark.circle")
                        .font(.footnote)
                    Spacer()
                    Button("Open") {
                        dismiss()
                        onOpenExisting(duplicate.id)
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
                }
            }
            ForEach(dictionaryForms) { verb in
                HStack {
                    Label("A form of \(verb.jishoQuery)", systemImage: "text.magnifyingglass")
                        .font(.footnote)
                    Spacer()
                    Button("Use \(verb.jishoQuery)") { useDictionaryForm(verb) }
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Save as the dictionary form, \(verb.jishoQuery)")
                }
            }
            TextField("Reading (かな)", text: optional($draft.reading))
                .autocorrectionDisabled()
        } header: {
            Text("Text")
        } footer: {
            if draft.reading != nil, draft.reading == autoReading {
                Text("Filled in from the furigana dictionary. Change it if it's wrong.")
            }
        }
    }

    // MARK: - Suggestions

    private var appliedCatalogueIDs: Set<String> {
        Set(store.dialectTags.filter { draft.dialectTagIDs.contains($0.id) }.compactMap(\.catalogueID))
    }

    private var suggestionRest: EntrySuggestion? {
        guard case let .ready(full) = suggestions.state else { return nil }
        return full.removing(whatIsIn: draft, appliedDialectCatalogueIDs: appliedCatalogueIDs)
    }

    private var suggestionDialectName: String? {
        suggestionRest?.dialectCatalogueID.flatMap { id in DialectCatalogue.bundled.dialects.first { $0.id == id }?.name }
    }

    private var suggestionCard: some View {
        EntrySuggestionCard(
            state: suggestions.state, rest: suggestionRest, dialectName: suggestionDialectName,
            onUseAll: { if let rest = suggestionRest { useAll(rest) } },
            onDismiss: { suggestions.dismiss() },
            onRetry: { suggestions.retry() }
        )
    }

    @ViewBuilder
    private var suggestionsSection: some View {
        switch suggestions.state {
        case .idle, .unavailable, .dismissed:
            EmptyView()
        default:
            Section { suggestionCard }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
        }
    }

    private func useAll(_ rest: EntrySuggestion) {
        if let reading = rest.reading { draft.apply(reading: reading) }
        rest.standardForms.forEach { draft.apply(standardForm: $0) }
        rest.meanings.forEach { draft.apply(meaning: $0) }
        if let kind = rest.kind { draft.apply(kind: kind) }
        if let id = rest.dialectCatalogueID, let record = DialectCatalogue.bundled.dialects.first(where: { $0.id == id }) {
            applyDialect(record)
        }
    }

    /// Reuses the tag already made from this dialect, or makes it.
    private func applyDialect(_ record: DialectRecord) {
        let tag = store.dialectTags.first { $0.catalogueID == record.id } ?? (try? store.createDialectTag(from: record))
        if let tag, !draft.dialectTagIDs.contains(tag.id) { draft.dialectTagIDs.append(tag.id) }
    }

    private var equivalentsSection: some View {
        Section {
            ForEach(draft.equivalents.indices, id: \.self) { index in
                VStack(alignment: .leading) {
                    TextField("Standard Japanese (ありがとう)", text: $draft.equivalents[index].written)
                        .autocorrectionDisabled()
                    TextField("Reading", text: optional($draft.equivalents[index].reading))
                        .autocorrectionDisabled()
                        .font(.subheadline)
                    TextField("Note", text: optional($draft.equivalents[index].note))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete { draft.equivalents.remove(atOffsets: $0) }
            Button("Add standard form", systemImage: "plus.circle") {
                draft.equivalents.append(StandardEquivalent(written: ""))
            }
        } header: {
            Text("Standard Japanese")
        } footer: {
            Text("What this is in standard Japanese, so entries line up across dialects.")
        }
    }

    private var sensesSection: some View {
        Section {
            ForEach(draft.senses.indices, id: \.self) { index in
                VStack(alignment: .leading) {
                    TextField("Meaning (thank you)", text: $draft.senses[index].meaning)
                    TextField("Note (≠ standard 直す)", text: optional($draft.senses[index].note))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete { draft.senses.remove(atOffsets: $0) }
            Button("Add meaning", systemImage: "plus.circle") {
                draft.senses.append(Sense(meaning: ""))
            }
        } header: {
            Text("Meanings")
        }
    }

    private var detailsSection: some View {
        Section {
            Picker("Kind", selection: $draft.kind) {
                ForEach(EntryKind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)
            if draft.kind == .word {
                Picker("Word class", selection: $draft.wordClass) {
                    Text("None").tag(WordClass?.none)
                    ForEach(WordClass.allCases, id: \.self) { Text($0.rawValue.capitalized).tag(WordClass?.some($0)) }
                }
            }
            Button {
                choosingFolder = true
            } label: {
                HStack {
                    Text("Folder")
                    Spacer()
                    Text(folderName).foregroundStyle(.secondary)
                    RowChevron()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var tagsSection: some View {
        Section("Tags") {
            let dialect = store.dialectTags.filter { draft.dialectTagIDs.contains($0.id) }
            let custom = store.customTags.filter { draft.customTagIDs.contains($0.id) }
            if !dialect.isEmpty || !custom.isEmpty {
                WrappingFlowLayout(spacing: 6) {
                    ForEach(dialect) { TagPill($0) }
                    ForEach(custom) { TagPill($0) }
                }
            }
            Button(dialect.isEmpty && custom.isEmpty ? "Add tags" : "Edit tags", systemImage: "tag") {
                choosingTags = true
            }
        }
    }

    private var moreSection: some View {
        Section("More") {
            TextField("Kanji spelling (大きに)", text: optional($draft.kanjiSpelling))
                .autocorrectionDisabled()
            TextField("Source or notes", text: optional($draft.notes), axis: .vertical)
                .lineLimit(2...6)
        }
    }

    // MARK: - Helpers

    private var folderName: String {
        draft.folderID.flatMap { store.tree.folder($0)?.name } ?? "Unfiled"
    }

    /// A text field's binding for an optional string: empty means nil.
    private func optional(_ binding: Binding<String?>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue ?? "" },
            set: { binding.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }

    private func refreshReading() {
        guard draft.reading == nil || draft.reading == autoReading else { return }
        let derived = readingFor(trimmedText)
        autoReading = derived
        draft.reading = derived
    }

    /// The kana for `text` when it has kanji and every kanji has a reading.
    private func readingFor(_ text: String) -> String? {
        guard let dictionary, dictionary.containsKanji(text), !dictionary.hasUnreadKanji(in: text) else { return nil }
        let reading = dictionary.reading(of: text)
        return reading == text ? nil : reading
    }

    /// Replaces the text with the verb's dictionary form and its reading. The reading
    /// counts as typed by hand, so a later furigana lookup doesn't clear it.
    private func useDictionaryForm(_ verb: Verb) {
        draft.text = verb.jishoQuery
        if verb.kanji != nil { draft.reading = verb.dict }
    }

    private func save() {
        do {
            _ = try store.save(draft)
            dismiss()
        } catch {
            failed = true
        }
    }
}
