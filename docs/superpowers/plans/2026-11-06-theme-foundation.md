# Theme Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the glass-and-pastel look with paper-and-ink surfaces driven by twelve selectable themes, in the app and its widgets.

**Architecture:** Theme logic (ids, groups, appearance, seasonal override, migration, persistence) is plain Swift in VerbKit with XCTest coverage. Colours live in App as a `ThemePalette` value injected through the environment by one root modifier, which also forces the window appearance for light-only and dark-only themes. Shared components read `\.palette`; the widget target compiles the palette files too.

**Tech Stack:** Swift 6 toolchain, SwiftUI (iOS 26 / macOS 26), XCTest in `Packages/VerbKit`, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-11-06-paper-ink-redesign-design.md` (rules, the twelve themes, the palette table, Increase Contrast). Canvas boards: Style map, Proposed list/page/quiz/dark, Settings, Theme picker v2, Themes across screens, Colour-blind and contrast.

## Global Constraints

- Work on a new branch from `main` (`claude/theme-foundation`). If `App/VerbPairCard.swift` exists on `main` by then, it is a `glassCard` caller: include it in Task 4.
- VerbKit stays UI-free: no SwiftUI/UIKit/AppKit/WidgetKit import in `Packages/VerbKit`. Colours, fonts and theme names stay in `App/`.
- User-facing strings live in `App/` (theme names, group titles, Settings copy).
- Liquid Glass only on chrome; content surfaces use `paper`, `card` and a 1 pt `rule`.
- `mark` only for wrong answers, corrections and destructive actions.
- Every new App file a widget needs must be listed under `VerbTableWidgets.sources` in `project.yml`; run `make check-project`. Never edit or commit the `.xcodeproj`.
- No change under `data/`.
- Defaults live in the App Group: `UserDefaults.verbKitAppGroup` in VerbKit, `.appGroup` in App.
- After the work, update the AGENTS.md "App UI components" table (`glassCard` → `paperCard`, new `TypeLabel`, `paperBackground`, `Font.headword`, `\.palette`).
- Swift tests only: `make test-swift`. Build check: `make project && xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation -destination 'generic/platform=iOS Simulator' build`.

## Review Focus

- **Existing users keep their appearance.** Someone who chose Dark before the update must still see dark after it, once, with no flash of Light → `ThemeChoiceTests.testMigratesDarkAppearance` (Task 1) and the launch-order step in Task 3.
- **Seasonal theme hands back on 1 November.** A user who opted into seasonal themes must get their own theme back after October → `testSeasonalReturnsChosenThemeInNovember` (Task 1).
- **A dark-only theme on a light phone.** Sheets, alerts, menus and the keyboard must render dark with Nocturnal while iOS is in light mode → Task 7, step 4.
- **Differentiate Without Color plus Increase Contrast in a quiz.** A wrong answer must still be readable as wrong with no colour → Task 6 simulator check.
- **Widgets after a theme change.** Home-screen widgets must repaint in the new theme, and keep a readable clear style on a tinted or clear home screen → Task 8 simulator check.

---

### Task 1: Theme model in VerbKit

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Theme/ThemeID.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Theme/ThemeChoice.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/ThemeChoiceTests.swift`

**Interfaces:**
- Produces:
  - `public enum ThemeID: String, CaseIterable, Sendable { case light, dark, pastel, sand, matcha, latte, coffee, iceCream, northernLights, nocturnal, halloween, christmas }` — `allCases` order is the picker order above.
  - `public var group: ThemeGroup` on `ThemeID`.
  - `public func appearance(matchingSystem: Bool) -> ThemeAppearance` on `ThemeID`.
  - `public enum ThemeGroup: String, CaseIterable, Sendable { case everyday, cafe, night, seasonal }` with `public var themes: [ThemeID]`.
  - `public enum ThemeAppearance: Sendable, Equatable { case followSystem, light, dark }`.
  - `public struct ThemeChoice: Equatable, Sendable` with `var theme: ThemeID`, `var matchesSystem: Bool`, `var seasonal: Bool`; `init(theme: ThemeID = .light, matchesSystem: Bool = true, seasonal: Bool = false)`; `static let themeKey = "theme"`, `matchesSystemKey = "themeMatchesSystem"`, `seasonalKey = "seasonalThemes"`, `legacyAppearanceKey = "appearanceMode"`; `func effectiveTheme(on date: Date, calendar: Calendar = .current) -> ThemeID`; `func appearance(on date: Date, calendar: Calendar = .current) -> ThemeAppearance`; `static func migrated(appearanceMode: String?) -> ThemeChoice`; `static func load(from defaults: UserDefaults) -> ThemeChoice`; `func save(to defaults: UserDefaults)`.

