import SwiftUI
import VerbKit

extension VerbType {
    /// Echoes the original web app's per-type palette (getTypeColors).
    var accentColor: Color {
        switch self {
        case .irregular: return Color(red: 0.973, green: 0.443, blue: 0.400)
        case .ru: return Color(red: 0.486, green: 0.831, blue: 0.992)
        case .u: return Color(red: 0.992, green: 0.792, blue: 0.243)
        }
    }
}

extension TeGroup {
    /// Echoes the original web app's per-て-form-group palette (TE_GROUPS).
    var accentColor: Color {
        switch self {
        case .tte: return Color(red: 0.976, green: 0.451, blue: 0.086)
        case .nde: return Color(red: 0.176, green: 0.831, blue: 0.749)
        case .ite: return Color(red: 0.655, green: 0.545, blue: 0.980)
        case .ide: return Color(red: 0.506, green: 0.549, blue: 0.973)
        case .shite: return Color(red: 0.984, green: 0.447, blue: 0.522)
        }
    }
}

extension View {
    /// Colour-coded Liquid Glass capsule. The accent colours are all light pastels, so the
    /// label is fixed near-black (never the accent itself, which vanishes on its own tint).
    func accentPill(_ accent: Color) -> some View {
        foregroundStyle(Color.black.opacity(0.85))
            .glassEffect(.regular.tint(accent.opacity(0.85)), in: Capsule())
    }
}
