# JLPT Levels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give verbs and grammar lessons a JLPT level, let the user hide levels in Settings, and make search say when levels are hidden with a one-tap "All levels" scope.

**Architecture:** `JLPTLevel` and `LevelSettings` live in VerbKit (pure, tested; settings stored in the App Group defaults so the widgets read them too). The data files and persistence carry `jlpt`. The app filters lists, the quiz pool and the widgets through one `visible(in:)` helper; the lists add search scopes ("My levels" / "All levels") plus hidden-match hints.

**Tech Stack:** Swift 5 mode, SwiftUI (iOS 26 / macOS 26), SwiftData, WidgetKit, XcodeGen, XCTest, Python 3 data script.

**Spec:** `docs/superpowers/specs/2026-10-01-jlpt-levels-design.md`

## Global Constraints

- `JLPTLevel`: `n5, n4, n3, n2, n1`, raw values `"N5"`…`"N1"`, `CaseIterable`, `Codable`, `Hashable`, `Sendable`, `Comparable` with N5 smallest (easiest first).
- `Verb.jlpt: JLPTLevel?` and `GrammarPoint.jlpt: JLPTLevel?`, JSON key `jlpt`, missing = nil. **nil is always visible.** `GrammarLevel` and the grammar JSON key `level` are removed (the app is unreleased; no older build to support).
- **Ruling vs the spec:** the setting is stored as the *hidden* set, key `hiddenJLPTLevels` (comma-separated raw values, default empty), not the visible set, so a level added to the data later (for example N2) appears automatically instead of being hidden by an older choice. Everything else in the spec is unchanged.
- At least one level that exists in the data must stay visible (the last visible toggle is disabled).
- The setting lives in the App Group defaults suite `group.dev.martinloeseth.jpverbconjugation` (`UserDefaults.appGroup` in the app; the widgets use the same suite).
- Hidden levels leave: the verb list, the grammar list, the Random Quiz pool and the widgets' day/random picks. NOT hidden: direct navigation (`verbtable://` links, a lesson linked from a verb page, the selected item), *Test this verb*, and *Pick a verb/lesson* in the widgets.
- Search scopes: **My levels** (default) / **All levels**; the scope bar appears only when at least one level that exists in the data is hidden; scope is per search and resets to My levels when the search text is cleared/dismissed; it never changes the setting.
- Level summary text: a contiguous run of visible levels as a range with an en dash, best first ("N5–N4"), otherwise a comma list ("N5, N3"). Shown in the list subtitle only when something is hidden.
- Provisional curated data values: grammar `n-desu` N4, `potential` N4, `certainty` N3, `obligation` N3, `appearance` N3, `ppoi` N2, `teiru` N5, `teshimau` N4, `temiru` N4, `sugiru` N4; verbs N5 except しぬ, いそぐ, みせる, かえす which are N4.
- Work only in the git worktree `/private/tmp/claude-501/-Users-mlj-dev-playground-jp-verb-conjugation-app/908cd4a7-6c49-4de7-a8e1-0667a185fc63/scratchpad/levels-wt` (branch `levels`); never touch `/Users/mlj/dev/playground/jp-verb-conjugation-app` itself.
- Package tests: `swift test --package-path Packages/VerbKit` (299 pass today; all must stay green). Data check: `python3 scripts/update_data.py --check`; script tests: `python3 scripts/test_update_data.py`.
- Schemes `JPVerbConjugation_iOS` and `JPVerbConjugation_macOS`; `xcodegen generate` after adding files. iOS build: `xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination 'id=4DB21AA8-1057-4014-A2C0-6D4968330CA5' -derivedDataPath .build-dd build`; macOS: `-scheme JPVerbConjugation_macOS -destination 'platform=macOS' -derivedDataPath .build-dd-mac CODE_SIGNING_ALLOWED=NO`. iOS-only SwiftUI APIs (search scopes behaviours, `listSectionSpacing`, `searchToolbarBehavior`) need `#if os(iOS)` so macOS compiles. Never commit `.build-dd*/` or PNGs; `git add` explicit paths.
- The Write/Edit tools may be blocked for repo paths; use Bash heredocs/python. Commit messages end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

