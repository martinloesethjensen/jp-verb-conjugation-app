import SwiftUI
import VerbKit

extension View {
    /// Reads the theme settings, pins the window appearance when the theme needs it, and gives
    /// everything below its palette through `\.palette`. Applied once, at the root.
    func themedRoot() -> some View {
        modifier(ThemedRoot())
    }
}

struct ThemedRoot: ViewModifier {
    @AppStorage(ThemeChoice.themeKey, store: .appGroup) private var themeRaw = ThemeID.light.rawValue
    @AppStorage(ThemeChoice.matchesSystemKey, store: .appGroup) private var matchesSystem = true
    @AppStorage(ThemeChoice.seasonalKey, store: .appGroup) private var seasonal = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase
    /// Re-read when the app becomes active, so a seasonal theme starts and ends on the right day.
    @State private var today = Date()

    private var choice: ThemeChoice {
        ThemeChoice(theme: ThemeID(rawValue: themeRaw) ?? .light, matchesSystem: matchesSystem, seasonal: seasonal)
    }

    func body(content: Content) -> some View {
        let appearance = choice.appearance(on: today)
        let palette = ThemePalette.resolve(
            choice.effectiveTheme(on: today), appearance: appearance,
            systemScheme: colorScheme, contrast: contrast
        )
        return content
            .environment(\.palette, palette)
            .tint(palette.accent)
            .onChange(of: appearance, initial: true) { _, new in
                ThemeApplier.apply(new)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { today = Date() }
            }
    }
}