Appearance table (`matchingSystem` true / false): light, dark, latte, coffee, pastel, sand → `.followSystem` / (light, pastel, sand, latte → `.light`; dark, coffee → `.dark`). matcha, iceCream, christmas → `.light` always. northernLights, nocturnal, halloween → `.dark` always.

`load(from:)`: when `themeKey` is absent, build `migrated(appearanceMode: defaults.string(forKey: legacyAppearanceKey))`, `save(to:)` it, and return it. Unknown raw theme values fall back to `.light`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import VerbKit

final class ThemeChoiceTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

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
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set("dark", forKey: ThemeChoice.legacyAppearanceKey)
        XCTAssertEqual(ThemeChoice.load(from: defaults), ThemeChoice(theme: .dark, matchesSystem: false))
        XCTAssertEqual(defaults.string(forKey: ThemeChoice.themeKey), "dark")
    }

    func testSaveLoadRoundTripAndUnknownFallsBack() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let choice = ThemeChoice(theme: .northernLights, matchesSystem: false, seasonal: true)
        choice.save(to: defaults)
        XCTAssertEqual(ThemeChoice.load(from: defaults), choice)
        defaults.set("neon", forKey: ThemeChoice.themeKey)
        XCTAssertEqual(ThemeChoice.load(from: defaults).theme, .light)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd Packages/VerbKit && swift test --filter ThemeChoiceTests`
Expected: FAIL — `cannot find 'ThemeChoice' in scope`.

- [ ] **Step 3: Implement `ThemeID`, `ThemeGroup`, `ThemeAppearance` in `ThemeID.swift` and `ThemeChoice` in `ThemeChoice.swift`** per the Interfaces block and the appearance table. Seasonal: month 10 → `.halloween`, month 12 → `.christmas`, from `calendar.component(.month, from: date)`.

- [ ] **Step 4: Run them to verify they pass**

Run: `cd Packages/VerbKit && swift test --filter ThemeChoiceTests`
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/VerbKit/Sources/VerbKit/Theme Packages/VerbKit/Tests/VerbKitTests/ThemeChoiceTests.swift
git commit -m "VerbKit: theme ids, groups, seasonal override and appearance migration"
```

### Task 2: Palettes in App, shared with the widgets

**Files:**
- Create: `App/Theme/ThemePalette.swift` (type, `Color(hex:)`, environment key, `resolve`)
- Create: `App/Theme/ThemePalettes.swift` (the fourteen palettes)
- Create: `App/Theme/ThemeDisplay.swift` (names)
- Modify: `project.yml` (widget `sources`: add `App/Theme/ThemePalette.swift`, `App/Theme/ThemePalettes.swift`)

**Interfaces:**
- Consumes: `ThemeID`, `ThemeAppearance` (Task 1).
- Produces:
  - `struct ThemePalette: Equatable { let paper, card, ink, muted, rule, mark, markSoft, good, goodSoft, button, onButton, accent: Color; let fillsTypePills: Bool }`
  - `static func resolve(_ theme: ThemeID, appearance: ThemeAppearance, systemScheme: ColorScheme, contrast: ColorSchemeContrast) -> ThemePalette` — `systemScheme` decides only when `appearance == .followSystem`.
  - `func increasedContrast() -> ThemePalette` — `muted = muted.mix(with: ink, by: 0.5)`, `rule = rule.mix(with: muted, by: 0.5)` (original `muted`).
  - `extension EnvironmentValues { @Entry var palette: ThemePalette = .light }`
  - `extension Color { init(hex: UInt32) }`
  - Static palettes named as in the spec table: `.light, .dark, .pastel, .pastelDark, .sand, .sandDark, .matcha, .latte, .coffee, .iceCream, .northernLights, .nocturnal, .halloween, .christmas`; `fillsTypePills` true for `.pastel`, `.pastelDark`, `.iceCream`.
  - In `ThemeDisplay.swift` (App only, not the widget): `extension ThemeID { var displayName: String }` ("Light", "Dark", "Pastel", "Sand", "Matcha", "Latte", "Coffee", "Ice cream", "Northern lights", "Nocturnal", "Halloween", "Christmas"); `extension ThemeGroup { var title: String }` ("Everyday", "Café", "Night", "Seasonal").