---

### Task 1: Levels in the model, persistence and data

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Models/JLPTLevel.swift`, test `Packages/VerbKit/Tests/VerbKitTests/JLPTLevelTests.swift`, test `Packages/VerbKit/Tests/VerbKitTests/RealJLPTDataTests.swift`
- Modify: `Packages/VerbKit/Sources/VerbKit/Models/Verb.swift`, `.../Models/GrammarPoint.swift`, `.../Persistence/VerbEntity.swift` (and its `toVerb()` / init usage in `SwiftDataVerbPersisting`), every use of `GrammarLevel` / `level:` (find with `grep -rn "GrammarLevel\|\.level\b\|level:" App Widgets Packages/VerbKit`), `scripts/update_data.py`, `scripts/test_update_data.py`, `data/verbs.json`, `data/grammar.json`, `data/manifest.json`

**Interfaces:**
- Produces: `public enum JLPTLevel: String, Codable, CaseIterable, Hashable, Sendable, Comparable`; `Verb.jlpt: JLPTLevel?` (memberwise init gains `jlpt: JLPTLevel? = nil`, placed after `teGroup`); `GrammarPoint.jlpt: JLPTLevel?` replacing `level` (init parameter `level: GrammarLevel` becomes `jlpt: JLPTLevel? = nil`, same position); `VerbEntity.jlpt: String?` (default nil, init parameter `jlpt: String? = nil`).

- [ ] **Step 1: Failing tests.** `JLPTLevelTests`: raw values round-trip through JSON; `JLPTLevel.n5 < .n4`; `allCases` order is N5…N1; a `Verb` decoded from JSON with `"jlpt": "N4"` has `.n4` and without the key has nil; same for `GrammarPoint` (use the existing grammar decoding fixture style in `GrammarDecodingTests`); a `VerbEntity` round-trip through `SwiftDataVerbPersisting` (in-memory container, see `SwiftDataVerbPersistingTests`) keeps `jlpt`, and a verb without a level stays nil. `RealJLPTDataTests`: every verb in `data/verbs.json` (via `RealVerbs.load()`) and every grammar point in `data/grammar.json` has a non-nil `jlpt`, and the grammar and verb values equal the curated values in Global Constraints (a dictionary in the test).

- [ ] **Step 2: Run** `swift test --package-path Packages/VerbKit --filter "JLPTLevelTests|RealJLPTDataTests"` — expect FAIL (does not compile).

- [ ] **Step 3: Implement.** `JLPTLevel`:

```swift
public enum JLPTLevel: String, Codable, CaseIterable, Hashable, Sendable, Comparable {
    case n5 = "N5", n4 = "N4", n3 = "N3", n2 = "N2", n1 = "N1"

    /// N5 (easiest) sorts first.
    public static func < (lhs: JLPTLevel, rhs: JLPTLevel) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}
