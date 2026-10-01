# Grammar-Rule Widget and Widget-Link Dismissal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A "Grammar Rule" Home/Lock Screen widget that opens its lesson when tapped, and widget (`verbtable://`) links that always reach the target screen even when a sheet or the quiz is open.

**Architecture:** One generic pure day-pick (`DailyPick`) in VerbKit now backs both `VerbPick` and the grammar widget. `RootView` dismisses every presented sheet/cover before it hands an incoming route to `MainTabView`. The widget bundle gains a second widget (own kind, intent, provider and views) that reads grammar points from the same App Group store.

**Tech Stack:** Swift 5 mode, SwiftUI, WidgetKit, App Intents, SwiftData, XcodeGen, XCTest.

**Spec:** Approved in chat (design summary in the Goal above and the Global Constraints). The existing widget design is `docs/superpowers/specs/2026-10-01-widgets-romaji-search-design.md`.

## Global Constraints

- iOS 26 / macOS 26, Swift 5 mode. Package tests: `swift test --package-path Packages/VerbKit` (293 pass today; all must stay green). Tests are XCTest.
- Work only in the git worktree `/private/tmp/claude-501/-Users-mlj-dev-playground-jp-verb-conjugation-app/908cd4a7-6c49-4de7-a8e1-0667a185fc63/scratchpad/main-wt` (branch `grammar-widget`); never touch `/Users/mlj/dev/playground/jp-verb-conjugation-app` itself (another branch is checked out there).
- Xcode schemes `JPVerbConjugation_iOS` and `JPVerbConjugation_macOS`; run `xcodegen generate` after adding files. iOS build: `xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination 'id=4DB21AA8-1057-4014-A2C0-6D4968330CA5' -derivedDataPath .build-dd build`. macOS: `-scheme JPVerbConjugation_macOS -destination 'platform=macOS' -derivedDataPath .build-dd-mac CODE_SIGNING_ALLOWED=NO`. Never commit `.build-dd*/` or PNGs; `git add` explicit paths. Tracked generated files `App/Info.plist` and `Widgets/Info.plist` are committed if they change.
- The Write/Edit tools may be blocked for repo paths; use Bash heredocs/python.
- Grammar widget: new widget kind `"GrammarRuleWidget"`, display name "Grammar Rule"; modes Lesson of the day (default), Random lesson, Pick a lesson; lesson of the day changes at local midnight (same two-entry timeline as the verb widget), random every 3 hours, pick never; Pick falls back to lesson of the day if the lesson no longer exists. Families `.systemSmall`, `.systemMedium` and, on iOS only, `.accessoryRectangular`, `.accessoryInline`. Tap opens `Route.grammar(point.id).url` (`verbtable://grammar/<id>`). Empty store text exactly "Open Verb Table to load verbs". Same navy-to-black gradient and white text as the verb widget (`Color(red: 0.043, green: 0.063, blue: 0.149)`). Widgets never write the store.
- Grammar widget content: small = title, level, summary (3 lines max); medium = small plus the first usage's first example (`point.usages.first?.examples.first`: `jp` and `en`); rectangular = title + summary (1 line); inline = title.
- All widgets reload when grammar points change as well as verbs.
- Commit messages end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

---

### Task 1: Generic DailyPick

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Widget/DailyPick.swift`
- Modify: `Packages/VerbKit/Sources/VerbKit/Widget/VerbPick.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/DailyPickTests.swift`

**Interfaces:**
- Produces: `public enum DailyPick { public static func element<T>(of items: [T], on date: Date, calendar: Calendar = .current) -> T?; public static func random<T>(of items: [T], using generator: inout some RandomNumberGenerator) -> T? }`. `VerbPick.verbOfTheDay` / `randomVerb` keep their exact signatures and results and delegate to it.

- [ ] **Step 1: Write the failing tests** (`DailyPickTests.swift`):

```swift
import XCTest
@testable import VerbKit

