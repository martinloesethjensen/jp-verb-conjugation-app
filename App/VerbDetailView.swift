import SwiftUI
import VerbKit

struct VerbDetailView: View {
    let verb: Verb
    var onExamples: () -> Void
    var onQuiz: () -> Void
    @AppStorage(FavouriteVerbs.defaultsKey, store: .appGroup) private var favouritesRaw = ""

    private var isFavourite: Bool { FavouriteVerbs(rawValue: favouritesRaw).contains(verb) }

    private var accent: Color {
        verb.teGroup?.accentColor ?? verb.type.accentColor
    }

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
                    JapaneseText(verb.description)
                        .font(.body)
                    formGroups
                    CommonPhrasesCard(collocations: verb.collocations)
                    VerbPairCard(verb: verb)
                    if let notes = verb.notes {
                        notesBox(notes)
                    }
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
                    Button("Examples", systemImage: "book", action: onExamples)
                    if let jishoURL {
                        Link(destination: jishoURL) {
                            Label("Jisho", systemImage: "link")
                        }
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    ReportProblemButton(item: reportItem)
                }
            }
            .navigationDestination(for: VerbSubPage.self) { page in
                switch page {
                case .potential: PotentialPage(verb: verb)
                case .nDesu: NdesuPage(verb: verb)
                case .auxiliaries: AuxiliariesPage(verb: verb)
                case .advanced: AdvancedPage(verb: verb)
                case .lessons: VerbLessonsPage()
                }
            }
        }
        .id(verb.id)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            TypeLabel(verb.type, teGroup: verb.teGroup, emphasis: .header)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(verb.dict).font(.largeTitle.weight(.heavy)).foregroundStyle(.primary)
                if let kanji = verb.kanji {
                    JapaneseText(kanji).font(.title2).foregroundStyle(.secondary)
                }
            }
            Text(verb.meaning).font(.headline).foregroundStyle(.secondary).italic()
        }
    }

    private var actions: some View {
        Button("Test this verb", systemImage: "gamecontroller", action: onQuiz)
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(accent)
            .foregroundStyle(Color.black.opacity(0.85))
    }

    private func notesBox(_ notes: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb")
            JapaneseText(notes).font(.footnote)
        }
        .paperCard(fillsWidth: false)
    }

    private var formGroups: some View {
        VStack(alignment: .leading, spacing: 16) {
            VerbFormsCard(verb: verb)
            MoreRowsCard(verb: verb)
        }
    }
}