```

Add `jlpt` to `Verb` and `GrammarPoint` (remove `GrammarLevel` and `GrammarPoint.level`), add the optional column to `VerbEntity` (default nil so existing rows migrate lightly) and map it in the persisting layer both ways, update every call site and existing test that used `GrammarLevel` / `level:` / `.beginner` / `.intermediate` (map beginner→.n5, intermediate→.n3 in test fixtures unless a test asserts real data, where use the curated value). The app/widget display of the level is done in later tasks: in this task make App/Widgets compile by temporary minimal edits only where `GrammarLevel` is referenced (e.g. `GrammarDisplay.swift` `extension JLPTLevel { var displayName: String { rawValue } }`, `GrammarListView`/`GrammarDetailView` use `point.jlpt?.displayName`, `GrammarWidgetViews` accent/level name switch on `JLPTLevel?`, sample uses `.n4`) — keep them tiny; the polish comes in Tasks 3 and 5.

- [ ] **Step 4: Data and script.** Add the `jlpt` key (curated values from Global Constraints) to every entry of `data/verbs.json` and `data/grammar.json` and remove the grammar `level` key. In `scripts/update_data.py` replace the grammar `level` validation with `jlpt` validation (must be one of N5…N1; required for grammar), and check an optional `jlpt` on verbs is valid if present when the verbs file is processed. Update `scripts/test_update_data.py` (the `level` fixtures and the two "bad level" tests become `jlpt` equivalents). Run `python3 scripts/update_data.py` (rewrites the manifest) then `--check` (must say "data is up to date") and `python3 scripts/test_update_data.py` (must pass).

- [ ] **Step 5: Run** the whole package suite — all green (existing count plus the new tests). Run the iOS and macOS builds — both succeed.

- [ ] **Step 6: Commit** `git add Packages/VerbKit App Widgets scripts data && git commit -m "Add JLPT levels to verbs and grammar, replacing the beginner/intermediate level"`.

---

### Task 2: LevelSettings and the visibility helpers

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Levels/LevelSettings.swift`, `Packages/VerbKit/Sources/VerbKit/Levels/Leveled.swift`, tests `Packages/VerbKit/Tests/VerbKitTests/LevelSettingsTests.swift`, `Packages/VerbKit/Tests/VerbKitTests/LeveledTests.swift`

**Interfaces:**
- Produces:

```swift
public struct LevelSettings: Equatable, Sendable {
    public static let defaultsKey = "hiddenJLPTLevels"
    public var hidden: Set<JLPTLevel>
    public init(hidden: Set<JLPTLevel> = [])
    public init(rawValue: String?)                      // "N4,N3"; nil/""/unknown tokens ignored
    public var rawValue: String                         // sorted N5…N1, comma-separated
    public func isVisible(_ level: JLPTLevel?) -> Bool   // nil is always visible
    public func anyHidden(among available: Set<JLPTLevel>) -> Bool
    public func canHide(_ level: JLPTLevel, among available: Set<JLPTLevel>) -> Bool   // false if it would leave no available level visible
    public func summary(among available: Set<JLPTLevel>) -> String?   // nil when nothing hidden among available; "N5–N4" / "N5, N3"
    public static func load(from defaults: UserDefaults? = nil) -> LevelSettings   // default: the App Group suite, falling back to .standard
    public func save(to defaults: UserDefaults? = nil)
}

public protocol Leveled { var jlpt: JLPTLevel? { get } }
extension Verb: Leveled {}
extension GrammarPoint: Leveled {}
public extension Sequence where Element: Leveled {
    func visible(in settings: LevelSettings) -> [Element]
    func hiddenCount(in settings: LevelSettings) -> Int
    func levels() -> Set<JLPTLevel>      // the levels present (nil skipped)
}
```

- [ ] **Step 1: Failing tests** covering: parse/serialise round trip and ordering (`LevelSettings(hidden: [.n3, .n5]).rawValue == "N5,N3"`); `init(rawValue: nil)`, `""`, `"bogus,N4"` (→ hidden `[.n4]`); `isVisible(nil)` true even when everything is hidden; `anyHidden(among:)` ignores hidden levels that are not in `available`; `canHide` false for the last available visible level, true otherwise, true for a level not in `available`; `summary` — nothing hidden → nil, available {N5,N4,N3}, hidden {N3} → "N5–N4", hidden {N4} → "N5, N3", hidden {N5,N4} → "N3", hidden {N5} → "N4–N3", single available visible level → just that level; `load`/`save` round trip through a `UserDefaults(suiteName: UUID().uuidString)`; `visible(in:)` keeps nil-level items and order, `hiddenCount`, `levels()`.

