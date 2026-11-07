import VerbKit

extension ThemeID {
    /// The theme's name in the picker and in Settings. Light/Dark and Latte/Coffee are named after
    /// the half that is showing.
    func displayName(isDark: Bool) -> String {
        switch self {
        case .light: isDark ? "Dark" : "Light"
        case .pastel: "Pastel"
        case .sand: "Sand"
        case .matcha: "Matcha"
        case .latte: isDark ? "Coffee" : "Latte"
        case .iceCream: "Ice cream"
        case .northernLights: "Northern lights"
        case .nocturnal: "Nocturnal"
        case .halloween: "Halloween"
        case .christmas: "Christmas"
        }
    }
}

extension AppearanceSetting {
    /// The segment label in Settings › Theme.
    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
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
