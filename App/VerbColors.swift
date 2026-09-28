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
