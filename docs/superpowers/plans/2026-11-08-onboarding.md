# Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A first-run flow of five pages (welcome, levels, furigana, theme, first verb) that a new install shows once, after the launch hand-off. It writes the three settings and opens 食べる or the app. Existing installs never see it.

**Architecture:**
- **VerbKit** gets the parts that can be tested:
  - `OnboardingProgress` decides once per launch whether to show the flow, and survives the app being killed half-way.
  - `OnboardingChoices` holds the picks, refuses to empty the levels, and writes them to the App Group defaults.
  - `LevelSettings.studying(_:amongEach:)` turns "levels I study" into the hidden set without leaving the verbs or lessons empty.
- **App** gets `OnboardingView` (five pages, each a small view) and a reusable `ThemeSwatch` taken out of `ThemePickerView`.
- `RootView` shows `OnboardingView` in place of the tabs, underneath the existing `LaunchHandoff` overlay. The seal therefore fades to the welcome page, not to the tabs.

**Tech Stack:** Swift 6, SwiftUI (iOS 26, macOS 26), XCTest in `Packages/VerbKit`.

**Spec:** `docs/superpowers/specs/2026-11-06-paper-ink-redesign-design.md`, row 5 of "Boards → plans". Board: "Onboarding" (`project/Onboarding.dc.html` on the canvas https://claude.ai/artifact/7eCLPFjJnWRoGB2n85ocr2).

## Global Constraints

- **Branch:** `claude/onboarding`, from `origin/main`.
- **Architecture:** VerbKit stays UI-free (Foundation only). Every user-facing string lives in App. No change under `data/`. No new dependency, download or asset.
- **Spec rules:**
  - Liquid Glass on chrome only. The pages sit on `palette.paper`, options on `palette.card` with a `rule` outline.
  - Content buttons use `.paper` / `.paperSecondary`.
  - Red never appears; nothing here is marked.
  - Every kanji gets furigana when furigana is on: Japanese goes through `JapaneseText`. The one exception is the furigana page's "OFF" sample, which shows the off state on purpose.
  - Never colour alone: a selected option has a 2 pt `ink` border **and** a filled check (levels), or the `.isSelected` trait and a ring (themes).
  - Text tokens are at least 4.5:1. Only `ink`, `muted` and `onButton`-on-`button` colour text.
- **Who sees it:** new installs only. An install that has ever accepted verb data, or has a stored level or furigana setting, skips it for good. A flow left unfinished (app killed) shows again on the next launch.
- **Defaults on the pages:**
  - levels N5 and N4 picked;
  - furigana on;
  - theme Light.
  - The flow never changes Appearance or Seasonal themes.
- **Theme page swatches, in this order:** `light`, `pastel`, `matcha`, `latte`, `northernLights`, `nocturnal`. Each is named and drawn as the half that is showing, as in `ThemePickerView`. The board's separate "Dark" swatch is now the dark half of Light (plan 2b), so Pastel takes its place. Owner confirmed 2026-11-09.
- **Copy (exact, from the board):**
  - Progress: five bars; accessibility label "Step N of 5". "Back" from page 2 on.
  - Page 1:
    - headword 活用 (72 pt Mincho W6, furigana かつよう), title "Verb Table";
    - body "Conjugate Japanese verbs, read grammar lessons and counters, and keep a word bank of your own. Everything works offline.";
    - button "Get started";
    - caption "Four quick choices. All of them can be changed later."
  - Page 2:
    - "Which levels are you studying?" / "Lists, quizzes and widgets show only these. Search still finds everything.";
    - rows "N5 Beginner", "N4 Elementary", "N3 Intermediate", "N2 Upper intermediate", "N1 Advanced".
  - Page 3:
    - "Show furigana?" / "Readings above every kanji. Turn them off once you can read without them.";
    - options "ON" and "OFF", each showing 毎朝パンを食べます。
  - Page 4: "Pick a look" / "You can change it any time. There are more in Settings, including seasonal ones."
  - Page 5:
    - "You’re set" / "Start with a verb everyone needs on day one.";
    - the card 食べる with "to eat · Ru-verb · N5" and a chevron;
    - summary "N5, N4 · furigana on · Light".
  - Buttons: "Continue" on pages 2–4, "Open Verb Table" on page 5.
- **Mac is parked:** the flow is shared code and will appear on macOS too, but it is checked on iOS only.
- **Tests:** `make test-swift`.
- **iOS build:** `make project && xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination 'generic/platform=iOS Simulator' build -quiet`.
- **macOS build:** the same command with `-scheme JPVerbConjugation_macOS -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO`. It passes when there are no Swift `error:` lines.
- **AGENTS.md:** each task adds its shared symbols to the tables in the same commit.
- **Release:** no TestFlight or App Store release.

## Review Focus

1. **An existing user updates the app.**
   - Expected: they never see onboarding, even though the new keys are absent.
   - Covered by Task 1, `testAnInstallThatHasAcceptedVerbsSkipsAndRemembers`.
2. **The app is killed on page 3 of a fresh install.** By the next launch the bundled install has written the verb version, which looks like an existing install.
   - Expected: onboarding shows again.
   - Covered by Task 1, `testAnUnfinishedFlowShowsAgainAfterDataArrived`.
3. **Someone studying only N3 (or only N1).** The verbs exist only at N5 and N4.
   - Expected: the verb list is not empty. The hardest level each dataset has stays visible.
   - Covered by Task 1, `testStudyingKeepsEveryDatasetVisible`.
4. **Tapping the last picked level.**
   - Expected: it stays picked, so the levels can never be empty.
   - Covered by Task 1, `testTheLastLevelCannotBeUnpicked`.
5. **Applying the choices clobbers a setting the flow doesn't own.** For example, Appearance pinned to Dark by a migration, or Seasonal on.
   - Expected: only the theme id, the hidden levels and furigana change.
   - Covered by Task 1, `testApplyWritesOnlyItsThreeSettings`.

---

### Task 1: Onboarding progress, choices and levels (VerbKit)

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Onboarding/OnboardingProgress.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Onboarding/OnboardingChoices.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Furigana/FuriganaSetting.swift`
- Modify: `Packages/VerbKit/Sources/VerbKit/Levels/LevelSettings.swift` (add `studying`)
- Modify: `Packages/VerbKit/Sources/VerbKit/Data/UserDefaultsSyncStateStore.swift` (add `hasAcceptedVerbs(in:)`)
- Modify: `App/RootView.swift:14`, `App/SettingsView.swift:15` (use `FuriganaSetting.defaultsKey` in place of the `"showFurigana"` literal)
- Create: `Packages/VerbKit/Tests/VerbKitTests/OnboardingTests.swift`
- Modify: `Packages/VerbKit/Tests/VerbKitTests/LevelSettingsTests.swift`
- Modify: `AGENTS.md` (VerbKit table)

**Interfaces:**
- Produces:
  - `public enum FuriganaSetting { public static let defaultsKey = "showFurigana" }`. This is the key the App already uses; the value is unchanged.
  - `UserDefaultsSyncStateStore.hasAcceptedVerbs(in defaults: UserDefaults) -> Bool` (`public static`). It is true when the verb version key (`VerbKit.lastSyncedManifest.version`) holds a string.
  - `public enum OnboardingProgress`:
    - `public static let completedKey = "onboardingCompleted"` and `public static let pendingKey = "onboardingPending"`, both App Group keys.
    - `public static func begin(appGroup: UserDefaults, standard: UserDefaults) -> Bool`. It returns whether to show the flow, checking in this order:
      1. completed → false;
      2. pending → true;
      3. existing install (`UserDefaultsSyncStateStore.hasAcceptedVerbs(in: standard)`, or `appGroup` has `LevelSettings.defaultsKey` or `FuriganaSetting.defaultsKey`) → set completed, false;
      4. otherwise → set pending, true.
    - `public static func finish(appGroup: UserDefaults)`: sets completed and removes pending.
  - `public struct OnboardingChoices: Equatable, Sendable`:
    - `public private(set) var levels: Set<JLPTLevel>` (default `[.n5, .n4]`);
    - `public var furigana: Bool` (default `true`);
    - `public var theme: ThemeID` (default `.light`);
    - `public init()`;
    - `public mutating func toggle(_ level: JLPTLevel)`. It never empties `levels`.
    - `public func apply(to appGroup: UserDefaults, amongEach datasets: [Set<JLPTLevel>])`. It saves `LevelSettings.studying(levels, amongEach:)`, sets `FuriganaSetting.defaultsKey` and sets `ThemeChoice.themeKey`. It reads the stored `ThemeChoice` first and keeps its appearance and seasonal values.
  - `LevelSettings.studying(_ picked: Set<JLPTLevel>, amongEach datasets: [Set<JLPTLevel>]) -> LevelSettings` (`public static`). It hides every `JLPTLevel` not in `picked`. Then, for each non-empty dataset with no visible level, it unhides that dataset's hardest level (`max()`).

- [ ] **Step 1: Write the failing tests** in `OnboardingTests.swift` and `LevelSettingsTests.swift`. Use a fresh suite per test, as `ThemeChoiceTests.freshDefaults` does.

```swift
func testAFreshInstallShowsOnceThenNotAfterFinishing() {
    let (group, standard) = (fresh("g"), fresh("s"))
    XCTAssertTrue(OnboardingProgress.begin(appGroup: group, standard: standard))
    OnboardingProgress.finish(appGroup: group)
    XCTAssertFalse(OnboardingProgress.begin(appGroup: group, standard: standard))
    XCTAssertNil(group.object(forKey: OnboardingProgress.pendingKey))
}
func testAnInstallThatHasAcceptedVerbsSkipsAndRemembers() {
    let (group, standard) = (fresh("g"), fresh("s"))
    standard.set("2026-11-01", forKey: "VerbKit.lastSyncedManifest.version")
    XCTAssertFalse(OnboardingProgress.begin(appGroup: group, standard: standard))
    XCTAssertTrue(group.bool(forKey: OnboardingProgress.completedKey))
}
func testAStoredLevelOrFuriganaSettingCountsAsAnExistingInstall() {
    let group = fresh("g"); group.set("", forKey: LevelSettings.defaultsKey)
    XCTAssertFalse(OnboardingProgress.begin(appGroup: group, standard: fresh("s")))
}
func testAnUnfinishedFlowShowsAgainAfterDataArrived() {
    let (group, standard) = (fresh("g"), fresh("s"))
    XCTAssertTrue(OnboardingProgress.begin(appGroup: group, standard: standard))
    standard.set("2026-11-01", forKey: "VerbKit.lastSyncedManifest.version")   // bundled install ran, app killed
    XCTAssertTrue(OnboardingProgress.begin(appGroup: group, standard: standard))
}
func testTheLastLevelCannotBeUnpicked() {
    var choices = OnboardingChoices()
    choices.toggle(.n4); choices.toggle(.n5)
    XCTAssertEqual(choices.levels, [.n5])
    choices.toggle(.n1)
    XCTAssertEqual(choices.levels, [.n5, .n1])
}
func testApplyWritesOnlyItsThreeSettings() {
    let group = fresh("g")
    ThemeChoice(theme: .latte, appearance: .dark, seasonal: true).save(to: group)
    var choices = OnboardingChoices(); choices.furigana = false; choices.theme = .matcha
    choices.apply(to: group, amongEach: [[.n5, .n4], [.n5, .n4, .n3, .n2]])
    XCTAssertEqual(ThemeChoice.load(from: group), ThemeChoice(theme: .matcha, appearance: .dark, seasonal: true))
    XCTAssertEqual(group.object(forKey: FuriganaSetting.defaultsKey) as? Bool, false)
    XCTAssertEqual(LevelSettings.load(from: group).hidden, [.n3, .n2, .n1])
}
// LevelSettingsTests
func testStudyingHidesWhatIsNotPicked() {
    XCTAssertEqual(LevelSettings.studying([.n5, .n4], amongEach: [[.n5, .n4]]).hidden, [.n3, .n2, .n1])
}
func testStudyingKeepsEveryDatasetVisible() {
    let settings = LevelSettings.studying([.n3], amongEach: [[.n5, .n4], [.n5, .n4, .n3, .n2], []])
    XCTAssertEqual(settings.hidden, [.n5, .n2, .n1])   // verbs keep N4, lessons already show N3
}
```

- [ ] **Step 2: Run the tests and confirm they fail.** Run `cd Packages/VerbKit && swift test --filter 'OnboardingTests|LevelSettingsTests'`. Expected: a compile failure on the missing symbols.
- [ ] **Step 3: Implement the files listed under Interfaces.** Then replace the two `"showFurigana"` literals in App with `FuriganaSetting.defaultsKey`.
- [ ] **Step 4: Run the tests and confirm they pass.** Run the same filter, then `make test-swift`. Expected: all pass.
- [ ] **Step 5: Update AGENTS.md and commit.**
  - AGENTS.md VerbKit table, three rows:
    - `OnboardingProgress`: show-once gate for the first-run flow, with an existing-install skip;
    - `OnboardingChoices`: the flow's picks and how they are written;
    - `FuriganaSetting.defaultsKey`.
  - Add `LevelSettings.studying(_:amongEach:)` to the `LevelSettings` row.
  - Commit message: `Onboarding: show-once gate, choices and studied levels`.

### Task 2: The five onboarding pages (App)

**Files:**
- Create: `App/Onboarding/OnboardingView.swift` (the pager: progress bars, Back, the pinned button, page switch)
- Create: `App/Onboarding/OnboardingPages.swift` (`WelcomePage`, `LevelsPage`, `FuriganaPage`, `ThemePage`, `FirstVerbPage`)
- Create: `App/Onboarding/OnboardingOption.swift` (the selectable card)
- Create: `App/Theme/ThemeSwatch.swift` (taken out of `ThemePickerView.swatch(_:)`)
- Modify: `App/Theme/ThemePickerView.swift` (use `ThemeSwatch`)
- Modify: `AGENTS.md` (components table)

**Interfaces:**
- Consumes: Task 1's `OnboardingChoices`. Also `ThemeID.displayName(isDark:)`, `ThemePalette.resolve(_:isDark:contrast:)`, `VerbType.typeLabel`, `JapaneseText`, `Font.headword(_:scale:)`, `PaperButtonStyle`, `RowChevron`.
- Produces:
  - `struct ThemeSwatch: View { let theme: ThemeID; let isSelected: Bool; var diameter: CGFloat = 50; var caption: String? = nil; let action: () -> Void }`. This is the existing swatch: paper, an ink lower band and a mark dot, the 3 pt `ink` ring when selected, and `.isSelected`. The name sits under it. `ThemePickerView` passes `caption` for the season month; onboarding passes `diameter: 66`, which is the board's 72 pt including the ring.
  - `struct OnboardingOption<Label: View>: View { let isSelected: Bool; let action: () -> Void; @ViewBuilder let label: () -> Label }`. It is a card button: `card` fill, a 14 pt radius, at least 54 pt tall, and a 2 pt `ink` border when selected or 1 pt `rule` when not. It has the `.isSelected` trait.
  - `enum OnboardingStep: Int, CaseIterable { case welcome, levels, furigana, theme, firstVerb }`, the pager's state.
  - `struct OnboardingView: View { let firstVerb: Verb?; let datasets: [Set<JLPTLevel>]; let onFinish: (Route?) -> Void }`. "Open Verb Table" calls `onFinish(nil)` and the 食べる card calls `onFinish(.verb("たべる"))`. Both first call `choices.apply(to: .appGroup, amongEach: datasets)` and `OnboardingProgress.finish(appGroup: .appGroup)`.

- [ ] **Step 1: Extract `ThemeSwatch` and switch `ThemePickerView` to it.** Build iOS. Expected: it succeeds, and Settings › Theme looks unchanged.
- [ ] **Step 2: Write `OnboardingOption` and `OnboardingView`.**
  - **Layout:** a top bar with "Back" (plain text button in `ink`, hidden on page 1) and the five progress bars. A bar is 6 pt tall; the current one is 22 pt wide and the others 6 pt. Bars up to the current step are `ink`, the rest `rule`. The bars are one accessibility element labelled "Step N of 5".
  - **Page area:** 24 pt side padding. Titles use `.title.bold()` (the board's 28 pt), body `.body` in `muted`.
  - **Pinned button:** at the bottom, in a `safeAreaInset`, styled `.paper`.
  - **Transitions:** pages change with `.animation(.smooth)` and a `.opacity` transition. With Reduce Motion on, no transition.
- [ ] **Step 3: Write the five pages.** Use the copy from Global Constraints.
  - **Welcome:** `JapaneseText("活用")` in `.headword(.largeTitle, scale: 2.1)`, about 72 pt.
  - **Levels:** one `OnboardingOption` per `JLPTLevel.allCases`. The label is the bold id and a `muted` hint. A trailing 24 pt check circle is filled `ink` with an `onButton` checkmark when picked, and outlined `rule` otherwise. The option calls `choices.toggle`.
  - **Furigana:** two options, each with a `muted` "ON"/"OFF" caption above `JapaneseText("毎朝パンを食べます。").font(.sentence(.title2))`. The ON sample sets `.environment(\.furiganaEnabled, true)` and the OFF sample `false`, whatever the stored setting.
  - **Theme:** a three-column `LazyVGrid` of `ThemeSwatch` for the six themes. Picking one sets `choices.theme` **and** writes `ThemeChoice.themeKey` at once, so the flow repaints live.
  - **First verb:** a `paperCard(cornerRadius: 16)` button. It holds `JapaneseText(verb.kanji ?? verb.dict)` in `.headword(.largeTitle)` with `.environment(\.furiganaEnabled, choices.furigana)`, then `"\(verb.meaning) · \(verb.type.typeLabel) · \(level)"` in `muted`, then `RowChevron()`.
    - The card is hidden when `firstVerb` is nil.
    - Below the card is the summary. It reads the visible levels from `LevelSettings.studying(choices.levels, amongEach: datasets)` among `JLPTLevel.allCases`, N5 first, joined with ", ". Then "furigana on" or "furigana off", then `choices.theme.displayName(isDark:)`, all joined with " · ".
- [ ] **Step 4: Add `#Preview`s.** One for each page, in Light and in Nocturnal dark. Build iOS and macOS. Expected: iOS succeeds, and macOS shows no Swift `error:` lines.
- [ ] **Step 5: Update AGENTS.md and commit.**
  - AGENTS.md components table: `ThemeSwatch` (a theme's swatch, picker and onboarding) and `OnboardingOption` (a selectable card with a 2 pt ink border).
  - Commit message: `Onboarding: the five pages`.

### Task 3: Show it once, after the launch hand-off (App)

**Files:**
- Modify: `App/JPVerbConjugationApp.swift` (call `OnboardingProgress.begin` first in `init()`, before `ThemeChoice.load`, and pass the result down)
- Modify: `App/RootView.swift` (show `OnboardingView` in place of the tabs; open the route on finish)

**Interfaces:**
- Consumes: Task 1's `OnboardingProgress.begin(appGroup:standard:)`; Task 2's `OnboardingView(firstVerb:datasets:onFinish:)`; `Route.verb(_:)`; RootView's existing `incomingRoute`.
- Produces: `RootView(showsOnboarding: Bool)`. RootView owns `@State private var onboarding: Bool`, starting from the init value.

- [ ] **Step 1: Wire the gate into the App.**
  - In `JPVerbConjugationApp.init()`, the very first line is `let firstRun = OnboardingProgress.begin(appGroup: .appGroup, standard: .standard)`. It must come before the stores are built, because the bundled install writes the verb version. Store it in a `let`.
  - Pass it as `RootView(showsOnboarding: firstRun)`.
- [ ] **Step 2: Replace the content in RootView's `Group`.**
  - Show `OnboardingView` when `onboarding` is true, else the existing `hasLocalData` / `DataLoadingView` switch.
  - Its arguments:
    - `firstVerb: verbStore.verbs.first { $0.id == "たべる" }`;
    - `datasets: [verbStore.verbs.levels(), verbStore.grammarPoints.levels()]`.
    - `onFinish`: `withAnimation(.smooth) { onboarding = false }`, then `incomingRoute = route`.
  - The `LaunchHandoff` overlay and `.themedRoot()` stay outermost, so the seal fades to page 1.
- [ ] **Step 3: Build iOS and macOS.** Expected: iOS succeeds, and macOS shows no Swift `error:` lines.
- [ ] **Step 4: Check on the simulator.**
  - **Fresh install:** erase the app first. Expected:
    - the seal fades to page 1;
    - Back, the bars and VoiceOver read "Step 2 of 5";
    - tapping N4 then N5 leaves N5 picked;
    - Matcha repaints the flow at once;
    - the furigana OFF card drops the ruby on the last page;
    - the summary reads "N5 · furigana off · Matcha";
    - the 食べる card opens 食べる's page on the Verbs tab;
    - Settings shows N4–N1 off and furigana off.
  - **Killed on page 3:** relaunch. Expected: page 1 again.
  - **Upgrade:** install `main`, launch once, install this branch. Expected: straight to the tabs.
  - **AX5:** pages scroll, and the pinned button stays reachable.
  - **Reduce Motion:** no page transition.
  - Take screenshots in Light and Nocturnal dark.
- [ ] **Step 5: Commit.** Message: `Onboarding: show it once on a new install, after the launch seal`.

### Task 4: Spec status and checks

**Files:**
- Modify: `docs/superpowers/specs/2026-11-06-paper-ink-redesign-design.md`

- [ ] **Step 1: Update the spec.**
  - Mark row 5 "(built)".
  - Add a short "Onboarding" paragraph covering:
    - new installs only, with the existing-install skip;
    - the default picks;
    - the six swatches;
    - that the flow never sets Appearance or Seasonal;
    - studied levels keep each dataset visible.
- [ ] **Step 2: Run the checks.** Run `make check`, `make check-project` and `make test-swift`. Expected: all pass.
- [ ] **Step 3: Commit.** Message: `Spec: onboarding built`.

---

## Self-review

- **Spec coverage:** levels (Task 1 + the levels page), furigana (the furigana page + apply), theme (the theme page + apply, live repaint), first verb (the first-verb page + the route in Task 3), board copy (Global Constraints), rules (Global Constraints, checked in Task 3, step 4). There are no gaps.
- **Placeholders:** none in the copy; every string is the board's. Owner decisions are listed below.
- **Types:**
  - `OnboardingChoices.apply(to:amongEach:)`, `LevelSettings.studying(_:amongEach:)` and `OnboardingProgress.begin(appGroup:standard:)` / `finish(appGroup:)` are spelled the same in Tasks 1–3.
  - `OnboardingView(firstVerb:datasets:onFinish:)` matches between Tasks 2 and 3.
- **Owner decisions:**
  - Pastel replaces the board's "Dark" swatch.
  - The default picks are N5 and N4, where today the default hides nothing.
  - The flow appears on macOS too, though Mac is parked.
  - "Hardest level stays visible" is the rule when the picked levels would empty a dataset.
