import Foundation

/// The app's twelve themes. `allCases` is the picker order; the names shown to people live in App.
public enum ThemeID: String, CaseIterable, Sendable {
    case light, dark, pastel, sand
    case matcha, latte, coffee, iceCream
    case northernLights, nocturnal
    case halloween, christmas

    /// The picker section the theme sits in.
    public var group: ThemeGroup {
        switch self {
        case .light, .dark, .pastel, .sand: .everyday
        case .matcha, .latte, .coffee, .iceCream: .cafe
        case .northernLights, .nocturnal: .night
        case .halloween, .christmas: .seasonal
        }
    }

    /// Whether the window follows iOS or is pinned light or dark. Paired themes (Light/Dark,
    /// Latte/Coffee) and themes with a dark variant (Pastel, Sand) follow the system while matching
    /// is on; light-only and dark-only themes always pin their appearance.
    public func appearance(matchingSystem: Bool) -> ThemeAppearance {
        switch self {
        case .light, .pastel, .sand, .latte: matchingSystem ? .followSystem : .light
        case .dark, .coffee: matchingSystem ? .followSystem : .dark
        case .matcha, .iceCream, .christmas: .light
        case .northernLights, .nocturnal, .halloween: .dark
        }
    }
}

extension ThemeID {
    /// For the halves of a light/dark pair, whether this half is the dark one; nil otherwise.
    var pairedHalfIsDark: Bool? {
        switch self {
        case .light, .latte: false
        case .dark, .coffee: true
        default: nil
        }
    }
}

/// The four sections of the theme picker.
public enum ThemeGroup: String, CaseIterable, Sendable {
    case everyday, cafe, night, seasonal

    /// This group's themes, in picker order.
    public var themes: [ThemeID] {
        ThemeID.allCases.filter { $0.group == self }
    }
}

/// How the window's light/dark appearance is set for a theme.
public enum ThemeAppearance: Sendable, Equatable {
    case followSystem, light, dark
}
