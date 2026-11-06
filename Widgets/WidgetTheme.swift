import SwiftUI
import VerbKit

/// What the three home screen widgets share: the app theme's palette, the text
/// shown before the first sync, and the JLPT accent palette.
enum WidgetTheme {
    /// The palette of the theme the app shows on `date`, read from the shared App Group.
    static func palette(on date: Date, scheme: ColorScheme, contrast: ColorSchemeContrast) -> ThemePalette {
        let choice = ThemeChoice.load(from: .verbKitAppGroup)
        return ThemePalette.resolve(
            choice.effectiveTheme(on: date), appearance: choice.appearance(on: date),
            systemScheme: scheme, contrast: contrast
        )
    }

    /// For tinted and clear home screens: no paper, and the system's own text colours.
    static func plain(_ palette: ThemePalette) -> ThemePalette {
        ThemePalette(
            paper: .clear, card: .clear, ink: .primary, muted: .secondary, rule: .secondary,
            mark: palette.mark, markSoft: .clear, good: palette.good, goodSoft: .clear,
            button: .primary, onButton: .clear, accent: .primary, fillsTypePills: false
        )
    }

    /// The theme's paper on the home screen; transparent on the lock screen and inline
    /// families, where the system draws its own surface.
    @ViewBuilder
    static func background(isHome: Bool, palette: ThemePalette) -> some View {
        if isHome {
            palette.paper
        } else {
            Color.clear
        }
    }

    /// The pastel that marks a grammar point's level.
    static func accent(for level: JLPTLevel?) -> Color {
        switch level {
        case .n5: Color(red: 0.176, green: 0.831, blue: 0.749)
        case .n4: Color(red: 0.486, green: 0.831, blue: 0.992)
        case .n3: Color(red: 0.655, green: 0.545, blue: 0.980)
        case .n2: Color(red: 0.992, green: 0.792, blue: 0.243)
        case .n1: Color(red: 0.973, green: 0.443, blue: 0.400)
        case nil: .secondary
        }
    }
}

/// "Open Verb Table to load verbs" and the like, shown until the first sync.
/// Inline (above the clock) can only draw plain text.
struct WidgetEmptyState: View {
    @Environment(\.palette) private var palette
    let message: String
    var isHome: Bool
    var isInline: Bool = false

    var body: some View {
        if isInline {
            Text(message)
        } else {
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(isHome ? palette.ink : .primary)
        }
    }
}

extension View {
    /// Gives a widget's view the current theme's palette, or the plain one on a tinted or
    /// clear home screen.
    func widgetThemed(date: Date) -> some View {
        modifier(WidgetThemed(date: date))
    }
}

private struct WidgetThemed: ViewModifier {
    let date: Date
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.widgetRenderingMode) private var renderingMode

    func body(content: Content) -> some View {
        let palette = WidgetTheme.palette(on: date, scheme: scheme, contrast: contrast)
        content.environment(\.palette, renderingMode == .fullColor ? palette : WidgetTheme.plain(palette))
    }
}
