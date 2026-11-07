# Theme Halves and Appearance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every theme a light and a dark half, replace "Match light and dark to iOS" with an Appearance control (Automatic / Light / Dark), and show ten swatches instead of twelve, with existing settings migrated and the widgets following.

**Architecture:** VerbKit holds the testable model:
- `ThemeID` drops to ten cases (`dark` and `coffee` fold into `light` and `latte`);
- a new `AppearanceSetting` replaces `ThemeAppearance` and `matchesSystem`;
- `ThemeChoice` gains `isDark(systemIsDark:)` and a two-step migration.

App maps a theme plus `isDark` to one of twenty palettes and rebuilds the picker. `ThemeApplier` still pins the window, but only from the Appearance setting.

**Tech Stack:** Swift 6, SwiftUI (iOS 26 / macOS 26), XCTest in `Packages/VerbKit`, XcodeGen, WidgetKit.

**Spec:** `docs/superpowers/specs/2026-11-06-paper-ink-redesign-design.md`, sections "Themes" and "Palettes" (updated 2026-11-07), row 2b of "Boards → plans". Design hand-over: canvas boards "Six new halves" and "Theme picker".

## Global Constraints

- **Branch:** `claude/theme-halves`, from `origin/main` (plans 1 and 2 merged).
- **Palette values:** copied exactly from the spec's palette table, token order `paper card ink muted rule mark markSoft good goodSoft button onButton accent`.
- **`fillsTypePills`:** pastel, pastelDark, iceCream and iceCreamDark only.
- **Stored keys stay readable by the widgets:** App Group defaults `theme`, `themeAppearance` (new), `seasonalThemes`. The legacy keys `themeMatchesSystem` and `appearanceMode` are read only by the migration.
- **Wording is a UI concern:** theme names, "Automatic"/"Light"/"Dark" labels and footnotes live in `App/`.
- **VerbKit stays UI-free.** `ThemePalette` is in App and compiled into the widget target via `project.yml` (no new widget sources needed).
- **No change under `data/`.**
- **Tests:** `make test-swift`.
- **iOS build:** `make project && xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination 'generic/platform=iOS Simulator' build -quiet`.
- **macOS build:** the same with `-scheme JPVerbConjugation_macOS -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO`. The check is no Swift `error:` lines; the existing `LSSupportsOpeningDocumentsInPlace` error is known.
- **AGENTS.md:** update the `ThemeID`, `ThemeGroup`, `ThemeChoice` row in the task that changes them.

## Review Focus

- **Someone on plan 1 with Coffee and matching off.** After updating they must still see Coffee: theme `latte`, Appearance Dark. Covered by `testMigratesPlan1PinnedCoffee` (Task 1).
- **Someone on plan 1 with Matcha (light-only before).** They now get Automatic, so at night the app turns matchaDark rather than staying light. That's the spec's rule; the test pins it so it's deliberate. Covered by `testMigratesForcedThemeToAutomatic` (Task 1).
- **Appearance Dark while the phone is in Light.** The widgets can't see the app's window override, so they must use the dark palette from the stored setting, not from the system scheme. Covered by `testIsDarkFollowsSetting` (Task 1) and the widget check in Task 3.
- **Seasonal on in October with Appearance Light.** Halloween must show its light half (halloweenLight), not force dark. Covered by `testSeasonalKeepsTheChosenAppearance` (Task 1).
- **Opening the picker from a Dark phone.** The Light/Dark swatch reads "Dark" and draws the dark palette; tapping it changes nothing else. Covered by the Task 3 simulator check.

---

### Task 1: Theme model, appearance and migration (VerbKit)

**Files:**
- Modify: `Packages/VerbKit/Sources/VerbKit/Theme/ThemeID.swift`
- Modify: `Packages/VerbKit/Sources/VerbKit/Theme/ThemeChoice.swift`
- Modify: `Packages/VerbKit/Tests/VerbKitTests/ThemeChoiceTests.swift` (rewrite)
- Modify: `AGENTS.md`

**Interfaces:**
- Produces:
  - `ThemeID` with ten cases in picker order: `light, pastel, sand, matcha, latte, iceCream, northernLights, nocturnal, halloween, christmas`. Raw values unchanged. `group` as before (Café: `matcha, latte, iceCream`). `appearance(matchingSystem:)` and `pairedHalfIsDark` are deleted.
  - `public enum AppearanceSetting: String, CaseIterable, Sendable { case automatic, light, dark }`, which replaces `ThemeAppearance` (deleted).
  - `ThemeChoice(theme: ThemeID = .light, appearance: AppearanceSetting = .automatic, seasonal: Bool = false)`.
    - Keys: `themeKey = "theme"`, `appearanceKey = "themeAppearance"`, `seasonalKey = "seasonalThemes"`; legacy `matchesSystemKey = "themeMatchesSystem"` and `legacyAppearanceKey = "appearanceMode"`.
  - `ThemeChoice.effectiveTheme(on:calendar:) -> ThemeID`, unchanged.
  - `ThemeChoice.isDark(systemIsDark: Bool) -> Bool`.
  - `ThemeChoice.load(from:) -> ThemeChoice` and `save(to:)`.
  - `ThemeChoice.migrated(appearanceMode:)` and `choosing(_:systemIsDark:)` are deleted.