- [ ] **Step 2: Run** the filtered tests — expect FAIL. **Step 3: Implement** to satisfy them (default suite = `UserDefaults(suiteName: VerbModelContainer.appGroupIdentifier) ?? .standard`). **Step 4: Run** filtered then the whole suite — green.

- [ ] **Step 5: Commit** `git add Packages/VerbKit && git commit -m "Add LevelSettings and level visibility helpers"`.

---

### Task 3: Settings, badges, quiz pool and widget reload

**Files:**
- Modify: `App/SettingsView.swift`, `App/VerbRow.swift`, `App/GrammarDisplay.swift`, `App/GrammarListView.swift` (badge only), `App/GrammarDetailView.swift` (badge only), `App/RootView.swift` (quiz pool), `App/JPVerbConjugationApp.swift` (reload widgets when the setting changes)

**Interfaces:**
- Consumes: `LevelSettings`, `Leveled.visible(in:)`, `JLPTLevel`.

- [ ] **Step 1: Settings.** Add `@AppStorage(LevelSettings.defaultsKey, store: .appGroup) private var hiddenLevelsRaw = ""` and a **Levels** section (placed after Reading): one `Toggle("N5", isOn:)`… for each level present in the data (`Set(verbStore.verbs.levels()).union(verbStore.grammarPoints.levels())`, ordered N5…N1; read `VerbStore` from the environment), bound so on = visible. A toggle that `canHide` is false for is disabled when on. Footer: "Hidden levels are left out of lists, the quiz and the widgets. Search can still look at all levels." If the data has no levels yet, hide the section.

- [ ] **Step 2: Badges.** `JLPTLevel.displayName` returns the raw value (move/keep in `GrammarDisplay.swift`); grammar rows and the detail page show `point.jlpt?.displayName` (nothing when nil). `VerbRow` gets the same small capsule badge (`.font(.caption2.weight(.semibold))`, glass capsule, same as `GrammarRow`) after the dictionary form/kanji when `verb.jlpt` is non-nil.

- [ ] **Step 3: Quiz pool.** In `RootView`, `onRandomQuiz: { topicSheetVerbs = verbStore.verbs.visible(in: LevelSettings.load()) }` — reading the setting at tap time. If the visible pool is empty the sheet must still work (it already handles empty topics); do not change *Test this verb*.

- [ ] **Step 4: Widget reload.** `JPVerbConjugationApp`: reload widget timelines when `hiddenLevelsRaw` changes (an `@AppStorage` plus `.onChange`, placed with the existing reload `.onChange`s).

- [ ] **Step 5: Build** iOS and macOS. **Verify on the simulator** (iPhone 17 Pro; install over the current build; app data loaded): Settings shows the Levels toggles for the levels in the data only; the last visible toggle is disabled; badges show on verb rows and lessons; with some level hidden, Random Quiz only asks about verbs of visible levels (the real verbs are almost all N5/N4, so hide N5 to see the quiz pool shrink to the N4 verbs). Report what you saw and what you could not check.

- [ ] **Step 6: Commit** `git add App && git commit -m "Add the Levels setting, level badges and a quiz pool limited to visible levels"`.

---

### Task 4: Lists and search

**Files:**
- Modify: `App/VerbListView.swift`, `App/GrammarListView.swift`, optionally create `App/LevelSearch.swift` for shared pieces (scope enum, hint row, summary subtitle helper)

**Interfaces:**
- Consumes: `LevelSettings`, `Leveled.visible(in:)` / `hiddenCount`, existing `matchesSearch` / `matchesGrammarSearch`.

- [ ] **Step 1: Filtering.** Both lists read the hidden set via `@AppStorage(LevelSettings.defaultsKey, store: .appGroup)` and build a `LevelSettings`. A `@State var scope: LevelScope` (`mine` / `all`) selects the settings used for filtering: `mine` filters with the real settings, `all` with an empty settings (`LevelSettings()`). The scope resets to `mine` whenever the search text becomes empty.

