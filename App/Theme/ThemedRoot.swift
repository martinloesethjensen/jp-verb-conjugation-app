import SwiftUI
import VerbKit

extension View {
    /// Reads the theme settings, pins the window appearance when the Appearance setting asks, and gives
    /// everything below its palette through `\.palette`. Applied once, at the root.
    func themedRoot() -> some View {
        modifier(ThemedRoot())
    }
}

struct ThemedRoot: ViewModifier {
    @AppStorage(ThemeChoice.themeKey, store: .appGroup) private var themeRaw = ThemeID.light.rawValue
    @AppStorage(ThemeChoice.appearanceKey, store: .appGroup) private var appearanceRaw = AppearanceSetting.automatic.rawValue
    @AppStorage(ThemeChoice.seasonalKey, store: .appGroup) private var seasonal = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase
    /// Re-read when the app becomes active, so a seasonal theme starts and ends on the right day.
    @State private var today = Date()

    private var choice: ThemeChoice {
        ThemeChoice(
            theme: ThemeID(rawValue: themeRaw) ?? .light,
            appearance: AppearanceSetting(rawValue: appearanceRaw) ?? .automatic,
            seasonal: seasonal
        )
    }

    func body(content: Content) -> some View {
        let palette = ThemePalette.resolve(
            choice.effectiveTheme(on: today),
            isDark: choice.isDark(systemIsDark: colorScheme == .dark),
            contrast: contrast
        )
        return content
            .environment(\.palette, palette)
            // Text buttons, links and the selected tab use `button` (≥ 4.5:1 on paper and card in
            // every palette); the lighter `accent` only fills switches, where it is not text.
            .tint(palette.button)
            #if os(iOS)
            .toggleStyle(SwitchToggleStyle(tint: palette.accent))
            #endif
            .onChange(of: choice.appearance, initial: true) { _, new in
                ThemeApplier.apply(new)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { today = Date() }
            }
    }
}
