# Theme personality Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Each theme gets a signature in three places only: a results stamp on quiz results, a small motif beside the tab roots' large titles, and, when someone opts in, the app icon.

**Architecture:** VerbKit gains the motif path data (`TitleMotif`, beside `StampShape`) and the icon rule (`AppIconMatching`), both UI-free and tested. App gets the colours (`ThemeMotif`, next to `ThemeStamp`), a `\.themeHalf` environment value set by `themedRoot()`, a `motifTitle(_:)` modifier using iOS 26's `ToolbarItemPlacement.largeTitle`, the stamp in `QuizScoreCard`, and an "App icon matches theme" switch in Settings › Theme. `scripts/generate-icon.swift` also renders nine alternate icon sets. It is built together with VerbKit's `StampShape.swift` and `SVGPathData.swift` by a new `make icons`, so the stamps are drawn from the same path data as the app.

**Tech Stack:** SwiftUI (iOS 26 / macOS 26), VerbKit (Foundation only), XCTest, CoreGraphics/CoreText script, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-11-06-paper-ink-redesign-design.md`, row 6 of "Boards → plans". Boards: "Theme personality" (`project/ThemePersonality.dc.html`) and "App icons per palette" (`project/LaunchIcons.dc.html`) on https://claude.ai/artifact/7eCLPFjJnWRoGB2n85ocr2.

## Global Constraints

- Decoration only on the icon, the title motif and the results stamp. Rows, forms, examples and quiz choices never get any.
- Motifs are still. The stamp keeps the score readable in its middle (the shapes keep a clear radius of about 32 of 120).
- The score is drawn in `mark` red only for the Light theme's light half (the teacher's circle). Every other half draws the score in `ink`.
- Stamp and motif colours are the board's hex values per theme half, as `ThemeStamp` already does. The six new halves keep their theme's motif and stamp.
- Icons:
  - one set per theme, ten in all: Light·Dark is the primary icon, and Latte·Coffee is one set;
  - each set has a light, a dark and a tinted 1024 px image;
  - strokes are the board's width × 1.8, the stamp is scaled 0.84 about the centre, and 活 is outlined from Shippori Mincho B1 (never committed).
- The icon changes only when someone taps a theme while "App icon matches theme" is on. The switch is off by default. A seasonal override never changes the icon, but a seasonal theme chosen by hand does.
- macOS: no alternate icons and no title motif (both `#if os(iOS)`).
- VerbKit stays UI-free. Wording lives in App. Never edit `.xcodeproj`: edit `project.yml` and run `make project`.

## Review Focus

1. **Large titles with a motif:**
   - The inline title still shows when the large title collapses on scroll.
   - The title text is the same as before: 早見表, Grammar, Counters, Word Bank's folder title, Search.
   - VoiceOver reads the title and not the motif.
   - Test: the modifier marks the motif `accessibilityHidden`; checked on the simulator.
2. **Dynamic Type AX5 on results:**
   - The stamp scales with `stampSize` and the score still fits inside it.
   - Test: the existing `minimumScaleFactor` stays in place; checked on the simulator.
3. **Seasonal override:**
   - In October with Seasonal on, tapping Light keeps the icon at Light even though Halloween is showing.
   - Test: `testSeasonalOverrideNeverPicksTheIcon` in Task 1.
4. **Turning the switch on and off:**
   - On applies the chosen theme's icon at once.
   - Off returns to the primary icon.
   - Nothing happens while the icon already matches, so iOS shows no alert.
   - Test: `testNoChangeWhenTheIconAlreadyMatches` in Task 1.
5. **Increase Contrast and the dark halves:**
   - Stamp colours are fixed hexes, and the score uses `ink`, so its contrast follows the palette's checked text token.
   - Test: covered by the Global Constraints rule; checked on screen in Northern lights dark.

---