- [ ] **Step 1: Rewrite `ThemeChoiceTests`.** Keep `utc`, `date`, `freshDefaults` and the three seasonal date tests, switched to the new initialiser. Add:

```swift
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
func testSeasonalKeepsTheChosenAppearance() {
    let choice = ThemeChoice(theme: .sand, appearance: .light, seasonal: true)
    XCTAssertEqual(choice.effectiveTheme(on: date(2026, 10, 15), calendar: utc), .halloween)
    XCTAssertFalse(choice.isDark(systemIsDark: true))
}
func testMigratesPreThemeAppearanceMode() {   // no theme key yet
    // "system" → (.light, .automatic); "light" → (.light, .light); "dark" → (.light, .dark); nil → ThemeChoice()
    // and load writes theme + themeAppearance so a second load reads them directly
}
func testMigratesPlan1PinnedCoffee() {       // theme "coffee", themeMatchesSystem false
    // → ThemeChoice(theme: .latte, appearance: .dark); defaults now hold "latte" / "dark", no themeMatchesSystem key
}
func testMigratesPlan1Matching() {           // theme "dark", matchesSystem true → (.light, .automatic)
                                             // theme "sand", matchesSystem false → (.sand, .light)
                                             // theme "latte", no matchesSystem key (defaulted true) → (.latte, .automatic)
}
func testMigratesForcedThemeToAutomatic() {  // "matcha", "nocturnal", "halloween", matchesSystem false → .automatic each
}
func testSaveLoadRoundTripAndUnknownFallsBack() {
    // ThemeChoice(theme: .northernLights, appearance: .dark, seasonal: true) round-trips;
    // theme "neon" with an appearance key present loads .light; appearance "sepia" loads .automatic
}
```

