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
    @AppStorage(RecentTags.key) private var recentTagsRaw = ""
    /// The tag chips as first drawn, so ticking or unticking never makes one jump or vanish.
    @State private var shownTagIDs: [UUID]?
    /// Any field of the standard-form and meaning rows; cleared before a row is removed.
    @FocusState private var editingRow: Bool

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
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    textSection
                    if suggestionsOn { suggestionCard }
                    equivalentsSection
                    sensesSection
                    tagsSection
                    folderAndMoreSection
                }
                .padding(16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .paperBackground()
            .navigationTitle(isNew ? "New word" : "Edit word")
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
                if shownTagIDs == nil { shownTagIDs = tagPicks.compactMap(id(of:)) }
            }
        }
    }

    // MARK: - Sections

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaperFieldSection {
                PaperField("Text", placeholder: "おおきに", text: $draft.text, font: .headword(.title2), axis: .vertical)
                    .autocorrectionDisabled()
                PaperDivider()
                PaperField("Reading", placeholder: "かな", text: optional($draft.reading))
                    .autocorrectionDisabled()
            }
            if draft.reading != nil, draft.reading == autoReading {
                note("Filled in from the furigana dictionary. Change it if it's wrong.")
            }
            if let duplicate {
                HStack {
                    Label {
                        JapaneseText("You already have “\(duplicate.text)”")
                    } icon: {
                        Image(systemName: "exclamationmark.circle")
                    }
                    .font(.footnote)
                    .foregroundStyle(palette.ink)
                    Spacer(minLength: 8)
                    Button("Open") {
                        dismiss()
                        onOpenExisting(duplicate.id)
                    }
                    .buttonStyle(.paperSecondaryInline)
                }
            }
            ForEach(dictionaryForms) { verb in
                HStack {
                    Label {
                        JapaneseText("A form of \(verb.jishoQuery)")
                    } icon: {
                        Image(systemName: "text.magnifyingglass")
                    }
                    .font(.footnote)
                    .foregroundStyle(palette.ink)
                    Spacer(minLength: 8)
                    Button("Use \(verb.jishoQuery)") { useDictionaryForm(verb) }
                        .buttonStyle(.paperSecondaryInline)
                        .accessibilityLabel("Save as the dictionary form, \(verb.jishoQuery)")
                }
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(palette.muted).padding(.horizontal, 4)
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
        PaperFieldSection("Standard Japanese") {
            ForEach(draft.equivalents.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        PaperField("Written", placeholder: "ありがとう", text: row(\.equivalents, index, \.written))
                            .autocorrectionDisabled()
                        PaperField("Reading", placeholder: "かな", text: optional(row(\.equivalents, index, \.reading)))
                            .autocorrectionDisabled()
                        PaperField("Note", placeholder: "Only in casual speech", text: optional(row(\.equivalents, index, \.note)))
                    }
                    .focused($editingRow)
                    removeButton("Remove standard form \(index + 1)") { remove(index, from: \.equivalents) }
                }
                PaperDivider()
            }
            addRow("Add a standard form") { draft.equivalents.append(StandardEquivalent(written: "")) }
        }
    }

    private var sensesSection: some View {
        PaperFieldSection("Meanings") {
            ForEach(draft.senses.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        PaperField("Meaning \(index + 1)", placeholder: "thank you", text: row(\.senses, index, \.meaning))
                        PaperField("Note", placeholder: "≠ standard 直す", text: optional(row(\.senses, index, \.note)))
                    }
                    .focused($editingRow)
                    removeButton("Remove meaning \(index + 1)") { remove(index, from: \.senses) }
                }
                PaperDivider()
            }
            addRow("Add a meaning") { draft.senses.append(Sense(meaning: "")) }
        }
    }

    /// A row field's binding that checks the index, so a field ending its edit after its row was
    /// removed writes nothing instead of crashing.
    private func row<Row, Value>(
        _ rows: WritableKeyPath<WordBankEntryValue, [Row]>, _ index: Int, _ field: WritableKeyPath<Row, Value>
    ) -> Binding<Value> where Value: DefaultValue {
        Binding(
            get: { draft[keyPath: rows].indices.contains(index) ? draft[keyPath: rows][index][keyPath: field] : .defaultValue },
            set: { if draft[keyPath: rows].indices.contains(index) { draft[keyPath: rows][index][keyPath: field] = $0 } }
        )
    }

    /// Clears focus first, then removes the row on the next run loop, so the keyboard never keeps
    /// typing into the row that slid up into its place.
    private func remove<Row>(_ index: Int, from rows: WritableKeyPath<WordBankEntryValue, [Row]>) {
        editingRow = false
        DispatchQueue.main.async {
            if draft[keyPath: rows].indices.contains(index) { draft[keyPath: rows].remove(at: index) }
        }
    }

    private func removeButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "minus.circle")
                .foregroundStyle(palette.muted)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func addRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "plus")
                .font(.body)
                .foregroundStyle(palette.button)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var tagPicks: [TagSuggestion] {
        let applied = draft.dialectTagIDs + draft.customTagIDs
        if let shownTagIDs {
            return TagSuggester().keepingPlaces(
                shown: shownTagIDs, applied: applied, dialectTags: store.dialectTags, customTags: store.customTags)
        }
        return TagSuggester().quickPicks(
            applied: applied, recent: RecentTags.ids(from: recentTagsRaw),
            dialectTags: store.dialectTags, customTags: store.customTags
        )
    }

    private func id(of pick: TagSuggestion) -> UUID? {
        switch pick {
        case let .existingDialect(tag): tag.id
        case let .existingCustom(tag): tag.id
        default: nil
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TAGS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.muted)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            WrappingFlowLayout(spacing: 8) {
                ForEach(tagPicks, id: \.self) { pick in
                    switch pick {
                    case let .existingDialect(tag):
                        tagChip(tag.name, isOn: draft.dialectTagIDs.contains(tag.id)) { toggle(tag.id, in: \.dialectTagIDs) }
                    case let .existingCustom(tag):
                        tagChip(tag.name, isOn: draft.customTagIDs.contains(tag.id)) { toggle(tag.id, in: \.customTagIDs) }
                    default:
                        EmptyView()
                    }
                }
                Button {
                    choosingTags = true
                } label: {
                    Text("+ New tag")
                        .font(.subheadline)
                        .foregroundStyle(palette.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .overlay(Capsule().strokeBorder(palette.rule, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func tagChip(_ name: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            FilterChip(name, isOn: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func toggle(_ id: UUID, in keyPath: WritableKeyPath<WordBankEntryValue, [UUID]>) {
        if draft[keyPath: keyPath].contains(id) {
            draft[keyPath: keyPath].removeAll { $0 == id }
        } else {
            draft[keyPath: keyPath].append(id)
            recentTagsRaw = RecentTags.recording(id, in: recentTagsRaw)
        }
    }

    private var folderAndMoreSection: some View {
        PaperFieldSection {
            Button {
                choosingFolder = true
            } label: {
                HStack {
                    Text("Folder").foregroundStyle(palette.ink)
                    Spacer(minLength: 8)
                    Text(folderPath).foregroundStyle(palette.muted).lineLimit(1)
                    RowChevron()
                }
                .frame(minHeight: 44)
                .padding(.horizontal, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            PaperDivider()
            NavigationLink {
                WordBankEditorMore(draft: $draft)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("More").foregroundStyle(palette.ink)
                        Text("Kanji spelling, notes").font(.caption).foregroundStyle(palette.muted)
                    }
                    Spacer(minLength: 8)
                    RowChevron()
                }
                .frame(minHeight: 44)
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private var folderPath: String {
        draft.folderID.map { store.tree.path(of: $0).map(\.name).joined(separator: " › ") } ?? "Unfiled"
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

/// A value a bounds-checked row binding returns once its row is gone.
protocol DefaultValue { static var defaultValue: Self { get } }
extension String: DefaultValue { static var defaultValue: String { "" } }
extension Optional: DefaultValue { static var defaultValue: Self { nil } }
