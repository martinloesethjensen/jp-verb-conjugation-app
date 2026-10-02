import SwiftUI
import VerbKit

struct VerbDetailView: View {
    let verb: Verb
    var onExamples: () -> Void
    var onQuiz: () -> Void

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
                    if let notes = verb.notes {
                        notesBox(notes)
                    }
                    JapaneseText(verb.description)
                        .font(.body)
                    formGroups
                }
                .padding()
            }
            .navigationTitle(verb.dict)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verb.label)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .accentPill(verb.type.accentColor)
                if let teGroup = verb.teGroup {
                    Text(teGroup.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Circle().fill(teGroup.accentColor).frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(verb.dict).font(.largeTitle.weight(.heavy)).foregroundStyle(.primary)
                if let kanji = verb.kanji {
                    JapaneseText(kanji).font(.title2).foregroundStyle(.secondary)
                }
                SpeakButton(text: verb.jishoQuery)
            }
            Text(verb.meaning).font(.headline).foregroundStyle(.secondary).italic()
        }
    }

    private var actions: some View {
        Button("Test this verb", systemImage: "gamecontroller", action: onQuiz)
            .buttonStyle(.glassProminent)
            .controlSize(.small)
            .tint(accent)
            .foregroundStyle(Color.black.opacity(0.85))
    }

    private func notesBox(_ notes: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb")
            JapaneseText(notes).font(.footnote)
        }
        .padding(12)
        .glassEffect(in: RoundedRectangle(cornerRadius: 10))
    }

    private var formGroups: some View {
        VStack(alignment: .leading, spacing: 16) {
            VerbFormsCard(verb: verb)
            MoreRowsCard(verb: verb)
        }
    }
}