- [ ] **Step 1: Write the palettes** with every hex value copied from the spec's palette table, and the mapping from the spec's "Palette per theme" paragraph inside `resolve`.
- [ ] **Step 2: Add a `#Preview("All palettes")`** in `ThemePalettes.swift` that lists each palette as a row: paper background, a card with ink, muted, mark and good sample text, and the button with onButton text.
- [ ] **Step 3: Add the two palette files to the widget target** in `project.yml`, then run `make check-project`.
  Expected: exits 0.
- [ ] **Step 4: Build**

Run: `make project && xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **` (the widget target compiles the palette files).

- [ ] **Step 5: Commit**

```bash
git add App/Theme project.yml
git commit -m "Theme palettes for the twelve themes, shared with the widgets"
```

### Task 3: Root wiring, migration and window appearance

**Files:**
- Create: `App/Theme/ThemedRoot.swift`
- Modify: `App/AppearanceApplier.swift` → rename to `App/Theme/ThemeApplier.swift`
- Modify: `App/RootView.swift:13,94-96,151-153` (remove `appearanceModeRaw` and its `onChange`; apply `.themedRoot()`)
- Modify: `App/SettingsView.swift:6-18,24,80-84,108-116` (delete `AppearanceMode` and the Appearance section; Task 7 adds the Theme row)
- Modify: `App/DataLoadingView.swift` only if it references `AppearanceMode`

**Interfaces:**
- Consumes: `ThemeChoice` (Task 1), `ThemePalette.resolve`, `\.palette` (Task 2).
- Produces:
  - `enum ThemeApplier { @MainActor static func apply(_ appearance: ThemeAppearance) }` — `.followSystem` → `UIUserInterfaceStyle.unspecified` / `NSApp.appearance = nil`; `.light`/`.dark` as before. Keeps the cross-dissolve.
  - `extension View { func themedRoot() -> some View }`, backed by `struct ThemedRoot: ViewModifier`. It reads the three keys with `@AppStorage(…, store: .appGroup)`, `@Environment(\.colorScheme)`, `@Environment(\.colorSchemeContrast)` and `@Environment(\.scenePhase)`. It keeps `@State private var today = Date()`, refreshed when the scene becomes active. It calls `ThemeApplier.apply` on change (initial too), injects `.environment(\.palette, …)` and applies `.tint(palette.accent)`.
  - Launch order: `JPVerbConjugationApp.init` calls `_ = ThemeChoice.load(from: .appGroup)` before the first scene, so the migration writes the keys before `@AppStorage` reads them.

- [ ] **Step 1: Rename the applier** and change its parameter to `ThemeAppearance`.
- [ ] **Step 2: Write `ThemedRoot`** per the Interfaces block. Apply `.themedRoot()` in `RootView.body` in place of the `appearanceModeRaw` `onChange`, and call the migration in `JPVerbConjugationApp.init`.
- [ ] **Step 3: Remove `AppearanceMode`** and the Settings Appearance section, then build (the Task 2 build command). Expected: `** BUILD SUCCEEDED **` with no reference to `AppearanceMode` (`grep -rn AppearanceMode App` prints nothing).
- [ ] **Step 4: Simulator check, migration.** Install the current `main` build, choose Settings › Appearance › Dark, then install this build over it. Expected: the app opens dark with no light flash.
- [ ] **Step 5: Commit**

```bash
git add App
git commit -m "Theme root: palette environment, window appearance, appearanceMode migration"
```

### Task 4: Paper surfaces

