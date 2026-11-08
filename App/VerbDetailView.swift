import SwiftUI
import VerbKit

struct VerbDetailView: View {
    let verb: Verb
    var onExamples: () -> Void
    var onQuiz: () -> Void
    @AppStorage(FavouriteVerbs.defaultsKey, store: .appGroup) private var favouritesRaw = ""
    @Environment(\.palette) private var palette
    @Environment(VerbStore.self) private var verbStore
    @Environment(KanjiStore.self) private var kanjiStore: KanjiStore?
    @State private var kanjiRequest: KanjiSheetRequest?

    private var isFavourite: Bool { FavouriteVerbs(rawValue: favouritesRaw).contains(verb) }

    private var reportItem: String {
        "Verb: " + verb.dict + (verb.kanji.map { " (\($0))" } ?? "")
    }

    private var jishoURL: URL? {
        TextLookupURL.jisho(verb.jishoQuery)
    }

    var body: some View {
        // The detail column of a split view does not push navigation links by
        // itself, so the page owns a stack. Keyed on the verb, so choosing
        // another verb returns to the main page.
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    actions
                    formGroups
                    CommonPhrasesCard(collocations: verb.collocations)
                    VerbPairCard(verb: verb)
                    examples
                    if let notes = verb.notes {
                        notesBox(notes)
                    }
                    kanjiSection
                }
                .padding()
            }
            .paperBackground()
            .navigationTitle(verb.dict)
            #if os(iOS)
            // The header already shows the verb large, and the toolbar leaves no room for an
            // inline title. The title stays set for the back button and VoiceOver.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            #endif
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(isFavourite ? "Remove from favourites" : "Add to favourites",
                           systemImage: isFavourite ? "star.fill" : "star") {
                        var favourites = FavouriteVerbs(rawValue: favouritesRaw)
                        favourites.toggle(verb)
                        favouritesRaw = favourites.rawValue
                    }
                    SpeakButton(text: verb.jishoQuery)
                }
                // iOS draws these as the "More" menu.
                ToolbarItemGroup(placement: .secondaryAction) {
                    if let jishoURL {
                        Link(destination: jishoURL) {
                            Label("Open in Jisho", systemImage: "link")
                        }
                    }
                    ReportProblemButton(item: reportItem)
                }
            }
            .navigationDestination(for: VerbSubPage.self) { page in
                switch page {
                case .potential: PotentialPage(verb: verb)
                case .nDesu: NdesuPage(verb: verb)
                case .auxiliaries: AuxiliariesPage(verb: verb)
                case .advanced: AdvancedPage(verb: verb)
                case .lessons: VerbLessonsPage(verb: verb)
                }
            }
        }
        .id(verb.id)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                // Wraps the level onto its own line at large text sizes instead of breaking the type name.
                WrappingFlowLayout(spacing: 8) {
                    TypeLabel(verb.type, teGroup: verb.teGroup, emphasis: .header)
                    LevelBadge(level: verb.jlpt, emphasis: .header)
                }
                // The meaning sits beside the headword while it fits, and wraps under it when
                // it is long or the text size is large.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .lastTextBaseline, spacing: 14) {
                        headword
                        // Unwrapped here, so the row only fits when the meaning fits on one line.
                        meaning.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        // Not fixed here, so a long headword can wrap between its units on a
                        // narrow phone at the largest text sizes.
                        headwordText
                        meaning
                    }
                }
            }
            .accessibilityElement(children: .combine)
            JapaneseText(verb.description)
                .font(.body)
                .foregroundStyle(palette.ink)
        }
    }

    private var headword: some View {
        headwordText.fixedSize()
    }

    private var headwordText: some View {
        JapaneseText(units: verb.dictionaryUnits)
            .font(.headword(.largeTitle, scale: 1.5))
            .foregroundStyle(palette.ink)
    }

    private var meaning: some View {
        Text(verb.meaning)
            .font(.title3.weight(.semibold))
            .foregroundStyle(palette.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var actions: some View {
        Button(action: onQuiz) {
            Label("Test this verb", systemImage: "checkmark.circle")
        }
        .buttonStyle(.paper)
    }

    /// The verb's kanji, each a tile that opens its stroke order; nothing without kanji data.
    @ViewBuilder
    private var kanjiSection: some View {
        let characters = kanjiStore?.kanji(in: [verb.kanji ?? ""]) ?? []
        if !characters.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Kanji", systemImage: "character.book.closed.ja") {
                    Text("Tap for stroke order")
                }
                WrappingFlowLayout(spacing: 8) {
                    ForEach(characters, id: \.self) { character in
                        Button {
                            kanjiRequest = KanjiSheetRequest(character: character)
                        } label: {
                            Text(String(character))
                                .font(.headword(.title))
                                .foregroundStyle(palette.ink)
                                .padding(6)
                                .frame(minWidth: 56, minHeight: 56)
                                .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.rule, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(String(character)), stroke order")
                    }
                }
            }
            .kanjiSheet($kanjiRequest)
            .dismissOnLink { kanjiRequest = nil }
        }
    }

    private func notesBox(_ notes: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb")
            JapaneseText(notes).font(.subheadline)
        }
        .foregroundStyle(palette.ink)
        .paperCard(fillsWidth: false)
    }

    /// The first three examples on genkō paper; "See all" opens the sheet with every one.
    @ViewBuilder private var examples: some View {
        if !verb.examples.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Examples") {
                    if verb.examples.count > 3 {
                        Button("See all", action: onExamples)
                            .font(.subheadline.weight(.semibold))
                    }
                }
                VerbExampleCard(examples: Array(verb.examples.prefix(3)), verb: verb)
            }
        }
    }

    private var formGroups: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Forms") {
                    Text("Tap to hear · hold for more")
                        .font(.footnote)
                        .foregroundStyle(palette.muted)
                }
                VerbFormsCard(verb: verb)
            }
            if !MoreRowsCard.rows(for: verb, lessonCount: verbStore.grammarPoints.attachingToVerbs.count).isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader("More forms")
                    MoreRowsCard(verb: verb)
                }
            }
        }
    }
}
