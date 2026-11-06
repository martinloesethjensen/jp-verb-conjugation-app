import SwiftUI
import VerbKit

/// The colours one theme paints with. Every screen and widget reads them from `\.palette`; the
/// values are in `ThemePalettes.swift`, copied from the paper-and-ink spec's palette table.
/// Compiled into the widget target too (see `project.yml`).
struct ThemePalette: Equatable {
    /// The screen ground.
    let paper: Color
    /// Cards and list groups.
    let card: Color
    /// Text, selection and the one strong colour.
    let ink: Color
    /// Secondary text.
    let muted: Color
    /// Hairlines and card outlines.
    let rule: Color
    /// Wrong answers, corrections and destructive actions only.
    let mark: Color
    let markSoft: Color
    /// Correct answers.
    let good: Color
    let goodSoft: Color
    /// The primary button's fill and its label.
    let button: Color
    let onButton: Color
    /// Switches and the selected tab.
    let accent: Color
    /// Pastel and Ice cream fill the verb-type pill with the type colour instead of a dot.
    let fillsTypePills: Bool

    /// Increase Contrast: secondary text halfway to ink, hairlines halfway to secondary text.
    func increasedContrast() -> ThemePalette {
        ThemePalette(
            paper: paper, card: card, ink: ink,
            muted: muted.mix(with: ink, by: 0.5),
            rule: rule.mix(with: muted, by: 0.5),
            mark: mark, markSoft: markSoft, good: good, goodSoft: goodSoft,
            button: button, onButton: onButton, accent: accent, fillsTypePills: fillsTypePills
        )
    }

    /// The palette for `theme`. `systemScheme` decides only when the theme follows the system.
    static func resolve(
        _ theme: ThemeID, appearance: ThemeAppearance,
        systemScheme: ColorScheme, contrast: ColorSchemeContrast
    ) -> ThemePalette {
        let isDark = switch appearance {
        case .followSystem: systemScheme == .dark
        case .light: false
        case .dark: true
        }
        let palette: ThemePalette = switch theme {
        case .light, .dark: isDark ? .dark : .light
        case .latte, .coffee: isDark ? .coffee : .latte
        case .pastel: isDark ? .pastelDark : .pastel
        case .sand: isDark ? .sandDark : .sand
        case .matcha: .matcha
        case .iceCream: .iceCream
        case .northernLights: .northernLights
        case .nocturnal: .nocturnal
        case .halloween: .halloween
        case .christmas: .christmas
        }
        return contrast == .increased ? palette.increasedContrast() : palette
    }
}

extension EnvironmentValues {
    /// The current theme's colours, set once at the root by `themedRoot()`.
    @Entry var palette: ThemePalette = .light
}

extension Color {
    /// An sRGB colour from a 0xRRGGBB literal.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
