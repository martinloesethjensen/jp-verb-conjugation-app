import Foundation

/// The person's theme settings: the chosen theme, the Appearance setting, and whether the seasonal
/// themes take over in October and December. Stored as three App Group keys so the widgets read
/// the same choice.
public struct ThemeChoice: Equatable, Sendable {
    public static let themeKey = "theme"
    public static let appearanceKey = "themeAppearance"
    public static let seasonalKey = "seasonalThemes"
    /// Plan 1's "Match light and dark to iOS" switch, read once by the migration.
    public static let matchesSystemKey = "themeMatchesSystem"
    /// The pre-theme "Appearance" setting (system, light or dark), read once by the migration.
    public static let legacyAppearanceKey = "appearanceMode"

    public var theme: ThemeID
    public var appearance: AppearanceSetting
    public var seasonal: Bool

    public init(theme: ThemeID = .light, appearance: AppearanceSetting = .automatic, seasonal: Bool = false) {
        self.theme = theme
        self.appearance = appearance
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

    /// Whether the dark half shows: the system's appearance on Automatic, otherwise the setting.
    public func isDark(systemIsDark: Bool) -> Bool {
        switch appearance {
        case .automatic: systemIsDark
        case .light: false
        case .dark: true
        }
    }

    /// Reads the stored choice, migrating older settings the first time and saving the result,
    /// so later reads, `@AppStorage` included, see the current keys.
    public static func load(from defaults: UserDefaults) -> ThemeChoice {
        guard let raw = defaults.string(forKey: themeKey) else {
            let choice = migrated(appearanceMode: defaults.string(forKey: legacyAppearanceKey))
            choice.save(to: defaults)
            return choice
        }
        guard let appearanceRaw = defaults.string(forKey: appearanceKey) else {
            let matchesSystem = defaults.object(forKey: matchesSystemKey) as? Bool ?? true
            var choice = migrated(plan1Theme: raw, matchesSystem: matchesSystem)
            choice.seasonal = defaults.bool(forKey: seasonalKey)
            choice.save(to: defaults)
            defaults.removeObject(forKey: matchesSystemKey)
            return choice
        }
        return ThemeChoice(
            theme: ThemeID(rawValue: raw) ?? .light,
            appearance: AppearanceSetting(rawValue: appearanceRaw) ?? .automatic,
            seasonal: defaults.bool(forKey: seasonalKey)
        )
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(theme.rawValue, forKey: Self.themeKey)
        defaults.set(appearance.rawValue, forKey: Self.appearanceKey)
        defaults.set(seasonal, forKey: Self.seasonalKey)
    }

    /// The pre-theme Appearance setting: everyone lands on Light, pinned as before.
    private static func migrated(appearanceMode: String?) -> ThemeChoice {
        switch appearanceMode {
        case "light": ThemeChoice(theme: .light, appearance: .light)
        case "dark": ThemeChoice(theme: .light, appearance: .dark)
        default: ThemeChoice()
        }
    }

    /// Plan 1's twelve themes and matching switch. Dark and Coffee fold into Light and Latte;
    /// a pinned pair or variant keeps the half that was showing; the themes that used to force
    /// an appearance become Automatic.
    private static func migrated(plan1Theme raw: String, matchesSystem: Bool) -> ThemeChoice {
        let theme: ThemeID = switch raw {
        case "dark": .light
        case "coffee": .latte
        default: ThemeID(rawValue: raw) ?? .light
        }
        guard !matchesSystem else { return ThemeChoice(theme: theme, appearance: .automatic) }
        let appearance: AppearanceSetting = switch raw {
        case "dark", "coffee": .dark
        case "light", "latte", "pastel", "sand": .light
        default: .automatic
        }
        return ThemeChoice(theme: theme, appearance: appearance)
    }
}
