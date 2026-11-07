import XCTest
@testable import VerbKit

final class ThemeChoiceTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func freshDefaults(_ name: String = #function) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// Defaults as plan 1 left them: a theme and the old "match light and dark" switch.
    private func plan1Defaults(theme: String, matchesSystem: Bool?, _ name: String = #function) -> UserDefaults {
        let defaults = freshDefaults(name + theme)
        defaults.set(theme, forKey: ThemeChoice.themeKey)
        if let matchesSystem { defaults.set(matchesSystem, forKey: ThemeChoice.matchesSystemKey) }
        return defaults
    }

    func testPickerGroupsCoverEveryThemeOnceInOrder() {
        XCTAssertEqual(ThemeID.allCases.count, 10)
        XCTAssertEqual(ThemeGroup.allCases.flatMap(\.themes), ThemeID.allCases)
        XCTAssertEqual(ThemeGroup.cafe.themes, [.matcha, .latte, .iceCream])
    }

    func testIsDarkFollowsSetting() {
        XCTAssertTrue(ThemeChoice(appearance: .automatic).isDark(systemIsDark: true))
        XCTAssertFalse(ThemeChoice(appearance: .automatic).isDark(systemIsDark: false))
        XCTAssertTrue(ThemeChoice(appearance: .dark).isDark(systemIsDark: false))
        XCTAssertFalse(ThemeChoice(appearance: .light).isDark(systemIsDark: true))
    }

    func testSeasonalOverridesInOctoberAndDecember() {
        let choice = ThemeChoice(theme: .matcha, seasonal: true)
        XCTAssertEqual(choice.effectiveTheme(on: date(2026, 10, 1), calendar: utc), .halloween)
        XCTAssertEqual(choice.effectiveTheme(on: date(2026, 12, 31), calendar: utc), .christmas)
    }

    func testSeasonalKeepsTheChosenAppearance() {
        let choice = ThemeChoice(theme: .sand, appearance: .light, seasonal: true)
        XCTAssertEqual(choice.effectiveTheme(on: date(2026, 10, 15), calendar: utc), .halloween)
        XCTAssertFalse(choice.isDark(systemIsDark: true))
    }

    func testSeasonalReturnsChosenThemeInNovember() {
        let choice = ThemeChoice(theme: .matcha, seasonal: true)
        XCTAssertEqual(choice.effectiveTheme(on: date(2026, 11, 1), calendar: utc), .matcha)
        XCTAssertEqual(choice.effectiveTheme(on: date(2027, 1, 1), calendar: utc), .matcha)
    }

    func testSeasonalOffNeverOverrides() {
        XCTAssertEqual(ThemeChoice(theme: .sand).effectiveTheme(on: date(2026, 10, 31), calendar: utc), .sand)
    }

    func testMigratesPreThemeAppearanceMode() {
        let cases: [(String?, ThemeChoice)] = [
            ("system", ThemeChoice(theme: .light, appearance: .automatic)),
            ("light", ThemeChoice(theme: .light, appearance: .light)),
            ("dark", ThemeChoice(theme: .light, appearance: .dark)),
            (nil, ThemeChoice()),
        ]
        for (mode, expected) in cases {
            let defaults = freshDefaults(#function + (mode ?? "nil"))
            if let mode { defaults.set(mode, forKey: ThemeChoice.legacyAppearanceKey) }
            XCTAssertEqual(ThemeChoice.load(from: defaults), expected, "\(mode ?? "nil")")
            XCTAssertEqual(defaults.string(forKey: ThemeChoice.themeKey), expected.theme.rawValue)
            XCTAssertEqual(defaults.string(forKey: ThemeChoice.appearanceKey), expected.appearance.rawValue)
        }
    }

    func testMigratesPlan1PinnedCoffee() {
        let defaults = plan1Defaults(theme: "coffee", matchesSystem: false)
        XCTAssertEqual(ThemeChoice.load(from: defaults), ThemeChoice(theme: .latte, appearance: .dark))
        XCTAssertEqual(defaults.string(forKey: ThemeChoice.themeKey), "latte")
        XCTAssertEqual(defaults.string(forKey: ThemeChoice.appearanceKey), "dark")
        XCTAssertNil(defaults.object(forKey: ThemeChoice.matchesSystemKey))
    }

    func testMigratesPlan1Matching() {
        XCTAssertEqual(ThemeChoice.load(from: plan1Defaults(theme: "dark", matchesSystem: true)),
                       ThemeChoice(theme: .light, appearance: .automatic))
        XCTAssertEqual(ThemeChoice.load(from: plan1Defaults(theme: "sand", matchesSystem: false)),
                       ThemeChoice(theme: .sand, appearance: .light))
        XCTAssertEqual(ThemeChoice.load(from: plan1Defaults(theme: "latte", matchesSystem: nil)),
                       ThemeChoice(theme: .latte, appearance: .automatic))
    }

    func testMigratesForcedThemeToAutomatic() {
        for theme in ["matcha", "nocturnal", "halloween"] {
            XCTAssertEqual(ThemeChoice.load(from: plan1Defaults(theme: theme, matchesSystem: false)).appearance,
                           .automatic, theme)
        }
    }

    func testSaveLoadRoundTripAndUnknownFallsBack() {
        let defaults = freshDefaults()
        let choice = ThemeChoice(theme: .northernLights, appearance: .dark, seasonal: true)
        choice.save(to: defaults)
        XCTAssertEqual(ThemeChoice.load(from: defaults), choice)
        defaults.set("neon", forKey: ThemeChoice.themeKey)
        XCTAssertEqual(ThemeChoice.load(from: defaults).theme, .light)
        defaults.set("sepia", forKey: ThemeChoice.appearanceKey)
        XCTAssertEqual(ThemeChoice.load(from: defaults).appearance, .automatic)
    }
}