### Task 1: VerbKit — title motifs and the icon rule

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Seal/TitleMotif.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Theme/AppIconMatching.swift` (next to `ThemeID`; put it wherever `ThemeID` lives)
- Test: `Packages/VerbKit/Tests/VerbKitTests/ThemePersonalityTests.swift`

**Interfaces:**
- Produces:
  - `public enum TitleMotif: String, CaseIterable, Sendable { case hanko, brush, bubbles, rake, enso, heart, steam, sprinkles, aurora, moon, pumpkin, snow }` with `public var strokes: [MotifStroke]`, in a 64×40 box.
  - `public struct MotifStroke: Equatable, Sendable { public let d: String; public let color: MotifColor; public let width: Double }`.
  - `public enum MotifColor: Equatable, Sendable { case first, second, third, fixed(UInt32) }`. Bubbles and sprinkles use the board's fixed hexes:
    - bubbles: 7cd4fd, fdca3e, f87166;
    - sprinkles: e07aa0, 4fb393, e0a92e.
  - `public enum AppIconMatching`:
    - `static let defaultsKey = "appIconMatchesTheme"`;
    - `static func iconName(for theme: ThemeID) -> String?`: nil for `.light`, otherwise `"AppIcon-\(theme.rawValue)"`;
    - `static func change(tapped: ThemeID, matches: Bool, current: String?) -> IconChange?`;
    - `static func change(switchedOn: Bool, chosen: ThemeID, current: String?) -> IconChange?`.
  - `public struct IconChange: Equatable { public let name: String? }`. A nil name means the primary icon.

Paths are copied from the board's `motif()` function. `rake` is three copies at y 14, 22 and 30; `steam` is three copies at x 22, 32 and 42.

- [ ] **Step 1: Write the failing tests**

```swift
func testEveryMotifParsesAndStaysInItsBox() {
    for motif in TitleMotif.allCases {
        XCTAssertFalse(motif.strokes.isEmpty, "\(motif)")
        for stroke in motif.strokes {
            let elements = SVGPathData.parse(stroke.d)
            XCTAssertFalse(elements.isEmpty, "\(motif): \(stroke.d)")
            // Every end point inside 64×40 (control points may stray).
        }
    }
}
func testBubblesAndSprinklesUseTheBoardsFixedColours() {
    XCTAssertEqual(TitleMotif.bubbles.strokes.map(\.color), [.fixed(0x7CD4FD), .fixed(0xFDCA3E), .fixed(0xF87166)])
    XCTAssertEqual(Set(TitleMotif.sprinkles.strokes.map(\.color)), [.fixed(0xE07AA0), .fixed(0x4FB393), .fixed(0xE0A92E)])
    XCTAssertEqual(TitleMotif.aurora.strokes.map(\.color), [.first, .second, .third])
}
func testIconNames() {
    XCTAssertNil(AppIconMatching.iconName(for: .light))
    XCTAssertEqual(AppIconMatching.iconName(for: .latte), "AppIcon-latte")
    XCTAssertEqual(Set(ThemeID.allCases.compactMap(AppIconMatching.iconName)).count, 9)
}
func testTappingAThemeChangesTheIconOnlyWhenMatching() {
    XCTAssertEqual(AppIconMatching.change(tapped: .matcha, matches: true, current: nil), IconChange(name: "AppIcon-matcha"))
    XCTAssertNil(AppIconMatching.change(tapped: .matcha, matches: false, current: nil))
    XCTAssertEqual(AppIconMatching.change(tapped: .light, matches: true, current: "AppIcon-matcha"), IconChange(name: nil))
}
func testNoChangeWhenTheIconAlreadyMatches() {
    XCTAssertNil(AppIconMatching.change(tapped: .matcha, matches: true, current: "AppIcon-matcha"))
    XCTAssertNil(AppIconMatching.change(switchedOn: false, chosen: .matcha, current: nil))
}
func testSwitchingOnAppliesTheChosenThemeAndOffRestoresThePrimary() {
    XCTAssertEqual(AppIconMatching.change(switchedOn: true, chosen: .sand, current: nil), IconChange(name: "AppIcon-sand"))
    XCTAssertEqual(AppIconMatching.change(switchedOn: false, chosen: .sand, current: "AppIcon-sand"), IconChange(name: nil))
}
func testSeasonalOverrideNeverPicksTheIcon() {
    // The rule only ever sees the theme someone tapped, never ThemeChoice.effectiveTheme.
    let october = ThemeChoice(theme: .light, appearance: .automatic, seasonal: true)
    XCTAssertEqual(october.effectiveTheme(on: date("2026-10-15")), .halloween)
    XCTAssertEqual(AppIconMatching.change(switchedOn: true, chosen: october.theme, current: nil), nil)
}
```

- [ ] **Step 2:** Run `make test-swift`. Expected: it fails to compile because `TitleMotif` and `AppIconMatching` are not defined.
- [ ] **Step 3:** Implement both types. Fill in the "every end point inside 64×40" assertion using the parsed elements' end points.
- [ ] **Step 4:** Run `make test-swift`. Expected: all tests pass.
- [ ] **Step 5:** Commit: "VerbKit: title motifs and the app icon rule".

### Task 2: App — the theme half, title motifs and the results stamp

**Files:**
- Create: `App/Theme/ThemeMotif.swift`. It holds `ThemeMotif` (motif plus three colours per theme half, from the board's `LIGHT`/`DARK` tables), `struct ThemeHalf: Equatable { theme: ThemeID; isDark: Bool }`, `@Entry var themeHalf`, and `TitleMotifView`, which draws the strokes with `Path(svg:)` scaled from 64×40 to 56×35 pt.
- Create: `App/UI/MotifTitle.swift`. It holds `func motifTitle(_ title: String) -> some View`. On iOS it adds `.navigationTitle(title)` and a `ToolbarItem(placement: .largeTitle)` with the title in `.largeTitle.bold()` and `TitleMotifView` trailing, with the motif `accessibilityHidden`. On macOS it is `.navigationTitle(title)` only.
- Modify: `App/Theme/ThemedRoot.swift` to set `\.themeHalf` from `effectiveTheme` and `isDark`.
- Modify: `App/UI/QuizScoreCard.swift`. The stamp draws `ThemeStamp.stamp(for:isDark:)` from `\.themeHalf`, with each stroke trimmed by `drawn` at the board's base width, scaled to `stampSize`. The score uses `palette.mark` when the half is `.light`/light, otherwise `palette.ink`. Remove `StampRing` if nothing else uses it.
- Modify the tab roots to use `motifTitle`, replacing `.navigationTitle` there:
  - `VerbListView` (早見表);
  - `GrammarListView`;
  - `CountersHomeView`;
  - `WordBankListView`, root folder only;
  - `SearchTab`.

The colours per half come from the board:
- Light: hanko, c2372b.
- Dark: brush, e9ebe6.
- Pastel: bubbles.
- Sand: rake, a8743a / c08a4a.
- Matcha: enso, 4a6b35 / 8fbf6a.
- Latte: heart, a8714a.
- Coffee: steam, b8a796.
- Ice cream: sprinkles.
- Northern lights:
  - light half: aurora, 1fae84 / 2a8fb0 / 7c5fd6;
  - dark half: aurora, 5fe3b0 / 4cc3d9 / a78bfa.
- Nocturnal:
  - light half: moon, 7a70e0 / 3d3680;
  - dark half: moon, b9b3ff / d9d7f0.
- Halloween:
  - light half: pumpkin, e2701a / 4d7a2a;
  - dark half: pumpkin, ff8a2a / 9ad36a.
- Christmas: snow, 1f6b45 / f1ece0.

- [ ] **Step 1:** Implement. These are views with no VerbKit logic, so the verification is the build plus the screen.
- [ ] **Step 2:** Build for iOS and macOS. Expected: no errors, apart from the known macOS plist error.
- [ ] **Step 3:** On the simulator:
  - Verbs in Light, Northern lights dark and Pastel: motif beside the large title, inline title on scroll.
  - A finished verb quiz in Light (red teacher's circle, red score) and Sand (raked rings, ink score).
  - AX5 results.
- [ ] **Step 4:** Commit: "Theme personality: title motifs and results stamps".

### Task 3: Alternate icons — generator, assets, project and the switch

**Files:**
- Modify: `scripts/generate-icon.swift`:
  - Replace `teacherPath`/`sumiPath` with `StampShape`.
  - Convert `SVGPathData.parse` elements to a `CGPath`.
  - Keep the primary icon and launch image unchanged; regenerate and check the diff.
  - Add a table of the ten sets: paper and ink hexes from the board's `SETS`, stamp kinds and colours.
  - Write `App/Assets.xcassets/AppIcon-<theme>.appiconset` for the nine non-Light themes, each with `icon-1024.png`, `icon-1024-dark.png` and `icon-1024-tinted.png`, plus `Contents.json` shaped like the primary set's iOS entries.
  - Write a 120 pt preview per set into `App/Assets.xcassets/IconPreview-<theme>.imageset`, for the Settings row.
- Modify: `Makefile`. Add `icons: ## Regenerate the app icons and launch image (FONT=path to ShipporiMinchoB1-Bold.ttf)`. It copies the script to a temp dir as `main.swift`, compiles it with `swiftc` together with `Packages/VerbKit/Sources/VerbKit/Seal/{StampShape,SVGPathData}.swift`, and runs it with `--font $(FONT) $(CURDIR)`. Update the usage line in the script header and the AGENTS.md trap to say `make icons FONT=…`.
- Modify: `project.yml`. In the iOS app target add `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` with the nine names and `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS: YES`. Then run `make project` and `make check-project`.
- Create: `App/Theme/AppIconSwitcher.swift`. On iOS it applies an `IconChange` with `UIApplication.shared.setAlternateIconName` when `supportsAlternateIcons`; on macOS it does nothing.
- Modify: `App/Theme/ThemePickerView.swift`. Below Seasonal themes, on iOS only, add a card with:
  - the `Toggle("App icon matches theme")` (`paperSwitch()`), stored at `AppIconMatching.defaultsKey` in `.appGroup`;
  - the selected theme's icon preview at 44 pt;
  - the footnote "Changes the Home Screen icon when you pick a theme. iOS confirms each change."

  Tapping a swatch and flipping the switch call `AppIconMatching.change` with `UIApplication.shared.alternateIconName` and apply the result.

- [ ] **Step 1:** Run `make icons FONT=<scratchpad>/font/ShipporiMinchoB1-Bold.ttf`. Expected:
  - `git diff --stat` shows the primary icon PNGs, launch PNGs and `SealGlyph.swift` byte-identical (or a pixel diff of 0);
  - nine new icon sets and ten previews.
- [ ] **Step 2:** Run `make project` and `make check-project`, then build for iOS. Expected: no errors. `actool` lists the alternate icons in the built `Info.plist` (`CFBundleAlternateIcons`).
- [ ] **Step 3:** On the simulator:
  - With the switch on, tap Matcha. Expected: the system alert, and the Matcha icon on the Home Screen.
  - With Seasonal on, set the simulator's date to October and tap Light. Expected: no icon change.
  - Turn the switch off. Expected: the primary icon.
- [ ] **Step 4:** Update the spec row 6 to "(built)", add the new symbols to the AGENTS.md tables, and commit: "Theme personality: alternate app icons".
