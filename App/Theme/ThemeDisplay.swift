import VerbKit

extension ThemeID {
    /// The theme's name in the picker and in Settings.
    var displayName: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .pastel: "Pastel"
        case .sand: "Sand"
        case .matcha: "Matcha"
        case .latte: "Latte"
        case .coffee: "Coffee"
        case .iceCream: "Ice cream"
        case .northernLights: "Northern lights"
        case .nocturnal: "Nocturnal"
        case .halloween: "Halloween"
        case .christmas: "Christmas"
        }
    }
}

extension ThemeGroup {
    /// The picker section heading.
    var title: String {
        switch self {
        case .everyday: "Everyday"
        case .cafe: "Café"
        case .night: "Night"
        case .seasonal: "Seasonal"
        }
    }
}