final class DailyPickTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let items = ["a", "b", "c", "d", "e", "f", "g"]

    private func date(_ day: Int, hour: Int = 15) -> Date {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = day; components.hour = hour
        return calendar.date(from: components)!
    }

    func testSameDayGivesSameElement() {
        XCTAssertEqual(
            DailyPick.element(of: items, on: date(5, hour: 1), calendar: calendar),
            DailyPick.element(of: items, on: date(5, hour: 23), calendar: calendar)
        )
    }

    func testConsecutiveDaysCycleThroughTheList() throws {
        let picks = try (1...7).map { try XCTUnwrap(DailyPick.element(of: items, on: date($0), calendar: calendar)) }
        XCTAssertEqual(Set(picks), Set(items))
        let eighth = try XCTUnwrap(DailyPick.element(of: items, on: date(8), calendar: calendar))
        XCTAssertEqual(eighth, picks[0])
    }

    func testDifferentCalendarsAgree() {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = calendar.timeZone
        for day in 1...7 {
            XCTAssertEqual(
                DailyPick.element(of: items, on: date(day), calendar: buddhist),
                DailyPick.element(of: items, on: date(day), calendar: calendar)
            )
        }
    }

    func testEmptyGivesNil() {
        XCTAssertNil(DailyPick.element(of: [Int](), on: date(1), calendar: calendar))
        var generator = SystemRandomNumberGenerator()
        XCTAssertNil(DailyPick.random(of: [Int](), using: &generator))
    }

    func testRandomComesFromTheList() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<20 {
            XCTAssertTrue(items.contains(DailyPick.random(of: items, using: &generator)!))
        }
    }

    func testWorksOnGrammarPoints() {
        let points = GrammarFixture.points
        XCTAssertNotNil(DailyPick.element(of: points, on: date(3), calendar: calendar))
    }
}
```

- [ ] **Step 2: Run** `swift test --package-path Packages/VerbKit --filter DailyPickTests` — expect FAIL (`DailyPick` undefined).

- [ ] **Step 3: Implement.** `DailyPick.swift` holds the body currently in `VerbPick.verbOfTheDay` (the Gregorian-with-the-caller's-time-zone decomposition and `daysSinceEpoch`, copied with its doc comment) generalised to `[T]`, and `random` using `items.randomElement(using:)`. Then reduce `VerbPick` to:

```swift
public enum VerbPick {
    public static func verbOfTheDay(verbs: [Verb], on date: Date, calendar: Calendar = .current) -> Verb? {
        DailyPick.element(of: verbs, on: date, calendar: calendar)
    }
    public static func randomVerb(verbs: [Verb], using generator: inout some RandomNumberGenerator) -> Verb? {
        DailyPick.random(of: verbs, using: &generator)
    }
}
```

Remove the now-unused private helper from `VerbPick` (it moves to `DailyPick`).

- [ ] **Step 4: Run** the filtered tests (PASS), `--filter VerbPickTests` (still PASS, unchanged), then the whole suite (all green).

- [ ] **Step 5: Commit** `git add Packages/VerbKit && git commit -m "Extract a generic DailyPick shared by verb and grammar widgets"`.

---

### Task 2: Widget links dismiss presented screens

**Files:**
- Modify: `App/RootView.swift`, `App/VerbListView.swift` (guide sheet state only)

**Interfaces:**
- Consumes: `RootView.incomingRoute`, existing presentation state (`showingExamples`, `showingSettings`, `quizQuestions`, `topicSheetVerbs`, `pendingQuestions`), `VerbListView.showGuide`.
- Produces: an incoming `verbtable://` link first clears every presented sheet/cover, then sets `incomingRoute`.

- [ ] **Step 1:** Lift the Guide sheet's state out of `VerbListView` so `RootView` can clear it: change `@State private var showGuide = false` in `VerbListView` to `@Binding var showGuide: Bool` (add it to the memberwise init order at the call site in `RootView.verbsTab`: pass `showGuide: $showingGuide`), and add `@State private var showingGuide = false` to `RootView`.

- [ ] **Step 2:** In `RootView`'s `.onOpenURL`, before assigning `incomingRoute`, add:

```swift
        .onOpenURL { url in
            guard let route = Route(url: url) else { return }
            // Anything presented over the list would hide the page the link opens.
            showingExamples = false
            showingSettings = false
            showingGuide = false
            topicSheetVerbs = nil
            pendingQuestions = nil
            quizQuestions = nil
            incomingRoute = route
        }
```

- [ ] **Step 3: Build** iOS and macOS (Global Constraints). Both must succeed.

