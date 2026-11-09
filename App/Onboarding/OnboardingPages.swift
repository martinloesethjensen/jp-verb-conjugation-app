import SwiftUI
import VerbKit

/// Page 1: what the app is.
struct WelcomePage: View {
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            JapaneseText(units: [TextUnit(text: "活用", reading: "かつよう")])
                .font(.headword(.largeTitle, scale: 2.1))
                .foregroundStyle(palette.ink)
                .accessibilityHidden(true)
            Text("Verb Table")
                .font(.title.bold())
                .foregroundStyle(palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text("Conjugate Japanese verbs, read grammar lessons and counters, and keep a word bank of your own. Everything works offline.")
                .font(.body)
                .foregroundStyle(palette.muted)
            Text("Four quick choices. All of them can be changed later.")
                .font(.footnote)
                .foregroundStyle(palette.muted)
        }
    }
}

/// A page's title and body.
struct OnboardingHeading: View {
    let title: String
    let detail: String
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title.bold()).foregroundStyle(palette.ink).accessibilityAddTraits(.isHeader)
            Text(detail).font(.body).foregroundStyle(palette.muted)
        }
    }
}

/// Page 2: the levels studied. The last picked level cannot be unpicked.
struct LevelsPage: View {
    @Binding var choices: OnboardingChoices
    @Environment(\.palette) private var palette

    private func hint(_ level: JLPTLevel) -> String {
        switch level {
        case .n5: "Beginner"
        case .n4: "Elementary"
        case .n3: "Intermediate"
        case .n2: "Upper intermediate"
        case .n1: "Advanced"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingHeading(title: "Which levels are you studying?",
                              detail: "Lists, quizzes and widgets show only these. Search still finds everything.")
            VStack(spacing: 10) {
                ForEach(JLPTLevel.allCases, id: \.self) { level in
                    let picked = choices.levels.contains(level)
                    OnboardingOption(isSelected: picked, action: { choices.toggle(level) }) {
                        HStack(spacing: 12) {
                            Text(level.rawValue).font(.headline).foregroundStyle(palette.ink)
                            Text(hint(level)).font(.subheadline).foregroundStyle(palette.muted)
                            Spacer(minLength: 0)
                            ZStack {
                                if picked {
                                    Circle().fill(palette.button)
                                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(palette.onButton)
                                } else {
                                    Circle().strokeBorder(palette.rule, lineWidth: 1.5)
                                }
                            }
                            .frame(width: 24, height: 24)
                            .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
    }
}

/// Page 3: furigana on or off, each shown on the same sentence.
struct FuriganaPage: View {
    @Binding var choices: OnboardingChoices
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingHeading(title: "Show furigana?",
                              detail: "Readings above every kanji. Turn them off once you can read without them.")
            ForEach([true, false], id: \.self) { on in
                OnboardingOption(isSelected: choices.furigana == on, action: { choices.furigana = on }) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(on ? "ON" : "OFF").font(.caption.weight(.semibold)).foregroundStyle(palette.muted)
                        JapaneseText("毎朝パンを食べます。")
                            .font(.sentence(.title2))
                            .foregroundStyle(palette.ink)
                            .environment(\.furiganaEnabled, on)
                    }
                    .padding(.vertical, 6)
                }
                .accessibilityLabel(on ? "Furigana on" : "Furigana off")
            }
        }
    }
}

/// Page 4: six themes; choosing one repaints the flow at once.
struct ThemePage: View {
    @Binding var choices: OnboardingChoices
    @AppStorage(ThemeChoice.themeKey, store: .appGroup) private var themeRaw = ThemeID.light.rawValue

    static let themes: [ThemeID] = [.light, .pastel, .matcha, .latte, .northernLights, .nocturnal]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingHeading(title: "Pick a look",
                              detail: "You can change it any time. There are more in Settings, including seasonal ones.")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: 3), spacing: 18) {
                ForEach(Self.themes, id: \.self) { theme in
                    ThemeSwatch(theme: theme, isSelected: choices.theme == theme, diameter: 66) {
                        choices.theme = theme
                        themeRaw = theme.rawValue
                    }
                }
            }
        }
    }
}

/// Page 5: the first verb to open, and a summary of the choices.
struct FirstVerbPage: View {
    let choices: OnboardingChoices
    let firstVerb: Verb?
    let datasets: [Set<JLPTLevel>]
    let onOpenVerb: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    private var summary: String {
        let visible = LevelSettings.studying(choices.levels, amongEach: datasets)
        let levels = JLPTLevel.allCases.filter { visible.isVisible($0) }.map(\.rawValue).joined(separator: ", ")
        return [levels, choices.furigana ? "furigana on" : "furigana off",
                choices.theme.displayName(isDark: colorScheme == .dark)].joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingHeading(title: "You’re set", detail: "Start with a verb everyone needs on day one.")
            if let verb = firstVerb {
                Button(action: onOpenVerb) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            JapaneseText(units: verb.dictionaryUnits)
                                .font(.headword(.largeTitle))
                                .foregroundStyle(palette.ink)
                                .environment(\.furiganaEnabled, choices.furigana)
                            Text([verb.meaning, verb.type.typeLabel, verb.jlpt?.rawValue].compactMap { $0 }.joined(separator: " · "))
                                .font(.subheadline)
                                .foregroundStyle(palette.muted)
                        }
                        Spacer(minLength: 0)
                        RowChevron()
                    }
                    .paperCard(cornerRadius: 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text(summary)
                .font(.footnote)
                .foregroundStyle(palette.muted)
        }
    }
}