**Files:**
- Create: `App/UI/PaperSurface.swift`
- Delete: `App/UI/GlassCard.swift`
- Modify (`glassCard` → `paperCard`): `App/CommonPhrasesCard.swift`, `App/VerbDetailView.swift`, `App/GrammarDetailView.swift`, `App/Grammar/AttachmentSection.swift`, `App/Counters/CounterDetailView.swift`, `App/WordBank/WordBankDetailView.swift` (+ `App/VerbPairCard.swift` if present)
- Modify: `App/FormTable.swift:55-60` (`formCard` draws `card` + 1 pt `rule`, radius 14)
- Modify (add `paperBackground()` to each screen's root `List`/`ScrollView`/`Form`): `VerbListView`, `VerbDetailView`, `GrammarListView`, `GrammarDetailView`, `Counters/CountersHomeView`, `Counters/CounterListView`, `Counters/CounterDetailView`, `WordBank/WordBankListView`, `WordBank/WordBankDetailView`, `SettingsView`, `QuizView`

**Interfaces:**
- Consumes: `\.palette`.
- Produces:
  - `func paperCard(cornerRadius: CGFloat = 12, fillsWidth: Bool = true) -> some View` — 12 pt padding, `palette.card` fill, `strokeBorder(palette.rule, lineWidth: contrast == .increased ? 1.5 : 1)`. Same signature as `glassCard`, so callers only rename.
  - `func paperBackground() -> some View` — `.scrollContentBackground(.hidden)` plus `palette.paper` behind, ignoring safe areas.
  - `func paperRow() -> some View` — for `List` rows: `.listRowBackground(palette.card)`, `.listRowSeparatorTint(palette.rule)`.

- [ ] **Step 1: Write `PaperSurface.swift`** per the Interfaces block. Delete `GlassCard.swift` and rename the callers.
- [ ] **Step 2: Apply `paperBackground()`** to the listed screens, and `paperRow()` to rows of inset-grouped lists in those screens.
- [ ] **Step 3: Build** (Task 2 build command). Expected: succeeded; `grep -rn "glassCard(" App` prints nothing.
- [ ] **Step 4: Simulator check.** In Light, Dark and Sand, open the Verbs list, a verb, a grammar lesson, a counter and Settings. Expected: paper ground, outlined white (or theme) cards, glass only on bars and toolbar buttons.
- [ ] **Step 5: Commit**

```bash
git add App
git commit -m "Paper surfaces replace glass cards in content"
```

### Task 5: Type label, level badge, filter chip, row headword

**Files:**
- Create: `App/UI/TypeLabel.swift`
- Create: `App/UI/Typography.swift`
- Modify: `App/UI/LevelBadge.swift`, `App/UI/FilterChip.swift`, `App/VerbRow.swift`, `App/VerbDetailView.swift:84-101` (type pill only), `App/VerbGuideSheet.swift`, `App/FormLookup/VerbSpanCard.swift`, `App/VerbColors.swift` (keep `accentPill`, used by `TypeLabel` for filled pills)

**Interfaces:**
- Consumes: `\.palette` (with `fillsTypePills`), `VerbType.accentColor`, `TeGroup.accentColor`.
- Produces:
  - `struct TypeLabel: View { init(_ type: VerbType, teGroup: TeGroup? = nil, emphasis: LevelBadge.Emphasis = .row) }`. It draws `verb.label`-style text ("Irregular", "Ru-verb", "U-verb") in `palette.ink` with an 8 pt dot in `type.accentColor`. With a `teGroup`, it adds "·", a dot in `teGroup.accentColor` and the て ending text (`TeGroup.rawValue`). With `fillsTypePills`, it draws `accentPill(type.accentColor)` instead. With `accessibilityDifferentiateWithoutColor`, the dot becomes `Image(systemName:)` (`diamond.fill`/`circle.fill`/`triangle.fill` for irregular/ru/u) and the て ending gets a 1 pt `ink` box.
  - `extension VerbType { var shapeSymbol: String }` (App).
  - `extension Font { static func headword(_ style: Font.TextStyle) -> Font }` — `.custom("HiraMinProN-W6", size: <default size of style>, relativeTo: style)`. Default sizes: largeTitle 34, title 28, title2 22, title3 20, headline 17, body 17.
  - `LevelBadge` keeps its API; it draws text in `palette.muted` in a capsule with `strokeBorder(palette.rule)`, no glass.
  - `FilterChip` keeps its API. Off: `palette.card` fill, 1 pt `palette.ink` border. On: `palette.button` fill, `palette.onButton` text. A non-nil `accent` draws a leading 8 pt dot instead of a pastel fill. `chipBackground(_:)` follows the same rule.

- [ ] **Step 1: Write `TypeLabel` and `Font.headword`.** Restyle `LevelBadge` and `FilterChip`.
- [ ] **Step 2: Use them.** In `VerbRow`, replace the leading `accentPill` with `TypeLabel(verb.type, teGroup: verb.teGroup)` on the line under the title. The title shows the kanji spelling through `JapaneseText` in `.headword(.title3)` when `verb.kanji != nil`, else the kana. Drop the separate grey kanji. Replace the pill in `VerbDetailView`'s header, `VerbGuideSheet` and `VerbSpanCard` with `TypeLabel`.
- [ ] **Step 3: Build** (Task 2 build command). Expected: succeeded.
- [ ] **Step 4: Simulator check.** In Light, Pastel and Ice cream, open the Verbs list with furigana on and off. Turn on Differentiate Without Color (Settings › Accessibility › Display & Text Size). Expected: dots in Light, filled pills in Pastel and Ice cream, shapes with DWC on, and furigana on every kanji headword when enabled.
- [ ] **Step 5: Commit**

```bash
git add App
git commit -m "Type label, outlined level badge and ink filter chips"
```

### Task 6: Quiz marking

**Files:**
- Modify: `App/QuizChoiceButton.swift`, `App/UI/QuizChrome.swift:100-110`, `App/QuizQuestionView.swift` (`timerColor`)

**Interfaces:**
- Consumes: `\.palette`, `accessibilityDifferentiateWithoutColor`.
- Produces: `QuizChoiceButton` keeps its initializer. It drops `correctColor`/`wrongColor`; `QuizChrome` reads `palette.good`/`palette.mark` instead.

States:

| State | Fill | Border | Text | Glyph |
|---|---|---|---|---|
| Unanswered | `card` | 1 pt `rule` | `ink` | small shape in `muted` (keeps today's four shapes) |
| Correct | `goodSoft` | 2 pt `good` | `ink`, bold | `checkmark` in `good` |
| Chosen, wrong | `markSoft` | 2 pt `mark` | `mark`, strikethrough | `xmark` in `mark` |
| Other, answered | as unanswered | | | 0.45 opacity |

Radius 14, minimum height 60, `.buttonStyle(.plain)`. With DWC on, answered buttons add a caption: "Your answer" (chosen, wrong) and "Correct". The VoiceOver `statusDescription` stays as it is. Timer: more than 10 s `muted`, 6–10 s `ink`, 5 s or less `mark`.

- [ ] **Step 1: Restyle `QuizChoiceButton`** per the table. Point `QuizChrome`'s feedback colours at the palette.
- [ ] **Step 2: Change `timerColor`.**
- [ ] **Step 3: Build** (Task 2 build command). Expected: succeeded; `grep -rn "correctColor\|wrongColor" App` prints nothing.
- [ ] **Step 4: Simulator check.** Answer one question wrong in the verb quiz and in the connection quiz with Light, then with Halloween plus DWC plus Increase Contrast (`xcrun simctl ui booted increase_contrast enabled`). Expected: wrong reads as struck-through with an ✕ and "Your answer", correct as ✓ and "Correct", in both.
- [ ] **Step 5: Commit**

```bash
git add App
git commit -m "Quiz answers marked like a teacher: struck in red, ringed in green"
```

### Task 7: Theme picker

**Files:**
- Create: `App/Theme/ThemePickerView.swift`
- Modify: `App/SettingsView.swift` (a Theme row where the Appearance section was)

**Interfaces:**
- Consumes: `ThemeChoice` keys, `ThemeGroup.themes`, `displayName`, `title`, `ThemePalette.resolve`, `TypeLabel`, `QuizChoiceButton`.
- Produces: `struct ThemePickerView: View`.

Layout, from the "Theme picker v2" board:
1. A preview card in the current palette: `TypeLabel(.ru)`, 食べる in `.headword(.largeTitle)` via `JapaneseText`, a "Test this verb" capsule in `button`/`onButton`, and two answered `QuizChoiceButton`s (wrong たべって, correct たべて).
2. One section per `ThemeGroup` with its `title`. Swatches are 50 pt circles: top half `paper`, bottom 45 % `ink`, an 8 pt `mark` dot. Each swatch is resolved with `appearance(matchingSystem: false)`, so paired themes show their own face. The name sits under the swatch; Halloween and Christmas show "October"/"December" beneath. The selection gets a 3 pt `ink` ring and `.isSelected` as an accessibility trait.
3. Toggles: "Match light and dark to iOS" and "Seasonal themes", with the footer "Seasonal themes switch on by themselves in October and December, then go back."

Selecting a theme or toggling writes the keys and calls `WidgetCenter.shared.reloadAllTimelines()` (iOS only, `#if canImport(WidgetKit)`). In Settings, the row is `NavigationLink { ThemePickerView() } label: { LabeledContent("Theme", value: choice.effectiveTheme(on: .now).displayName) }` in a section titled "Appearance".

- [ ] **Step 1: Write `ThemePickerView`** and the Settings row.
- [ ] **Step 2: Build** (Task 2 build command). Expected: succeeded.
- [ ] **Step 3: Simulator check, every theme.** Pick each of the twelve themes. Expected: the whole app, including the open Settings sheet, repaints. Matcha and Christmas stay light and Nocturnal stays dark with iOS in either mode. Turning matching off pins Light/Dark/Latte/Coffee.
- [ ] **Step 4: Simulator check, dark-only theme on a light phone.** With iOS in light mode and Nocturnal picked, open the Settings sheet, the "Reset quiz history" confirmation dialog, a filter menu and the search keyboard. Expected: all render dark.
- [ ] **Step 5: Commit**

```bash
git add App
git commit -m "Theme picker: twelve themes in four groups, live preview"
```

### Task 8: Widgets follow the theme

**Files:**
- Modify: `Widgets/WidgetTheme.swift`, `Widgets/VerbWidgetViews.swift`, `Widgets/GrammarWidgetViews.swift`, `Widgets/CounterWidgetViews.swift`

**Interfaces:**
- Consumes: `ThemeChoice.load(from: .verbKitAppGroup)`, `ThemePalette.resolve` (compiled into the widget since Task 2).
- Produces: `WidgetTheme.palette(on date: Date, scheme: ColorScheme, contrast: ColorSchemeContrast) -> ThemePalette`. `WidgetTheme.background(isHome:)` gains a `palette` parameter and fills `palette.paper` on the home screen.

Rules: text colours come from the palette (`ink`, `muted`), not `.white`. When `@Environment(\.widgetRenderingMode)` is not `.fullColor` (tinted or clear home screen), skip the paper fill and use `.primary`/`.secondary`. The navy gradient goes. `WidgetTheme.accent(for:)` stays for JLPT dots.

- [ ] **Step 1: Restyle the three widget views** per the rules.
- [ ] **Step 2: Build** (Task 2 build command). Expected: succeeded.
- [ ] **Step 3: Simulator check.** Add the verb, grammar and counter widgets. Switch the theme from Light to Nocturnal in the app, return home, then set the home screen to Tinted and to Clear. Expected: widgets repaint in Nocturnal within a few seconds; tinted and clear show legible type with no paper.
- [ ] **Step 4: Commit**

```bash
git add Widgets
git commit -m "Widgets paint in the current theme"
```

### Task 9: Docs and full check

**Files:**
- Modify: `AGENTS.md` ("App UI components" table and the U-backlog note naming `glassCard`)

- [ ] **Step 1: Update AGENTS.md:** `paperCard(cornerRadius:fillsWidth:)` replaces `glassCard`; add `paperBackground()`, `paperRow()`, `TypeLabel`, `Font.headword(_:)`, `\.palette` / `ThemePalette`; add `ThemeChoice` to the VerbKit table. Add a Trap: a widget-visible colour must live in `App/Theme/ThemePalette*.swift`.
- [ ] **Step 2: Run the checks**

Run: `make test-swift && make check-project && make check`
Expected: all pass.

- [ ] **Step 3: Commit**

```bash
git add AGENTS.md
git commit -m "AGENTS: paper surfaces, palette and theme model"
```
