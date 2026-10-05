import SwiftUI
import VerbKit

/// One entry: the text large (with furigana), a comparison with standard Japanese, its
/// meanings, a chip per kanji that opens Jisho, tags, where it's filed, notes and dates.
struct WordBankDetailView: View {
    @Environment(WordBankStore.self) private var store
    @Environment(\.openURL) private var openURL
    let entry: WordBankEntryValue
    @Binding var selection: UUID?

    @State private var editing = false
    @State private var moving = false
    @State private var deleting = false

    private var dialectTags: [DialectTagValue] { store.dialectTags.filter { entry.dialectTagIDs.contains($0.id) } }
    private var customTags: [CustomTagValue] { store.customTags.filter { entry.customTagIDs.contains($0.id) } }

    private var kanji: [Character] {
        KanjiExtraction.kanji(in: [entry.text, entry.kanjiSpelling ?? ""] + entry.equivalents.map(\.written))
    }

    private var folderPath: String? {
        entry.folderID.map { store.tree.path(of: $0).map(\.name).joined(separator: " › ") }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if !entry.equivalents.isEmpty { comparisonCard }
                if !entry.senses.isEmpty { meaningsSection }
                if !kanji.isEmpty { kanjiSection }
                if !dialectTags.isEmpty || !customTags.isEmpty { tagsSection }
                if folderPath != nil || entry.notes != nil { detailsSection }
                dates
            }
            .padding()
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(entry.text)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit", systemImage: "square.and.pencil") { editing = true }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Move to…", systemImage: "folder") { moving = true }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Delete", systemImage: "trash", role: .destructive) { deleting = true }
            }
            ToolbarItem(placement: .secondaryAction) {
                ReportProblemButton(item: "Word Bank entry")
            }
        }
        .sheet(isPresented: $editing) {
            WordBankEditor(request: WordBankEditorRequest(entry: entry))
        }
        .sheet(isPresented: $moving) {
            FolderPicker(current: entry.folderID) { store.move(entryIDs: [entry.id], to: $0) }
        }
        .confirmationDialog("Delete “\(entry.text)”?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete entry", role: .destructive) {
                store.delete(entryIDs: [entry.id])
                selection = nil
            }
        } message: {
            Text("This can't be undone.")
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(entry.kind.rawValue.capitalized)
                if let wordClass = entry.wordClass { Text("· \(wordClass.rawValue)") }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            JapaneseText(entry.text)
                .font(.largeTitle.weight(.heavy))
                .textActions(entry.text, translate: entry.kind == .sentence)

            // Furigana covers kanji it knows; a reading the user typed for kana-only text,
            // or for kanji the dictionary doesn't know, is shown plainly.
            if let reading = entry.reading, JapaneseNormalizer.key(reading) != JapaneseNormalizer.key(entry.text) {
                Text(reading).font(.title3).foregroundStyle(.secondary)
            }
            if let spelling = entry.kanjiSpelling {
                HStack(spacing: 6) {
                    Text("Written").font(.caption).foregroundStyle(.secondary)
                    JapaneseText(spelling).font(.title3)
                }
                .textActions(spelling)
            }

            HStack(spacing: 8) {
                SpeakButton(text: entry.reading ?? entry.text)
                Text("Standard pronunciation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 方言 → 標準語, one row per standard equivalent.
    private var comparisonCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("方言 → 標準語", systemImage: "arrow.left.arrow.right")
            VStack(alignment: .leading, spacing: 12) {
                ForEach(entry.equivalents.indices, id: \.self) { index in
                    let equivalent = entry.equivalents[index]
                    VStack(alignment: .leading, spacing: 2) {
                        JapaneseText(equivalent.written).font(.title2.weight(.semibold))
                        if let reading = equivalent.reading, JapaneseNormalizer.key(reading) != JapaneseNormalizer.key(equivalent.written) {
                            Text(reading).font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let note = equivalent.note {
                            Text(note).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textActions(equivalent.written)
                    if index < entry.equivalents.count - 1 { Divider() }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var meaningsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Meanings", systemImage: "text.quote")
            ForEach(entry.senses.indices, id: \.self) { index in
                let sense = entry.senses[index]
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(index + 1)").font(.callout.weight(.bold)).foregroundStyle(.secondary).monospacedDigit()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sense.meaning).font(.body)
                        if let note = sense.note {
                            Text(note).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var kanjiSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Kanji", systemImage: "character.book.closed.ja")
            PillFlow(spacing: 8) {
                ForEach(kanji, id: \.self) { character in
                    Button {
                        if let url = TextLookupURL.jishoKanji(character) { openURL(url) }
                    } label: {
                        Text(String(character))
                            .font(.title2)
                            .frame(minWidth: 44, minHeight: 44)
                            .glassEffect(in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Look up \(character) in Jisho")
                }
            }
            Text("Tap a kanji to open it in Jisho.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Tags", systemImage: "tag")
            PillFlow(spacing: 6) {
                ForEach(dialectTags) { TagPill($0) }
                ForEach(customTags) { TagPill($0) }
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let folderPath {
                Label(folderPath, systemImage: "folder").font(.subheadline).foregroundStyle(.secondary)
            }
            if let notes = entry.notes {
                sectionHeader("Notes", systemImage: "note.text")
                Text(notes).font(.body).textSelection(.enabled)
            }
        }
    }

    private var dates: some View {
        let added = entry.createdAt.formatted(date: .abbreviated, time: .omitted)
        let edited = entry.updatedAt.formatted(date: .abbreviated, time: .omitted)
        return Text(added == edited ? "Added \(added)" : "Added \(added) · Edited \(edited)")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage).font(.title3.weight(.semibold))
    }
}
