import Foundation

/// An icon to switch to: an alternate icon's name, or nil for the primary (Light · Dark) icon.
public struct IconChange: Equatable, Sendable {
    public let name: String?
    public init(name: String?) { self.name = name }
}

/// When the Home Screen icon follows the theme (canvas board "App icons per palette"). iOS shows
/// an alert on every change and only while the app is open, so the icon changes only on a tap:
/// picking a theme with "App icon matches theme" on, or flipping that switch. A seasonal
/// override is never passed here, so the season never changes the icon.
public enum AppIconMatching {
    /// The App Group key of "App icon matches theme" (off by default).
    public static let defaultsKey = "appIconMatchesTheme"

    /// The alternate icon set for a theme; Light uses the primary icon.
    public static func iconName(for theme: ThemeID) -> String? {
        theme == .light ? nil : "AppIcon-\(theme.rawValue)"
    }

    /// Someone tapped a theme. `current` is the icon showing now (`alternateIconName`).
    public static func change(tapped theme: ThemeID, matches: Bool, current: String?) -> IconChange? {
        guard matches else { return nil }
        return changing(current, to: iconName(for: theme))
    }

    /// Someone flipped the switch: on shows the chosen theme's icon, off the primary icon.
    public static func change(switchedOn: Bool, chosen: ThemeID, current: String?) -> IconChange? {
        changing(current, to: switchedOn ? iconName(for: chosen) : nil)
    }

    private static func changing(_ current: String?, to name: String?) -> IconChange? {
        current == name ? nil : IconChange(name: name)
    }
}
