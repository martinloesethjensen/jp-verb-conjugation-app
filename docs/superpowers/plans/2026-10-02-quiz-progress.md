# Quiz Progress and Weak Spots Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Save every answered quiz question, then offer a Weak spots quiz topic, a daily streak and Progress screen, a widget option that favours verbs you miss, and a history reset.

**Architecture:** An append-only `QuizAttemptEntity` in the App Group SwiftData store, wrapped by an `@Observable` `QuizHistoryStore` in VerbKit (like `VerbStore`). All maths (weakness, ranking, streaks, stats) is a pure `QuizProgress` struct over `[QuizAttempt]` with an injected calendar and clock. `QuizViewModel` gets an optional recorder closure; the topic sheet gets a Weak spots row; a Progress sheet and a Settings reset use the store; the widget reads the same store.

**Tech Stack:** Swift 5 mode, SwiftUI (iOS 26 / macOS 26), SwiftData, WidgetKit/App Intents, Swift Charts for the 7-day bars, XcodeGen, XCTest.

**Spec:** `docs/superpowers/specs/2026-10-02-quiz-progress-design.md`

## Global Constraints

- Work only in the git worktree `/private/tmp/claude-501/-Users-mlj-dev-playground-jp-verb-conjugation-app/908cd4a7-6c49-4de7-a8e1-0667a185fc63/scratchpad/progress-wt` (branch `progress`); never touch `/Users/mlj/dev/playground/jp-verb-conjugation-app` itself.
- Package tests: `swift test --package-path Packages/VerbKit` (322 pass today; all must stay green). Tests are XCTest. Data check `python3 scripts/update_data.py --check` must stay "data is up to date" (no data changes in this plan).
- Schemes `JPVerbConjugation_iOS` / `JPVerbConjugation_macOS`; run `xcodegen generate` after adding files. iOS build: `xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination 'id=4DB21AA8-1057-4014-A2C0-6D4968330CA5' -derivedDataPath .build-dd build`; macOS: `-scheme JPVerbConjugation_macOS -destination 'platform=macOS' -derivedDataPath .build-dd-mac CODE_SIGNING_ALLOWED=NO`. iOS-only SwiftUI APIs need `#if os(iOS)` so macOS compiles. Never commit `.build-dd*/` or PNGs; `git add` explicit paths.
- The app syncs data from GitHub `main` (which now has the JLPT data), so simulator checks need no data hack.
- The Write/Edit tools may be blocked for repo paths; use Bash heredocs/python. Commit messages end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Outcome rules: `correct`, `wrong`, `timedOut`. A *miss* is `wrong` or `timedOut`. Only `correct` and `wrong` are *answered* (count toward accuracy denominator, answers per day and the streak).
- Weakness per (verb, form) pair: take that pair's most recent 5 attempts, newest first; weights 5,4,3,2,1 by recency; weakness = sum(weight where miss) / sum(weight of all in window); a pair is **weak** when weakness > 0. Rank pairs by weakness descending, then most recent attempt descending, then (verb dict, form id) ascending for determinism.
- Streak: a local calendar day counts when it has ≥ 1 answered attempt. Current streak = consecutive counted days ending today, or ending yesterday if today has none yet; 0 if neither today nor yesterday counted. Best streak = the longest run in the history. Day boundaries use the injected `Calendar`.
- Progress numbers: `totalAnswered`, `accuracy` (correct / answered, nil when answered is 0), `last7Days` (7 entries oldest→newest ending today, answered count per day), `weakestVerbs` (top 5 by summed weakness of the verb's weak pairs), `weakestForms` (top 5 by summed weakness per form id across verbs); entries with 0 are omitted.
- Weak spots pool respects hidden JLPT levels (verbs passed in are already `visible(in: LevelSettings.load())`) and, for *Test this verb*, only that verb. The pool is never padded: fewer weak pairs than the question count means a shorter quiz. When there is no history the Weak spots row is shown disabled with "Answer some questions first". Reset deletes every attempt and reloads widget timelines; widgets also reload when a quiz ends.
- Hidden levels do not affect the Progress sheet (history shows everything).

---

### Task 1: Attempts model, persistence and the history store

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Quiz/QuizAttempt.swift`, `.../Persistence/QuizAttemptEntity.swift`, `.../Persistence/QuizHistoryPersisting.swift`, `.../Persistence/SwiftDataQuizHistoryPersisting.swift`, `.../Store/QuizHistoryStore.swift`
- Modify: `Packages/VerbKit/Sources/VerbKit/Persistence/VerbModelContainer.swift` (both schemas), `.../Quiz/QuizQuestion.swift` (`QuizQuestionKind` becomes `String`-raw)
- Test: `Packages/VerbKit/Tests/VerbKitTests/QuizHistoryStoreTests.swift`, `Packages/VerbKit/Tests/VerbKitTests/SwiftDataQuizHistoryPersistingTests.swift`

**Interfaces:**
- Produces:

```swift
public enum QuizOutcome: String, Sendable, Codable { case correct, wrong, timedOut
    public var isMiss: Bool { self != .correct }
    public var isAnswered: Bool { self != .timedOut } }
public struct QuizAttempt: Equatable, Sendable, Identifiable {
    public let id: UUID; public var verb: String; public var formID: String
    public var kind: QuizQuestionKind; public var outcome: QuizOutcome; public var date: Date
    public init(id: UUID = UUID(), verb: String, formID: String, kind: QuizQuestionKind, outcome: QuizOutcome, date: Date) }
@MainActor public protocol QuizHistoryPersisting {
    func loadAll() throws -> [QuizAttempt]; func append(_ attempt: QuizAttempt) throws; func deleteAll() throws }
@MainActor public final class SwiftDataQuizHistoryPersisting: QuizHistoryPersisting { public init(modelContext: ModelContext) … }
@MainActor @Observable public final class QuizHistoryStore {
    public private(set) var attempts: [QuizAttempt]
    public init(persisting: QuizHistoryPersisting)      // loads attempts (empty on failure)
    public func record(_ attempt: QuizAttempt)          // appends in memory and persists (persist failures are swallowed)
    public func reset()                                  // deleteAll + attempts = []
}
```

`QuizQuestionKind` becomes `public enum QuizQuestionKind: String, Sendable { case conjugate, identify }` (existing code only compares/matches cases, so this is source compatible). `QuizAttemptEntity` stores `id`, `verb`, `formID`, `kind` (raw), `outcome` (raw), `date`; attributes have no defaults requiring migration beyond the new table.

- [ ] **Step 1: Failing tests.** `SwiftDataQuizHistoryPersistingTests` (in-memory container via `VerbModelContainer.makeInMemory()`): append then loadAll returns the attempts in insertion/date order with every field intact; `deleteAll` empties; an unknown raw outcome/kind row is skipped on load, not crashing. `QuizHistoryStoreTests` with an in-memory test double conforming to `QuizHistoryPersisting`: `record` appends to `attempts` and persists once; `reset` clears both; construction loads existing attempts; a throwing persister leaves the store usable (in-memory attempts still update on record).
- [ ] **Step 2: Run** `swift test --package-path Packages/VerbKit --filter "SwiftDataQuizHistoryPersistingTests|QuizHistoryStoreTests"` — expect FAIL (types undefined).
- [ ] **Step 3: Implement** the types above; add `QuizAttemptEntity.self` to BOTH schemas in `VerbModelContainer`. `loadAll` sorts by `date` ascending then insertion.
- [ ] **Step 4: Run** the filtered tests (PASS) then the whole suite (all green); build iOS and macOS (the widget extension and app both open the container; the new table must not break the existing store).
- [ ] **Step 5: Commit** `git add Packages/VerbKit && git commit -m "Add quiz attempt storage and the QuizHistoryStore"`.

---

### Task 2: QuizProgress (weakness, streaks, stats)

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Quiz/QuizProgress.swift`, test `Packages/VerbKit/Tests/VerbKitTests/QuizProgressTests.swift`

**Interfaces:**
- Consumes: `QuizAttempt`, `QuizOutcome`, `QuizForm.all` (for form labels).
- Produces:

```swift
public struct WeakPair: Equatable, Sendable { public let verb: String; public let formID: String; public let weakness: Double }
public struct DayCount: Equatable, Sendable { public let day: Date; public let answered: Int }   // day = start of day
public struct WeakVerb: Equatable, Sendable { public let verb: String; public let weakness: Double }
public struct WeakForm: Equatable, Sendable { public let formID: String; public let label: String; public let weakness: Double }
public struct QuizProgress: Sendable {
    public init(attempts: [QuizAttempt], calendar: Calendar = .current, now: Date = Date())
    public var weakPairs: [WeakPair]                     // ranked per Global Constraints
    public func weakPairs(among verbs: Set<String>) -> [WeakPair]   // filtered by verb dict, same order
    public var currentStreak: Int
    public var bestStreak: Int
    public var totalAnswered: Int
    public var accuracy: Double?
    public var last7Days: [DayCount]
    public var weakestVerbs: [WeakVerb]
    public var weakestForms: [WeakForm]
    public var hasHistory: Bool
}
```

- [ ] **Step 1: Failing tests** (build attempts with a fixed Gregorian calendar and explicit dates; helper `attempt(verb, form, outcome, daysAgo, hour)`): weakness with a single miss among five correct (the miss's weight depends on its recency — newest miss weight 5 gives 5/15, oldest in window weight 1 gives 1/15); a pair with 6 attempts where the only miss is the oldest (outside the window of 5) is NOT weak; timeouts count as misses; a pair of all-correct attempts is not weak; ranking: higher weakness first, ties by most recent attempt, then verb/form id; `weakPairs(among:)` filters; streak: today counted → current = run length including today; today empty but yesterday counted → run ending yesterday; neither → 0; a gap breaks the run; best streak is the longest historical run; timeouts alone do not count a day; two attempts the same day count once; DST day and a 23:59/00:01 pair in `Europe/Copenhagen` count as two consecutive days; `last7Days` has exactly 7 entries oldest→newest and counts only answered; accuracy = correct/answered (timeouts excluded from the denominator), nil when no answered attempts; `weakestVerbs` sums weakness across a verb's weak pairs, sorted, max 5, zero omitted; `weakestForms` aggregates by form id with the label from `QuizForm.all`, max 5; `hasHistory` false for empty.
- [ ] **Step 2: Run** `--filter QuizProgressTests` — expect FAIL. **Step 3: Implement** as specified (pure, no I/O). **Step 4: Run** filtered then whole suite — green.
- [ ] **Step 5: Commit** `git add Packages/VerbKit && git commit -m "Add QuizProgress: weakness, streaks and stats"`.

---

### Task 3: Recording hook and question building from pairs

**Files:**
- Modify: `Packages/VerbKit/Sources/VerbKit/Quiz/QuizResult.swift` (add `formID`), `.../Quiz/QuizViewModel.swift` (recorder), `.../Quiz/QuizGenerator.swift` (pairs entry point)
- Test: `Packages/VerbKit/Tests/VerbKitTests/QuizViewModelTests.swift` (append), `Packages/VerbKit/Tests/VerbKitTests/QuizGeneratorTests.swift` (append)

**Interfaces:**
- Consumes: `QuizAttempt`, `QuizOutcome`.
- Produces: `QuizResult.formID: String` (new init parameter `formID: String` after `formLabel`; update every call site, including tests); `QuizViewModel.init(questions: [QuizQuestion], recorder: ((QuizAttempt) -> Void)? = nil, now: @escaping () -> Date = Date.init)` calling the recorder exactly once per `choose` (outcome `correct` or `wrong`) and once per `markTimedOut` (`timedOut`), with `verb = question.verb.dict`, `formID = question.form.id`, `kind = question.kind`; `public func buildQuestions(pairs: [(verb: Verb, form: QuizForm)], among verbs: [Verb], count: Int, kinds: [QuizQuestionKind] = [.conjugate, .identify]) -> [QuizQuestion]`.

- [ ] **Step 1: Failing tests.** ViewModel: a recorder collects attempts — `choose` right answer records `correct`, wrong answer `wrong`, timeout `timedOut`; one record per answered/timed-out question; a second `choose` on the same question records nothing; the recorded verb/formID/kind/date (injected `now`) are right; no recorder means no crash and the existing behaviour (existing tests unchanged apart from `QuizResult` init updates). Generator: `buildQuestions(pairs:among:count:)` returns questions for exactly the given pairs in the given order, at most `count`; fewer pairs gives fewer questions (no padding); a pair with a string collision is skipped like in `buildQuestions(verbs:topics:…)`; each question's choices contain the correct answer once and ≥ 2 choices; conjugate distractors come from the same verb's other forms then other verbs in `among`; identify choices are labels of the same verb's forms (all topics); kinds respected.
- [ ] **Step 2: Run** the filtered tests — expect FAIL. **Step 3: Implement.** Refactor `QuizGenerator.swift` so the question construction from a pool entry is shared by both entry points (extract the body into a private function taking the entry, the topics used for same-verb forms (`Set(QuizTopic.allCases)` for pairs), the `verbs` list and the kinds); keep `buildQuestions(verbs:topics:count:kinds:)` behaviour byte-identical (its existing tests must pass unchanged). The pairs entry point does NOT shuffle the pool.
- [ ] **Step 4: Run** filtered then whole suite — green; build iOS and macOS.
- [ ] **Step 5: Commit** `git add Packages/VerbKit App && git commit -m "Record quiz answers through a hook and build questions from verb/form pairs"` (include any App call sites of `QuizResult`).

---

### Task 4: Wire recording, the Weak spots row and the widget reload

**Files:**
- Modify: `App/JPVerbConjugationApp.swift` (create and inject the history store), `App/RootView.swift`, `App/QuizTopicSheet.swift`, `App/QuizView.swift`

**Interfaces:**
- Consumes: `QuizHistoryStore`, `QuizProgress`, `QuizViewModel(questions:recorder:)`, `buildQuestions(pairs:among:count:)`, `LevelSettings.load()` / `visible(in:)`.
- Produces: the topic sheet reports a `QuizSelection` instead of a topic set: `enum QuizSelection { case topics(Set<QuizTopic>); case weakSpots }`; `QuizTopicSheet(verbs:weakSpotCount:onStart:onCancel:)` with `onStart: ([Verb], QuizSelection) -> Void`.

- [ ] **Step 1: Store.** In `JPVerbConjugationApp` create `QuizHistoryStore(persisting: SwiftDataQuizHistoryPersisting(modelContext: context))` from the same `ModelContext` used for the other persisting objects, hold it in `@State`, and inject with `.environment(quizHistory)` on `RootView` and the macOS Settings scene (Task 5 uses it there).
- [ ] **Step 2: Recording.** `QuizView` reads the history store from the environment and builds its view model with a recorder `{ quizHistory.record($0) }`; "Practise missed" creates its replacement view model with the same recorder. When the quiz ends (results screen appears, and also when it is dismissed mid-way) call `WidgetCenter.shared.reloadAllTimelines()` (import WidgetKit; a single `onChange(of: viewModel.finished)` plus `onDisappear`, no double-reload hazard to worry about).
- [ ] **Step 3: Weak spots row.** `RootView` passes `weakSpotCount` to the topic sheet = `QuizProgress(attempts: quizHistory.attempts).weakPairs(among: Set(verbsInPlay.map(\.dict))).count` where `verbsInPlay` is the sheet's verbs. For Random Quiz those verbs are already level-visible; for *Test this verb* it is that single verb. `QuizTopicSheet` shows a first row **Weak spots** with the count ("N pairs"); disabled with secondary text "Answer some questions first" when 0; selecting it deselects the topic rows (it is a third `Choice` case) and Start sends `.weakSpots`. `RootView.onStart` for `.weakSpots`: take `weakPairs(among:)`, map to `(verb, form)` pairs (look the verb up in the verbs in play and the form in `QuizForm.all` by id; skip any not found), take the first `quizQuestionCount`, shuffle them, `buildQuestions(pairs:among:count:)`, and present as today (empty result behaves like an empty topic quiz today: Start does nothing). `.topics` behaves exactly as before.
- [ ] **Step 4: Build** iOS and macOS. **Verify on the simulator** (iPhone 17 Pro; install over the current app, launch): the Weak spots row is disabled with the hint on a fresh install; answer a few questions wrongly and rightly in a normal quiz; reopen the topic sheet — the row now shows a count; start a Weak spots quiz and confirm it asks only about verbs/forms you missed; answer them correctly and confirm the count shrinks after a few rounds. Screenshots lag taps by 1-2 s; wait between steps; pass the simulator id on every tool call. Report what you saw and what you could not check.
- [ ] **Step 5: Commit** `git add App && git commit -m "Record quiz answers and add the Weak spots quiz topic"`.

---

### Task 5: Progress sheet and Settings reset

**Files:**
- Create: `App/QuizProgressView.swift`
- Modify: `App/VerbListView.swift` (toolbar button + sheet), `App/SettingsView.swift` (reset)

**Interfaces:**
- Consumes: `QuizHistoryStore`, `QuizProgress`, `QuizForm.all`.
- Produces: `QuizProgressView` (a sheet with its own `NavigationStack`, title "Progress", a Done button).

- [ ] **Step 1: Progress sheet.** Sections: **Streak** (current and best, "days"), **Overall** (answered, accuracy as "NN%" or "—"), **Last 7 days** (Swift Charts `BarMark` per day, weekday abbreviation on the axis, answered count), **Weakest verbs** (up to 5: verb, kanji if known — look verbs up from `VerbStore` — and a simple weakness bar or label), **Weakest forms** (up to 5: form label). Empty state (`ContentUnavailableView`, "No quiz history yet", with a line saying answers appear here) when `!hasHistory`. The progress is computed from `quizHistory.attempts` each render with the default calendar and now.
- [ ] **Step 2: Toolbar.** `VerbListView` gets a `chart.bar` toolbar button (primary action, next to Guide and Random Quiz) that presents the sheet; manage its state in `RootView` like the other sheets and clear it in the existing widget-link dismissal (`onOpenURL` in `RootView`).
- [ ] **Step 3: Reset.** `SettingsView`: a destructive **Reset quiz history** button in the Quiz section, a `confirmationDialog` ("Delete all saved quiz results? This clears your streak and weak spots.", destructive "Reset", Cancel); on confirm call `quizHistory.reset()` and `WidgetCenter.shared.reloadAllTimelines()`. The macOS Settings scene has the store through the environment from Task 4.
- [ ] **Step 4: Build** iOS and macOS. **Verify on the simulator:** with answers recorded (do two short quizzes), the Progress sheet shows streak 1 / best 1, the answered count and accuracy matching what you answered, today's bar, weakest verbs/forms; reset from Settings (confirm dialog, Cancel does nothing, Reset clears) and the sheet then shows the empty state and the Weak spots row is disabled again. Report what you saw and what you could not check.
- [ ] **Step 5: Commit** `git add App && git commit -m "Add the Progress sheet and a quiz history reset"`.

---

### Task 6: Widget favours verbs you miss

**Files:**
- Modify: `Widgets/VerbWidgetIntent.swift`, `Widgets/VerbWidget.swift`

**Interfaces:**
- Consumes: `SwiftDataQuizHistoryPersisting` (read-only), `QuizProgress`, `Leveled.visible(in:)`, `DailyPick`.
- Produces: `VerbWidgetIntent.favourMisses: Bool` (`@Parameter(title: "Favour verbs I miss", default: false)`).

- [ ] **Step 1: Intent.** Add the boolean parameter; show it in the parameter summary for *Verb of the day* and *Random verb* only (not for *Pick a verb*).
- [ ] **Step 2: Provider.** In `choose(for:at:)`, after filtering by visible levels: when `favourMisses` and the mode is day or random, load attempts read-only (`SwiftDataQuizHistoryPersisting(modelContext: ModelContext(container)).loadAll()`, empty on failure), compute `QuizProgress(attempts:).weakPairs(among: Set(visibleVerbs.map(\.dict)))`, keep the verbs (in their original order) that have at least one weak pair, and if that list is non-empty use it as the pool for the day/random pick; otherwise fall back to the visible pool. The widget never writes.
- [ ] **Step 3: Build** iOS and macOS. **Verify on the simulator:** record some misses for a specific verb in the app (a few wrong answers on one verb), set the widget's "Favour verbs I miss" on (long-press the widget, Edit Widget), and confirm it shows a verb you missed (switch to the Home Screen; the widget reloads after the quiz); with the switch off or no history it behaves as before. Report what you saw and what you could not check.
- [ ] **Step 4: Commit** `git add Widgets && git commit -m "Let the verb widget favour verbs you miss"`.
