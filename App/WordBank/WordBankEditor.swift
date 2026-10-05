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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.furiganaDictionary) private var dictionary
    @Environment(WordBankStore.self) private var store
    let request: WordBankEditorRequest
    /// Opens another entry instead (from the "you already have this" banner).
    var onOpenExisting: (UUID) -> Void = { _ in }

    @State private var draft: WordBankEntryValue
    /// The reading the dictionary filled in, so a later text edit can refresh it but a
    /// hand-typed reading is never overwritten.
    @State private var autoReading: String?
    @State private var choosingFolder = false
    @State private var choosingTags = false
    @State private var failed = false

    init(request: WordBankEditorRequest, onOpenExisting: @escaping (UUID) -> Void = { _ in }) {
        self.request = request
        self.onOpenExisting = onOpenExisting
        _draft = State(initialValue: request.entry ?? WordBankEntryValue(text: request.text, folderID: request.folderID))
    }

    private var isNew: Bool { request.entry == nil }

    private var trimmedText: String { draft.text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var duplicate: WordBankEntryValue? {
        store.entryWithSameText(as: draft.text, excluding: draft.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                textSection
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
            .onChange(of: draft.text) { refreshReading() }
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
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
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
                PillFlow {
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

    private func save() {
        do {
            _ = try store.save(draft)
            dismiss()
        } catch {
            failed = true
        }
    }
}
