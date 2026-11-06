import Foundation

/// The person's theme settings: the chosen theme, whether light and dark follow iOS, and whether
/// the seasonal themes take over in October and December. Stored as three App Group keys so the
/// widgets read the same choice.
public struct ThemeChoice: Equatable, Sendable {
    public static let themeKey = "theme"
    public static let matchesSystemKey = "themeMatchesSystem"
    public static let seasonalKey = "seasonalThemes"
    /// The pre-theme "Appearance" setting (system, light or dark), migrated once.
    public static let legacyAppearanceKey = "appearanceMode"

    public var theme: ThemeID
    public var matchesSystem: Bool
    public var seasonal: Bool

    public init(theme: ThemeID = .light, matchesSystem: Bool = true, seasonal: Bool = false) {
        self.theme = theme
        self.matchesSystem = matchesSystem
        self.seasonal = seasonal
    }

    /// The theme shown on `date`: Halloween in October and Christmas in December when seasonal
    /// themes are on, otherwise the chosen theme.
    public func effectiveTheme(on date: Date, calendar: Calendar = .current) -> ThemeID {
        guard seasonal else { return theme }
        switch calendar.component(.month, from: date) {
        case 10: return .halloween
        case 12: return .christmas
        default: return theme
        }
    }

    /// The window appearance for the theme shown on `date`.
    public func appearance(on date: Date, calendar: Calendar = .current) -> ThemeAppearance {
        effectiveTheme(on: date, calendar: calendar).appearance(matchingSystem: matchesSystem)
    }

    /// The choice after the person taps `theme` in the picker. Picking the half of a light/dark
    /// pair (Light/Dark, Latte/Coffee) that the system is not showing turns matching off, so the
    /// tap visibly does what it says; every other pick keeps the switches as they are.
    public func choosing(_ theme: ThemeID, systemIsDark: Bool) -> ThemeChoice {
        var next = self
        next.theme = theme
        if matchesSystem, let wantsDark = theme.pairedHalfIsDark, wantsDark != systemIsDark {
            next.matchesSystem = false
        }
        return next
    }

    /// The choice that keeps what an existing "Appearance" setting looked like.
    public static func migrated(appearanceMode: String?) -> ThemeChoice {
        switch appearanceMode {
        case "light": ThemeChoice(theme: .light, matchesSystem: false)
        case "dark": ThemeChoice(theme: .dark, matchesSystem: false)
        default: ThemeChoice()
        }
    }

    /// Reads the stored choice. The first time (no theme key yet) it migrates the old Appearance
    /// setting and saves the result, so later reads, `@AppStorage` included, see the theme keys.
    public static func load(from defaults: UserDefaults) -> ThemeChoice {
        guard let raw = defaults.string(forKey: themeKey) else {
            let choice = migrated(appearanceMode: defaults.string(forKey: legacyAppearanceKey))
            choice.save(to: defaults)
            return choice
        }
        return ThemeChoice(
            theme: ThemeID(rawValue: raw) ?? .light,
            matchesSystem: defaults.object(forKey: matchesSystemKey) as? Bool ?? true,
            seasonal: defaults.bool(forKey: seasonalKey)
        )
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(theme.rawValue, forKey: Self.themeKey)
        defaults.set(matchesSystem, forKey: Self.matchesSystemKey)
        defaults.set(seasonal, forKey: Self.seasonalKey)
    }
}