- [ ] **Step 2: Scope bar.** When `settings.anyHidden(among: availableLevels)` apply `.searchScopes($scope)` with two scopes labelled "My levels" and "All levels" (and nothing when no level is hidden — implement as a small `ViewModifier` so the modifier is absent, not empty). Keep `searchToolbarBehavior(.minimize)` and the macOS `#if` splits compiling.

- [ ] **Step 3: Subtitle.** The verb list's `filterSummary` appends `settings.summary(among:)` (joined with " · ") when something is hidden and the scope is `mine`; the grammar list gets `navigationSubtitle(summary)` the same way (empty string when nothing to say). In scope `all` the subtitle drops the level part.

- [ ] **Step 4: Hints.** When scope is `mine`, search text is non-empty, and some items in hidden levels also match the search (count = matches under the empty settings minus matches under the real settings): if the visible results are non-empty, end the list with a row "N more in hidden levels — Search all levels" (a button that sets `scope = .all`); if the visible results are empty, replace the empty state with `ContentUnavailableView` titled "No match in <summary>" (summary from Global Constraints) describing "N in other levels" and an "All levels" button. When nothing hidden matches, keep today's behaviour exactly.

- [ ] **Step 5: Build** iOS and macOS. **Verify on the simulator:** hide N5 (verbs: only N4 remain visible) and search "taberu"/"eat" — the scope bar shows, My levels finds nothing for an N5 verb, the empty state offers All levels, tapping it lists the verb with its badge; a search that matches both shows the "N more" row; with nothing hidden there is no scope bar; scope returns to My levels after clearing the search; the subtitle shows "N4" style text only when something is hidden. Same checks on the Grammar tab (hide N5 so ている disappears). Report what you saw and what you could not check.

- [ ] **Step 6: Commit** `git add App && git commit -m "Hide levels in the lists, with search scopes and hidden-match hints"`.

---

### Task 5: Widgets pick from visible levels

**Files:**
- Modify: `Widgets/VerbWidget.swift`, `Widgets/GrammarWidget.swift`, `Widgets/GrammarWidgetViews.swift`

**Interfaces:**
- Consumes: `LevelSettings.load()`, `Leveled.visible(in:)`, `JLPTLevel`.

- [ ] **Step 1:** In each provider's `choose(for:at:)` filter the loaded verbs/lessons with `.visible(in: LevelSettings.load())` before the day/random pick. *Pick a verb/lesson* keeps using the unfiltered list; the fallback when the picked item is missing uses the filtered day pick. If the filtered list is empty fall back to the unfiltered list (never show the empty-state text because of levels). `LevelSettings.load()` must read the App Group suite (the widget is a separate process; it must not use `.standard`).

- [ ] **Step 2:** `GrammarWidgetViews`: replace the beginner/intermediate accent and name with a switch over `JLPTLevel?` (exhaustive, a distinct colour per level: N5 `Color(red: 0.176, green: 0.831, blue: 0.749)`, N4 `Color(red: 0.486, green: 0.831, blue: 0.992)`, N3 `Color(red: 0.655, green: 0.545, blue: 0.980)`, N2 `Color(red: 0.992, green: 0.792, blue: 0.243)`, N1 `Color(red: 0.973, green: 0.443, blue: 0.400)`, nil = white 0.8) and the label is the raw value (nothing when nil).

- [ ] **Step 3: Build** iOS and macOS. **Verify on the simulator:** with a Grammar Rule widget on the Home Screen, hide the level of the current lesson in the app's Settings and confirm the widget changes to a visible-level lesson (switch back to the Home Screen; widgets refresh when the setting changes); tap-through still opens the lesson. Report what you saw and what you could not check.

- [ ] **Step 4: Commit** `git add Widgets && git commit -m "Pick widget verbs and lessons from visible levels"`.
