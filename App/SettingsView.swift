import SwiftUI
import VerbKit
import WidgetKit

enum AppearanceMode: String, CaseIterable, Identifiable, Hashable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

struct SettingsView: View {
    @Environment(VerbStore.self) private var verbStore
    @Environment(QuizHistoryStore.self) private var quizHistory
    @State private var confirmingReset = false
    @AppStorage("appearanceMode", store: .appGroup) private var appearanceModeRaw = AppearanceMode.system.rawValue
    @AppStorage("quizQuestionCount", store: .appGroup) private var quizQuestionCount = 10
    @AppStorage("showFurigana", store: .appGroup) private var showFurigana = true
    @AppStorage("speechSpeed", store: .appGroup) private var speechSpeedRaw = SpeechSpeed.normal.rawValue
    @AppStorage("speakQuizAnswers", store: .appGroup) private var speakQuizAnswers = true
    @AppStorage(LevelSettings.defaultsKey, store: .appGroup) private var hiddenLevelsRaw = ""

    /// The levels present in the verb and grammar data, N5 first.
    private var availableLevels: [JLPTLevel] {
        Set(verbStore.verbs.levels()).union(verbStore.grammarPoints.levels()).sorted()
    }

    private func visibleBinding(for level: JLPTLevel) -> Binding<Bool> {
        Binding(
            get: { LevelSettings(rawValue: hiddenLevelsRaw).isVisible(level) },
            set: { visible in
                var settings = LevelSettings(rawValue: hiddenLevelsRaw)
                if visible { settings.hidden.remove(level) } else { settings.hidden.insert(level) }
                hiddenLevelsRaw = settings.rawValue
            }
        )
    }

    private var appearanceMode: Binding<AppearanceMode> {
        Binding(
            get: { AppearanceMode(rawValue: appearanceModeRaw) ?? .system },
            set: { appearanceModeRaw = $0.rawValue }
        )
    }

    #if os(macOS)
    private let settingsApp = "System Settings"
    #else
    private let settingsApp = "iOS Settings"
    #endif

    private let questionCountOptions = [5, 10, 15, 20, 30]

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Section("Reading") {
                Toggle("Show furigana", isOn: $showFurigana)
            }
            if !availableLevels.isEmpty {
                let settings = LevelSettings(rawValue: hiddenLevelsRaw)
                let datasets = [verbStore.verbs.levels(), verbStore.grammarPoints.levels()]
                Section {
                    ForEach(availableLevels, id: \.self) { level in
                        Toggle(level.displayName, isOn: visibleBinding(for: level))
                            .disabled(settings.isVisible(level) && !settings.canHide(level, amongEach: datasets))
                    }
                } header: {
                    Text("Levels")
                } footer: {
                    Text("Hidden levels are left out of lists, the quiz and the widgets. Search can still look at all levels. At least one level of verbs and of lessons stays visible.")
                }
            }
            Section("Quiz") {
                Picker("Number of questions", selection: $quizQuestionCount) {
                    ForEach(questionCountOptions, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                Button("Reset quiz history", role: .destructive) { confirmingReset = true }
                    .confirmationDialog(
                        "Delete all saved quiz results? This clears your streak and weak spots.",
                        isPresented: $confirmingReset,
                        titleVisibility: .visible
                    ) {
                        Button("Reset", role: .destructive) {
                            quizHistory.reset()
                            WidgetCenter.shared.reloadAllTimelines()
                        }
                        Button("Cancel", role: .cancel) {}
                    }
            }
            Section {
                Toggle("Speak after quiz answers", isOn: $speakQuizAnswers)
                Picker("Speed", selection: $speechSpeedRaw) {
                    ForEach(SpeechSpeed.allCases) { speed in
                        Text(speed.label).tag(speed.rawValue)
                    }
                }
            } header: {
                Text("Audio")
            } footer: {
                Text(Speaker.shared.hasJapaneseVoice
                     ? "Better voices can be downloaded in \(settingsApp) > Accessibility > Spoken Content."
                     : "No Japanese voice is installed, so audio is unavailable. Download one in \(settingsApp) > Accessibility > Spoken Content.")
            }
        }
        .navigationTitle("Settings")
        .frame(minWidth: 320, minHeight: 240)
    }
}
