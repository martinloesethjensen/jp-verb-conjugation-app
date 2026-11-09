import SwiftUI
import VerbKit

/// A theme's swatch: its paper with an ink band and a mark dot, drawn in the half that is showing,
/// a 3 pt ink ring when selected (and the `.isSelected` trait), and the theme's name under it.
/// Settings › Theme and onboarding use it.
struct ThemeSwatch: View {
    let theme: ThemeID
    let isSelected: Bool
    var diameter: CGFloat = 50
    var caption: String?
    let action: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        let face = ThemePalette.resolve(theme, isDark: isDark, contrast: .standard)
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    face.paper
                    face.ink.frame(height: diameter * 0.44).frame(maxHeight: .infinity, alignment: .bottom)
                    Circle().fill(face.mark).frame(width: diameter * 0.16, height: diameter * 0.16).padding(diameter * 0.18)
                }
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(face.rule, lineWidth: 1))
                .padding(3)
                .overlay(Circle().strokeBorder(isSelected ? palette.ink : .clear, lineWidth: 3))
                Text(theme.displayName(isDark: isDark))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let caption {
                    Text(caption).font(.caption2).foregroundStyle(palette.muted)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