- [ ] **Step 2: Run the tests and confirm they fail.**
  - Run: `cd Packages/VerbKit && swift test --filter ThemeChoiceTests`
  - Expected: compile errors (`AppearanceSetting`, `appearance:` and `isDark` don't exist).
- [ ] **Step 3: Implement the model.** `load(from:)` decides in this order:
  1. No `theme` key: migrate `appearanceMode`.
  2. A `theme` key but no `themeAppearance` key: migrate plan 1's keys using the spec's rules. `dark` becomes `light` and `coffee` becomes `latte`. Matching on, or the key missing, becomes `.automatic`. Matching off becomes `.dark` for `dark` and `coffee`, `.light` for `light`, `latte`, `pastel` and `sand`, and `.automatic` for every other theme. Then save, and remove `themeMatchesSystem`.
  3. Otherwise read the three keys. An unknown theme falls back to `.light`, an unknown appearance to `.automatic`.
- [ ] **Step 4: Run the tests and confirm they pass.** Run the filter, then `make test-swift`. Expected: all pass. The App won't build until Task 2; that's expected.
- [ ] **Step 5: Update AGENTS.md and commit.**
  - AGENTS.md row: "`ThemeID`, `ThemeGroup`, `ThemeChoice`, `AppearanceSetting` | The ten themes (each with a light and dark half), picker groups, seasonal override, the Appearance setting and the one-time migrations".
  - Commit message: `Themes: ten themes with light and dark halves, Appearance setting and migration`.

### Task 2: Twenty palettes, root and widgets (App)

**Files:**
- Modify: `App/Theme/ThemePalettes.swift` (add six palettes; the preview lists all twenty)
- Modify: `App/Theme/ThemePalette.swift` (`resolve`)
- Modify: `App/Theme/ThemeApplier.swift`, `App/Theme/ThemedRoot.swift`, `App/Theme/ThemeDisplay.swift`
- Modify: `Widgets/WidgetTheme.swift`, `App/SettingsView.swift` (the theme row only)

**Interfaces:**
- Consumes: Task 1's `ThemeID`, `AppearanceSetting`, `ThemeChoice.isDark(systemIsDark:)` and `ThemeChoice.appearanceKey`.
- Produces:
  - Six new static palettes named after the spec: `matchaDark`, `iceCreamDark` (with `fillsTypePills: true`), `christmasDark`, `northernLightsLight`, `nocturnalLight` and `halloweenLight`.
  - `ThemePalette.resolve(_ theme: ThemeID, isDark: Bool, contrast: ColorSchemeContrast) -> ThemePalette`, which uses the spec's Themes table and replaces the old signature.
  - `ThemeApplier.apply(_ appearance: AppearanceSetting)`: `.automatic` → `.unspecified` / `nil`.
  - `ThemeID.displayName(isDark: Bool) -> String`: `light` → "Light" / "Dark", `latte` → "Latte" / "Coffee", the other eight as before. The old `displayName` property is removed.
  - `AppearanceSetting.title`: "Automatic", "Light" or "Dark".

- [ ] **Step 1: Add the six palettes and rewrite `resolve`.** Copy the hex values from the spec table.
- [ ] **Step 2: Rewire `ThemedRoot`.**
  - Read `@AppStorage(ThemeChoice.appearanceKey)` instead of `matchesSystemKey`.
  - `isDark = choice.isDark(systemIsDark: colorScheme == .dark)`.
  - Apply the setting with `ThemeApplier.apply(choice.appearance)` in `onChange(of: choice.appearance, initial: true)`.
  - The palette is `resolve(choice.effectiveTheme(on: today), isDark:, contrast:)`.
- [ ] **Step 3: Rewire the widgets.** `WidgetTheme.palette(on:scheme:contrast:)` loads the choice and resolves with `isDark: choice.isDark(systemIsDark: scheme == .dark)`, so a pinned Dark setting reaches the widgets.
- [ ] **Step 4: Rewire Settings.** The Theme row shows `effectiveTheme(on: .now).displayName(isDark:)`, using the same `isDark` the root uses: read `colorScheme`. Remove the `themeMatchesSystem` storage.
- [ ] **Step 5: Build iOS and macOS.** Expected: iOS succeeds, and macOS has no Swift `error:` lines. `ThemePickerView` still references removed API, so stub its two switches to the new keys only as far as it needs to compile; Task 3 rebuilds it.
- [ ] **Step 6: Commit.** Message: `Twenty palettes: every theme resolves a light and a dark half; widgets follow the Appearance setting`.

### Task 3: The picker: Appearance control and ten swatches

**Files:**
- Modify: `App/Theme/ThemePickerView.swift`

**Interfaces:**
- Consumes: Task 1's `ThemeGroup.themes`, `AppearanceSetting`, `ThemeChoice`; Task 2's `resolve(_:isDark:contrast:)`, `displayName(isDark:)`, `AppearanceSetting.title`.
- Produces: nothing new.

- [ ] **Step 1: Rebuild the picker, top to bottom.**
  1. **The preview card.** Unchanged, except its accessibility label uses `displayName(isDark:)`.
  2. **"Appearance".** A segmented `Picker` over `AppearanceSetting.allCases`, labelled with `title`. Under it, the footnote "Automatic follows your iPhone. Light and Dark keep the app that way."
  3. **The four groups of swatches.** Each swatch's face is `resolve(theme, isDark: currentIsDark, contrast: .standard)`, so every swatch shows the half that is showing. Its name is `displayName(isDark: currentIsDark)`. Tapping a swatch only sets the theme. The season caption stays.
  4. **The "Seasonal themes" toggle and its footnote.** Unchanged. "Match light and dark to iOS" is removed.
  - Every change reloads the widget timelines, as today.
- [ ] **Step 2: Build iOS. Check on the simulator.**
  - Light phone, Automatic: the first swatch reads "Light". Switching to Dark turns the whole app dark, sheets included, and the swatch now reads "Dark".
  - Set Matcha and Automatic, then switch the simulator to dark with `xcrun simctl ui <udid> appearance dark`. Expected: matchaDark paper #141a12.
  - Seasonal on (fake October by temporarily writing the theme to `halloween` if needed) with Appearance Light. Expected: halloweenLight paper #f6efe4.
  - Add a widget, then set Appearance Dark while the phone is in Light. Expected: the widget uses the dark palette after its timeline reloads.
- [ ] **Step 3: Commit.** Message: `Theme picker: Appearance control and ten swatches named after the half that is showing`.

### Task 4: Spec status and checks

**Files:**
- Modify: `docs/superpowers/specs/2026-11-06-paper-ink-redesign-design.md` (row 2b gets "(built)")

- [ ] **Step 1: Mark row 2b built.**
- [ ] **Step 2: Run `make check`, `make check-project` and `make test-swift`.** Expected: all pass.
- [ ] **Step 3: Commit.** Message: `Spec: theme halves built`.