- [ ] **Step 4: Verify on the simulator** (iPhone 17 Pro; `xcodegen generate`, build, `xcrun simctl install`/`launch` the built app, bundle id `dev.martinloeseth.jpverbconjugation`; use `xcrun simctl openurl 4DB21AA8-1057-4014-A2C0-6D4968330CA5 'verbtable://verb/%E3%81%AE%E3%82%80'` and `verbtable://grammar/potential`; screenshots lag taps by 1-2 s, wait between steps): for each of Settings sheet, Examples sheet, Guide sheet, topic sheet and a running quiz, open the app into that state, send the link (the first `openurl` per scheme may show an "Open in Verb Table?" system prompt — tap Open), and confirm the sheet/quiz is gone and the verb page (or the Grammar tab's lesson) is showing. Report what you saw for each state, and anything you could not check.

- [ ] **Step 5: Commit** `git add App && git commit -m "Dismiss sheets and the quiz when a widget link opens"`.

---

### Task 3: The Grammar Rule widget

**Files:**
- Create: `Widgets/GrammarWidget.swift` (loader, entry, provider, widget), `Widgets/GrammarWidgetIntent.swift`, `Widgets/GrammarWidgetViews.swift`
- Modify: `Widgets/VerbTableWidgets.swift` (add the widget to the bundle), `App/JPVerbConjugationApp.swift` (reload on grammar changes)

**Interfaces:**
- Consumes: `DailyPick`, `Route.grammar(_:).url`, `GrammarPoint`, `SwiftDataGrammarPersisting.loadAllGrammarPoints()`, `matchesGrammarSearch`, the existing `Widgets/` patterns (`VerbLoader`, `VerbProvider`, `VerbWidgetIntent`, `VerbWidgetView`), and `UserDefaults`-free store access via `VerbModelContainer.make()`.
- Produces: `GrammarRuleWidget` (kind `"GrammarRuleWidget"`).

- [ ] **Step 1: Loader, entry, provider, widget** (`GrammarWidget.swift`), mirroring `Widgets/VerbWidget.swift` (read that file first and keep the same structure and the same midnight/3-hour/never timelines, the two-entry midnight rule, the iOS-only accessory families):

```swift
@MainActor
enum GrammarLoader {
    static func points() -> [GrammarPoint] {
        guard let container = try? VerbModelContainer.make() else { return [] }
        let persisting = SwiftDataGrammarPersisting(modelContext: ModelContext(container))
        return (try? persisting.loadAllGrammarPoints()) ?? []
    }
}

struct GrammarEntry: TimelineEntry {
    let date: Date
    /// nil while the app has not downloaded any data yet.
    let point: GrammarPoint?
}
```

`GrammarProvider: AppIntentTimelineProvider` with `placeholder` returning a sample `GrammarPoint` (build one in `GrammarWidgetViews.swift` as `GrammarPoint.sample` with a title, summary, level and one usage/example; check `GrammarPoint`'s memberwise initialiser in `Packages/VerbKit/Sources/VerbKit/Models/GrammarPoint.swift`), `choose(for:at:)` using `DailyPick.element` / `DailyPick.random` / the picked id with fallback to the lesson of the day. `GrammarRuleWidget` uses `AppIntentConfiguration(kind: "GrammarRuleWidget", intent: GrammarWidgetIntent.self, provider: GrammarProvider())`, `configurationDisplayName("Grammar Rule")`, `description("A grammar lesson from Verb Table, on your Home or Lock Screen.")`.

- [ ] **Step 2: Intent** (`GrammarWidgetIntent.swift`), mirroring `Widgets/VerbWidgetIntent.swift`: `GrammarWidgetMode: AppEnum` (cases `lessonOfTheDay`, `random`, `pick`; display "Lesson of the day", "Random lesson", "Pick a lesson"), `GrammarChoice: AppEntity` (`id`, `title`; `displayRepresentation` shows the title) with an `EntityStringQuery` backed by `GrammarLoader` and `matchesGrammarSearch`, and `GrammarWidgetIntent: WidgetConfigurationIntent` with the `mode` parameter (default `.lessonOfTheDay`), an optional `lesson: GrammarChoice?` shown only for Pick via `parameterSummary`. Use `static let` for the statics as the verb intent does.

- [ ] **Step 3: Views** (`GrammarWidgetViews.swift`): `GrammarWidgetView(entry:)` with the content rules in Global Constraints, `.widgetURL(Route.grammar(point.id).url)` on the non-empty layout, `containerBackground(for: .widget)` gradient for home families and `Color.clear` for accessory families, the exact empty text, level accent colour (beginner `Color(red: 0.176, green: 0.831, blue: 0.749)`, intermediate `Color(red: 0.655, green: 0.545, blue: 0.980)`), the iOS-only `#if os(iOS)` split for the accessory families as in `VerbWidgetViews.swift`, and previews (small, medium, rectangular on iOS) using `GrammarPoint.sample`.

- [ ] **Step 4: Bundle and reload.** Add `GrammarRuleWidget()` to `VerbTableWidgets.body`. In `App/JPVerbConjugationApp.swift` extend the existing `.onChange(of: verbStore.verbs)` reload so widgets also reload when `verbStore.grammarPoints` changes (add a second `.onChange(of: verbStore.grammarPoints) { WidgetCenter.shared.reloadAllTimelines() }`).

- [ ] **Step 5: Build** (`xcodegen generate`, iOS, macOS). Both must succeed; fix API mismatches minimally and list each deviation in the report.

- [ ] **Step 6: Verify on the simulator** (install the built app; app data must be loaded; long-press the Home Screen, tap +, search "Grammar Rule"): add small and medium; check the lesson of the day shows, the edit screen offers the three modes and the lesson picker only for Pick, Pick a lesson changes the widget, and tapping the widget opens that lesson in the Grammar tab (cold launch after terminating the app, and while the app is in the background). Also confirm the Verb Table widget still taps through to its verb. Report what you saw and what you could not verify.

- [ ] **Step 7: Commit** `git add Widgets App && git commit -m "Add the Grammar Rule widget"`.
