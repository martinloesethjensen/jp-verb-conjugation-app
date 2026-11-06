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

    func testPickerGroupsCoverEveryThemeOnceInOrder() {
        XCTAssertEqual(ThemeGroup.allCases.flatMap(\.themes), ThemeID.allCases)
        XCTAssertEqual(ThemeGroup.cafe.themes, [.matcha, .latte, .coffee, .iceCream])
    }

    func testAppearanceTable() {
        XCTAssertEqual(ThemeID.light.appearance(matchingSystem: true), .followSystem)
        XCTAssertEqual(ThemeID.light.appearance(matchingSystem: false), .light)
        XCTAssertEqual(ThemeID.coffee.appearance(matchingSystem: false), .dark)
        XCTAssertEqual(ThemeID.sand.appearance(matchingSystem: true), .followSystem)
        XCTAssertEqual(ThemeID.matcha.appearance(matchingSystem: true), .light)
        XCTAssertEqual(ThemeID.nocturnal.appearance(matchingSystem: true), .dark)
        XCTAssertEqual(ThemeID.christmas.appearance(matchingSystem: true), .light)
    }

    func testSeasonalOverridesInOctoberAndDecember() {
        let choice = ThemeChoice(theme: .matcha, seasonal: true)
        XCTAssertEqual(choice.effectiveTheme(on: date(2026, 10, 1), calendar: utc), .halloween)
        XCTAssertEqual(choice.effectiveTheme(on: date(2026, 12, 31), calendar: utc), .christmas)
        XCTAssertEqual(choice.appearance(on: date(2026, 10, 15), calendar: utc), .dark)
    }

    func testSeasonalReturnsChosenThemeInNovember() {
        let choice = ThemeChoice(theme: .matcha, seasonal: true)
        XCTAssertEqual(choice.effectiveTheme(on: date(2026, 11, 1), calendar: utc), .matcha)
        XCTAssertEqual(choice.effectiveTheme(on: date(2027, 1, 1), calendar: utc), .matcha)
    }

    func testSeasonalOffNeverOverrides() {
        XCTAssertEqual(ThemeChoice(theme: .sand).effectiveTheme(on: date(2026, 10, 31), calendar: utc), .sand)
    }

    func testMigratesSystemLightAndDark() {
        XCTAssertEqual(ThemeChoice.migrated(appearanceMode: "system"), ThemeChoice(theme: .light, matchesSystem: true))
        XCTAssertEqual(ThemeChoice.migrated(appearanceMode: "light"), ThemeChoice(theme: .light, matchesSystem: false))
        XCTAssertEqual(ThemeChoice.migrated(appearanceMode: nil), ThemeChoice())
    }

    func testMigratesDarkAppearance() {
        let defaults = freshDefaults()
        defaults.set("dark", forKey: ThemeChoice.legacyAppearanceKey)
        XCTAssertEqual(ThemeChoice.load(from: defaults), ThemeChoice(theme: .dark, matchesSystem: false))
        XCTAssertEqual(defaults.string(forKey: ThemeChoice.themeKey), "dark")
    }

    func testChoosingTheOtherHalfOfAPairPinsIt() {
        // Matching on, light phone: picking Dark must make the app dark, so matching turns off.
        let picked = ThemeChoice(theme: .light).choosing(.dark, systemIsDark: false)
        XCTAssertEqual(picked, ThemeChoice(theme: .dark, matchesSystem: false))
        XCTAssertEqual(ThemeChoice(theme: .latte).choosing(.coffee, systemIsDark: false).matchesSystem, false)
        XCTAssertEqual(ThemeChoice(theme: .coffee).choosing(.latte, systemIsDark: true).matchesSystem, false)
    }

    func testChoosingTheMatchingHalfKeepsFollowingTheSystem() {
        XCTAssertEqual(ThemeChoice(theme: .light).choosing(.dark, systemIsDark: true), ThemeChoice(theme: .dark, matchesSystem: true))
        XCTAssertEqual(ThemeChoice(theme: .dark).choosing(.light, systemIsDark: false).matchesSystem, true)
    }

    func testChoosingAnUnpairedThemeLeavesMatchingAndSeasonalAlone() {
        let choice = ThemeChoice(theme: .light, matchesSystem: true, seasonal: true)
        XCTAssertEqual(choice.choosing(.sand, systemIsDark: false), ThemeChoice(theme: .sand, matchesSystem: true, seasonal: true))
        XCTAssertEqual(choice.choosing(.nocturnal, systemIsDark: false).matchesSystem, true)
    }

    func testSaveLoadRoundTripAndUnknownFallsBack() {
        let defaults = freshDefaults()
        let choice = ThemeChoice(theme: .northernLights, matchesSystem: false, seasonal: true)
        choice.save(to: defaults)
        XCTAssertEqual(ThemeChoice.load(from: defaults), choice)
        defaults.set("neon", forKey: ThemeChoice.themeKey)
        XCTAssertEqual(ThemeChoice.load(from: defaults).theme, .light)
    }
}
