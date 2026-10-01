import SwiftUI

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
    @AppStorage("appearanceMode", store: .appGroup) private var appearanceModeRaw = AppearanceMode.system.rawValue
    @AppStorage("quizQuestionCount", store: .appGroup) private var quizQuestionCount = 10
    @AppStorage("showFurigana", store: .appGroup) private var showFurigana = true

    private var appearanceMode: Binding<AppearanceMode> {
        Binding(
            get: { AppearanceMode(rawValue: appearanceModeRaw) ?? .system },
            set: { appearanceModeRaw = $0.rawValue }
        )
    }

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
            Section("Quiz") {
                Picker("Number of questions", selection: $quizQuestionCount) {
                    ForEach(questionCountOptions, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .frame(minWidth: 320, minHeight: 240)
    }
}
