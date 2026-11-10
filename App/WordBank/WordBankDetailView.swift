import SwiftUI
import VerbKit

/// One entry, in paper and ink: its tags and folder above the text in Mincho, 方言 → 標準語, the
/// meanings, a tile per kanji (stroke order, or Jisho without kanji data), notes and dates.
struct WordBankDetailView: View {
    @Environment(WordBankStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(KanjiStore.self) private var kanjiStore: KanjiStore?
    let entry: WordBankEntryValue
    @Binding var selection: UUID?

    @State private var editing = false
    @State private var moving = false
    @State private var deleting = false
    @State private var kanjiRequest: KanjiSheetRequest?
    @Environment(\.palette) private var palette
    @ScaledMetric(relativeTo: .title) private var tileSide: CGFloat = 56

    private var dialectTags: [DialectTagValue] { store.dialectTags.filter { entry.dialectTagIDs.contains($0.id) } }
    private var customTags: [CustomTagValue] { store.customTags.filter { entry.customTagIDs.contains($0.id) } }

    private var chips: KanjiChips {
        KanjiExtraction.chips(text: entry.text, spelling: entry.kanjiSpelling, standard: entry.equivalents.map(\.written))
    }
    private var kanji: [Character] { chips.kanji }

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
                if let notes = entry.notes { notesSection(notes) }
                dates
            }
            .padding()
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .paperBackground()
        .navigationTitle(entry.text)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                SpeakButton(text: entry.reading ?? entry.text)
                    .accessibilityHint("Standard pronunciation")
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

    private var kindLine: String? {
        if entry.kind != .word { return entry.kind.rawValue }
        return entry.wordClass?.displayName.lowercased()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !dialectTags.isEmpty || !customTags.isEmpty || kindLine != nil {
                WrappingFlowLayout(spacing: 6) {
                    ForEach(dialectTags) { TagPill($0) }
                    ForEach(customTags) { TagPill($0) }
                    if let kindLine {
                        Text("· \(kindLine)").font(.caption).foregroundStyle(palette.muted)
                    }
                }
            }
            JapaneseText(entry.text)
                .font(.headword(.largeTitle, scale: 1.35))
                .foregroundStyle(palette.ink)
                .textActions(entry.text, translate: entry.kind == .sentence)
            // Furigana covers kanji it knows; a reading the user typed for kana-only text,
            // or for kanji the dictionary doesn't know, is shown plainly.
            if let reading = entry.reading, JapaneseNormalizer.key(reading) != JapaneseNormalizer.key(entry.text) {
                Text(reading).font(.title3).foregroundStyle(palette.muted)
            }
            if let spelling = entry.kanjiSpelling {
                HStack(spacing: 6) {
                    Text("Written").font(.caption).foregroundStyle(palette.muted)
                    JapaneseText(spelling).font(.title3).foregroundStyle(palette.ink)
                }
                .textActions(spelling)
            }
            if let folderPath {
                Text("Folder: \(folderPath)").font(.subheadline).foregroundStyle(palette.muted)
            }
        }
    }

    /// 方言 → 標準語: the entry beside its standard forms, then a line per form that has a note.
    private var comparisonCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Fixed readings: the dictionary reads 方言 kanji by kanji (かた・い) and lacks 標準語.
            JapaneseText(units: [
                TextUnit(text: "方言", reading: "ほうげん"), TextUnit(text: " → "),
                TextUnit(text: "標準語", reading: "ひょうじゅんご"),
            ])
                .font(.headword(.title3))
                .foregroundStyle(palette.ink)
                .accessibilityAddTraits(.isHeader)
            WrappingFlowLayout(spacing: 10) {
                JapaneseText(entry.text).font(.headword(.title3)).foregroundStyle(palette.ink)
                Image(systemName: "arrow.right").foregroundStyle(palette.muted).accessibilityLabel("in standard Japanese")
                JapaneseText(entry.equivalents.map(\.written).joined(separator: "・"))
                    .font(.headword(.title3))
                    .foregroundStyle(palette.ink)
                    .textActions(entry.equivalents.map(\.written).joined(separator: "・"))
            }
            .paperCard(cornerRadius: 14)
            ForEach(entry.equivalents.indices, id: \.self) { index in
                let equivalent = entry.equivalents[index]
                if let note = equivalent.note {
                    JapaneseText("\(equivalent.written) — \(note)").font(.footnote).foregroundStyle(palette.muted)
                }
            }
        }
    }

    private var meaningsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Meanings")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(entry.senses.indices, id: \.self) { index in
                    let sense = entry.senses[index]
                    if index > 0 { PaperDivider() }
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1)").font(.callout.weight(.bold)).foregroundStyle(palette.muted).monospacedDigit()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sense.meaning).font(.body).foregroundStyle(palette.ink)
                            if let note = sense.note {
                                JapaneseText("— \(note)").font(.footnote).foregroundStyle(palette.muted)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 14)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(palette.rule, lineWidth: 1))
        }
    }

    private var kanjiCaption: String {
        let source: String? = switch chips.source {
        case .standard: "From the standard form."
        case .spelling: "From the kanji spelling."
        case .text, .mixed: nil
        }
        let tap = kanji.contains { kanjiStore?.entry(for: $0) != nil }
            ? "Tap for stroke order." : "Tap a kanji to open it in Jisho."
        return [source, tap].compactMap { $0 }.joined(separator: " ")
    }

    private var kanjiSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Kanji")
            WrappingFlowLayout(spacing: 8) {
                ForEach(kanji, id: \.self) { character in
                    let hasStrokes = kanjiStore?.entry(for: character) != nil
                    Button {
                        if hasStrokes {
                            kanjiRequest = KanjiSheetRequest(character: character)
                        } else if let url = TextLookupURL.jishoKanji(character) {
                            openURL(url)
                        }
                    } label: {
                        Text(String(character))
                            .font(.headword(.title))
                            .foregroundStyle(palette.ink)
                            .frame(minWidth: tileSide, minHeight: tileSide)
                            .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.rule, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(hasStrokes ? "\(String(character)), stroke order" : "Look up \(character) in Jisho")
                }
            }
            Text(kanjiCaption).font(.caption).foregroundStyle(palette.muted)
        }
        .kanjiSheet($kanjiRequest)
        .dismissOnLink { kanjiRequest = nil }
    }

    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Notes")
            JapaneseText(notes)
                .font(.body)
                .foregroundStyle(palette.ink)
                .textSelection(.enabled)
                .paperCard(cornerRadius: 14)
        }
    }

    private var dates: some View {
        let added = WordBankDates.day(entry.createdAt)
        let edited = WordBankDates.day(entry.updatedAt)
        return Text(added == edited ? "Added \(added)" : "Added \(added) · Edited \(edited)")
            .font(.caption)
            .foregroundStyle(palette.muted)
            .frame(maxWidth: .infinity)
    }
}
