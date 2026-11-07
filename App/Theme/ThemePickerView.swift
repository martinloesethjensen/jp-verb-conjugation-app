import SwiftUI
import VerbKit
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Settings › Theme: a live preview in the current palette, the Appearance control, the ten themes
/// in their four groups (each swatch shows the half that is showing), and the seasonal switch.
/// Choosing repaints the whole app and the widgets.
struct ThemePickerView: View {
    @AppStorage(ThemeChoice.themeKey, store: .appGroup) private var themeRaw = ThemeID.light.rawValue
    @AppStorage(ThemeChoice.appearanceKey, store: .appGroup) private var appearanceRaw = AppearanceSetting.automatic.rawValue
    @AppStorage(ThemeChoice.seasonalKey, store: .appGroup) private var seasonal = false
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    private var selected: ThemeID { ThemeID(rawValue: themeRaw) ?? .light }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                preview
                appearancePicker
                ForEach(ThemeGroup.allCases, id: \.self) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.title.uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.muted)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), alignment: .top)], alignment: .leading, spacing: 14) {
                            ForEach(group.themes, id: \.self) { theme in
                                swatch(theme)
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Seasonal themes", isOn: changing($seasonal))
                        .padding(.vertical, 10)
                        .paperCard()
                    Text("Seasonal themes switch on by themselves in October and December, then go back.")
                        .font(.footnote)
                        .foregroundStyle(palette.muted)
                }
            }
            .padding()
        }
        .paperBackground()
        .navigationTitle("Theme")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// The window override puts the scheme on the pinned half, so this is the half that shows.
    private var isDark: Bool { colorScheme == .dark }

    private var appearancePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("APPEARANCE")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.muted)
            Picker("Appearance", selection: Binding(
                get: { AppearanceSetting(rawValue: appearanceRaw) ?? .automatic },
                set: { appearanceRaw = $0.rawValue; reloadWidgets() }
            )) {
                ForEach(AppearanceSetting.allCases, id: \.self) { setting in
                    Text(setting.title).tag(setting)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            #if os(macOS)
            Text("Automatic follows your Mac. Light and Dark keep the app that way.")
                .font(.footnote)
                .foregroundStyle(palette.muted)
            #else
            Text("Automatic follows your iPhone. Light and Dark keep the app that way.")
                .font(.footnote)
                .foregroundStyle(palette.muted)
            #endif
        }
    }

    private var preview: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                TypeLabel(.ru)
                JapaneseText("食べる")
                    .font(.headword(.largeTitle))
                    .foregroundStyle(palette.ink)
                Button("Test this verb") {}
                    .buttonStyle(.paper)
            }
            VStack(spacing: 6) {
                QuizChoiceButton(choice: "たべって", index: 0, isCorrect: false, isSelected: true, isAnswered: true) {}
                QuizChoiceButton(choice: "たべて", index: 1, isCorrect: true, isSelected: false, isAnswered: true) {}
            }
            .frame(maxWidth: 140)
        }
        .paperCard(cornerRadius: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the \(selected.displayName(isDark: isDark)) theme")
    }

    private func swatch(_ theme: ThemeID) -> some View {
        let face = ThemePalette.resolve(theme, isDark: isDark, contrast: .standard)
        let isSelected = theme == selected
        return Button {
            themeRaw = theme.rawValue
            reloadWidgets()
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    face.paper
                    face.ink.frame(height: 22).frame(maxHeight: .infinity, alignment: .bottom)
                    Circle().fill(face.mark).frame(width: 8, height: 8).padding(9)
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(face.rule, lineWidth: 1))
                .padding(3)
                .overlay(Circle().strokeBorder(isSelected ? palette.ink : .clear, lineWidth: 3))
                Text(theme.displayName(isDark: isDark))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let month = seasonMonth(theme) {
                    Text(month).font(.caption2).foregroundStyle(palette.muted)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func seasonMonth(_ theme: ThemeID) -> String? {
        switch theme {
        case .halloween: "October"
        case .christmas: "December"
        default: nil
        }
    }

    /// Writes through the binding, then repaints the widgets.
    private func changing(_ binding: Binding<Bool>) -> Binding<Bool> {
        Binding(get: { binding.wrappedValue }, set: { binding.wrappedValue = $0; reloadWidgets() })
    }

    private func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
