import Foundation

/// The app's ten themes, each with a light and a dark half. `allCases` is the picker order; the
/// names shown to people live in App (Light/Dark and Latte/Coffee are named after the half showing).
public enum ThemeID: String, CaseIterable, Sendable {
    case light, pastel, sand
    case matcha, latte, iceCream
    case northernLights, nocturnal
    case halloween, christmas

    /// The picker section the theme sits in.
    public var group: ThemeGroup {
        switch self {
        case .light, .pastel, .sand: .everyday
        case .matcha, .latte, .iceCream: .cafe
        case .northernLights, .nocturnal: .night
        case .halloween, .christmas: .seasonal
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

/// Settings › Theme › Appearance: follow iOS, or keep the app light or dark. The theme itself never
/// forces an appearance.
public enum AppearanceSetting: String, CaseIterable, Sendable {
    case automatic, light, dark
}
