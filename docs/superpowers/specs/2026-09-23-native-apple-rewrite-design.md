# Native Apple Rewrite — Design

**Date:** 2026-09-23
**Status:** Approved, pending spec self-review sign-off

## Summary

Rewrite the JP Verb Conjugation app from a React/Tauri web+desktop app into a
single native Swift/SwiftUI project targeting iOS, iPadOS, and macOS. This
replaces the current repo contents entirely (`src/`, `src-tauri/`, `public/`,
and the npm/Tauri tooling are removed).

Beyond a faithful port of the existing features (verb list, search/filter,
verb detail + examples, Kahoot-style quiz, dark mode), this rewrite also adds:

- Persisted preferences (appearance, quiz question count)
- Quiz score history
- A home screen widget and Siri/Shortcuts support
- A GitHub-hosted verb data source, synced into a local on-device database
- An expanded conjugation form set (potential, volitional, passive,
  causative, causative-passive, both conditionals, imperative, たい-form),
  populated via a JMdict + Tatoeba content pipeline (section 9)

All pieces are designed together here; implementation is expected to
proceed in roughly this order: core port → persistence → history → widgets,
with the content pipeline and expanded form set developed in parallel since
they're independent of the app's UI work (they only share the `VerbForms`
schema).

## 1. Project & platform foundations

- **Repo**: this Xcode project replaces the current Tauri/web project
  entirely. `src/`, `src-tauri/`, `public/`, `package.json`,
  `package-lock.json`, `tsconfig.json`, `vite.config.ts`, `index.html`,
  `.firebaserc`, and `firebase.json` are removed once the native app is in
  place.
- **Targets**:
  - One multiplatform **App** target ("JP Verb Conjugation") covering iOS,
    iPadOS, and macOS natively — true SwiftUI multiplatform (not Mac
    Catalyst).
  - One **Widget Extension** target for the home screen widget, added when
    that phase of work starts.
- **Shared package**: a local Swift package, `VerbKit`, holds everything
  platform-agnostic — models, data fetching/sync, quiz logic, SwiftData
  persistence, and App Intents. Both the App target and the Widget Extension
  depend on it. This keeps the logic unit-testable independent of any UI and
  gives the widget/Shortcuts access to the same data and logic as the app
  without duplication.
- **Deployment target**: iOS 17 / iPadOS 17 / macOS 14 minimum. This unlocks
  SwiftData, the `@Observable` macro, and current `NavigationSplitView`
  behavior, all of which meaningfully simplify the implementation.
- **Distribution**: personal use (direct Xcode install) for now; TestFlight
  and AltStore distribution planned later. No App Store release is in scope
  for this design.
- **Bundle IDs**: `dev.martinloeseth.jpverbconjugation` (app),
  `dev.martinloeseth.jpverbconjugation.widget` (widget extension), sharing
  App Group `group.dev.martinloeseth.jpverbconjugation`.

## 2. Navigation & screen structure

- **iPhone (compact width)**: `NavigationStack`. Root screen is the verb
  list — `.searchable` search field, filter chips (All / Irregular / Ru /
  U), collapsible "verb type guide" panel, て-form legend. Tapping a verb
  pushes a **Verb Detail** screen (description, notes, buttons for Examples
  / Test this verb / Jisho, and the full form breakdown — see below).
- **Verb Detail form layout**: with the expanded form set (section 9) there
  are up to 18 forms per verb, too many for a flat list on iPhone. The
  detail screen groups them into collapsible sections — "Polite" (masu ±
  present/past), "Plain" (short ± present/past), "て-form", and "Advanced"
  (potential, volitional, passive, causative, causative-passive, ば/たら
  conditionals, imperative, たい) — with Polite/Plain/て-form expanded by
  default and Advanced collapsed, matching how textbooks typically
  introduce these forms in tiers. Same grouped layout on all platforms; on
  iPad/Mac the extra width just means less scrolling, not a different
  structure.
- **iPad/Mac (regular width)**: `NavigationSplitView`. The same verb list
  becomes the sidebar; selecting a verb shows Verb Detail in the trailing
  pane instead of pushing. Same view code as iPhone — `NavigationSplitView`
  handles the compact/regular collapse automatically.
- **Examples**: `.sheet` presented from Verb Detail, listing example
  sentences per form.
- **Quiz**: `.fullScreenCover` on iOS/iPadOS (matches the current
  full-viewport takeover); a separate resizable window on macOS. Same
  `QuizView`/`QuizViewModel`, different presentation wrapper per platform.
- **Settings**: `.sheet` on iOS/iPadOS; a native **Settings scene** (⌘,) on
  macOS, backed by the same form content.
- **History**: a toolbar button (clock icon) on the verb list opens a
  **History** sheet — aggregate stats (average score, streak, count over
  time) plus a list of past quiz attempts.
- **Appearance**: tri-state "System / Light / Dark" control (not the
  current binary toggle), persisted via `@AppStorage`, defaulting to System.
- **First launch / data loading**: see section 4 — a dedicated screen shown
  before any verb data exists locally.
- **External links** ("Suggest a verb" → GitHub issue, "Jisho" lookup):
  native `openURL` environment action on all platforms.

## 3. Quiz engine (in `VerbKit`)

- **Question generation**: `buildQuestions(verbs:count:)` ports the existing
  shuffle/distractor logic — same-verb wrong answers plus cross-verb wrong
  answers, deduplicated, capped at 3 distractors — as a pure, UI-independent
  function.
- **Quiz timing**: the current 20s-per-question countdown becomes a
  `QuizViewModel` (`@Observable`) driven by `TimelineView(.periodic(...))`
  or a repeating `Task`/`Task.sleep` loop, ticking `timeLeft` down and
  flipping `timedOut` at zero.
- **Results**: end-of-quiz results (score, per-question correct/incorrect
  breakdown) feed both the on-screen results view and a persisted
  `QuizAttempt` record (section 5).

## 4. Data layer (GitHub-sourced + local SwiftData cache)

- **Source of truth**: `verbs.json` stays in this repo (moved to e.g.
  `data/verbs.json` once the web app files are removed) and is fetched at
  runtime from its `raw.githubusercontent.com` URL. This preserves the
  existing "suggest a verb via GitHub issue → maintainer edits the JSON →
  everyone gets it automatically" workflow, now without requiring an app
  release to ship new verbs.
- **Manifest**: a small `data/manifest.json` alongside it —
  `{"version": "1.2.0", "sha256": "<hash of verbs.json content>"}` — bumped
  whenever `verbs.json` changes. The app fetches this tiny file first on
  every sync check; only when its `version`/`sha256` differ from the last
  values stored locally (`UserDefaults`) does it fetch and parse the full
  `verbs.json`. This avoids downloading and re-decoding the whole verb file
  on every launch when nothing changed, and the hash doubles as an
  integrity check — if the fetched `verbs.json`'s computed hash doesn't
  match the manifest's declared hash, that's treated as
  `failed(.malformedData)` (corrupted/incomplete download) rather than
  silently accepting bad data.
- **Local store**: a SwiftData `Verb` model (flattened form fields or a
  nested `Codable` `VerbForms` attribute; `[VerbExample]` stored as a
  `Codable` array attribute), in the shared App Group container so the
  widget/Shortcuts extension can read it too.
- **Expanded `VerbForms` schema**: alongside the existing 9 fields
  (`masu_pos`, `masu_neg`, `masu_past`, `masu_past_neg`, `te`, `short_pos`,
  `short_neg`, `short_past`, `short_past_neg`), 9 new fields are added:
  `potential`, `volitional`, `passive`, `causative`, `causative_passive`,
  `conditional_ba`, `conditional_tara`, `imperative`, `tai`. Each holds the
  base (plain, non-past affirmative) form — e.g. `potential: "食べられる"` —
  not a full further-conjugated matrix (potential/passive/causative are
  themselves conjugatable verbs, but chaining that out to every
  tense/polarity is out of scope; flag if you actually want that depth).
  Note that potential and passive are orthographically identical for
  ichidan verbs (both `食べられる`) — both fields are still populated
  (with the same string), and the detail UI can note the overlap rather
  than hide one. See section 9 for how these are generated.
- **`VerbDataFetching` protocol**: abstracts fetching the manifest and the
  verb data so sync logic is unit-testable with a mock, independent of real
  network calls.
- **First launch** (empty local store) — a dedicated **"Loading verb data"**
  screen, state-machine driven:
  1. `checking` — quick connectivity check via `NWPathMonitor` before
     attempting the fetch.
  2. `fetching` — spinner while the manifest and (if needed) `verbs.json`
     requests are in flight (timeout, e.g. 15s).
  3. `failed(.offline)` — "No internet connection" messaging; the screen
     auto-retries when `NWPathMonitor` reports connectivity restored, and
     also offers a manual "Try Again" button.
  4. `failed(.serverUnreachable)` — device is online but the GitHub request
     itself failed (timeout/5xx/DNS) — distinct copy from "no internet,"
     since the fix differs.
  5. `failed(.malformedData)` — fetched but couldn't decode — generic
     "something went wrong, try again."
  6. `success` — seeds SwiftData, proceeds into the normal list/detail UI.
- **Subsequent launches**: local SwiftData already has data, so the app
  opens straight into the UI (fully offline-capable from here on) while a
  background `Task` checks `manifest.json`. If its version/hash differs
  from what's stored locally, `verbs.json` is fetched and the local store
  is **replace-synced** (remote JSON is the source of truth — verbs removed
  remotely are removed locally too). Never blocks the UI; failures here are
  silent since cached data remains valid.
- **Widget/Shortcuts**: read only from the local SwiftData store — no
  network fetch of their own, since widget extensions have tight execution
  budgets and the main app owns all networking.

## 5. Persistence & cross-target sharing

- **Preferences** (appearance, quiz question count): `@AppStorage`, stored
  in the shared App Group container so the widget can read them (e.g.
  respecting quiz-length preference when deep-linking into a quiz).
- **Quiz history**: a `QuizAttempt` SwiftData model (`date`, `verbCount`,
  `score`, `total`) — lean by design, enough for a stats/history view
  (average score, streak, count over time), not full per-question replay.
  Shares the same `ModelContainer`/App Group as the verb cache.

## 6. Widgets & Shortcuts

- **Widget**: a small/medium WidgetKit widget showing a glanceable "verb of
  the moment" (random verb + one conjugated form), refreshing on a timeline
  (e.g. every few hours). Tapping deep-links into the app, opening that
  verb's detail. Display-only — not an interactive tap-to-answer quiz in the
  widget itself.
- **Shortcuts/App Intents** (in `VerbKit`): `StartQuizIntent(questionCount:)`
  lets Siri/Shortcuts launch straight into a quiz; `GetRandomVerbIntent`
  returns a verb + form as text, usable in Shortcuts automations (e.g. a
  scheduled notification). These also back the widget's timeline data, so
  the logic is written once.
- **Deep linking**: a small set of intents/URL targets ("open verb detail",
  "start quiz") that both widget taps and Shortcuts invocations resolve
  through.

## 7. Error handling

- Network/connectivity errors during first-launch data loading are a
  first-class, designed part of the app (section 4) — distinct states for
  offline, server-unreachable, and malformed data, each with appropriate
  messaging and retry behavior.
- Background re-sync failures on subsequent launches are silent — cached
  data remains valid, so there's nothing actionable to show the user.
- SwiftData/App Group container failures get a one-time console log; these
  are effectively "can't happen on a correctly provisioned build," not
  something to build user-facing recovery UI for.

## 8. Testing

- Unit tests on the `VerbKit` package cover: quiz question/distractor
  generation, search/filter matching, JSON decoding against the real data
  file, and the fetch/sync logic (manifest-unchanged skip, manifest-changed
  full sync, and hash-mismatch-on-`verbs.json` corruption handling) via the
  injected `VerbDataFetching` mock.
- UI is verified by running the app in Simulator per platform rather than
  SwiftUI snapshot/UI tests, given this is a personal-scale app.

## 9. Content pipeline (JMdict + Tatoeba)

A maintenance-time tool, separate from the Swift app, that (re)generates
`data/verbs.json` and `data/manifest.json`. It doesn't ship inside the app
or run on a user's device — it's what a maintainer runs before committing a
data update.

- **Location**: `scripts/generate-verb-data/`, a standalone Python tool
  (Python fits naturally here since `jmdict-simplified` is plain JSON and
  Tatoeba's export is straightforward to process with it — no need to
  match the app's Swift toolchain for a script that never ships).
- **Verb selection**: a maintainer-edited `target-verbs.txt` (dictionary
  forms, one per line) controls which verbs are included — the pipeline
  does **not** import all of JMdict's tens of thousands of verb entries.
  Curated scope matters for a learning app; this keeps growth intentional.
- **Steps**:
  1. Look up each target verb in a `jmdict-simplified` (common-only,
     English) release for kanji, reading, gloss (→ `meaning`), and its verb
     POS tag (→ ichidan/godan/irregular classification).
  2. Run a rule-based conjugation engine (ported from / cross-checked
     against `jconj`'s conjugation tables) to generate all 18 `VerbForms`
     fields per verb from its dictionary form and class.
  3. Pull Tatoeba's Japanese-English sentence-pair export and, for each
     verb, substring-match its conjugated surface forms against sentence
     text to source `examples`, tagged by which form appears, capped at a
     couple of examples per form and preferring shorter sentences.
  4. Merge into the existing `data/verbs.json`: hand-curated prose fields
     (`description`, `notes`) on verbs that already exist are preserved
     untouched; only `forms`/`examples` are regenerated. New verbs get a
     `"description": "TODO: write description"` placeholder for a
     maintainer to fill in — the pipeline doesn't attempt to generate that
     kind of pedagogical prose.
  5. Bump `manifest.json`'s version and recompute its `sha256`.
- **Review flow**: run manually (locally, or via a manually-dispatched
  GitHub Action) and opened as a PR — not auto-merged, and not run on a
  schedule. Since the app treats whatever's on `main` as safe to sync to
  every user automatically (section 4), generated content (example-sentence
  selection especially) gets a human glance before it's reachable.

## Proposed project layout

```
JPVerbConjugation.xcodeproj
App/                          # App target
  JPVerbConjugationApp.swift
  Views/
    VerbListView.swift
    VerbDetailView.swift
    ExamplesView.swift
    QuizView.swift
    SettingsView.swift
    HistoryView.swift
    DataLoadingView.swift     # first-launch network-required screen
  Resources/                  # assets, Info.plist, entitlements
Widget/                       # Widget extension target
  VerbWidget.swift
Packages/
  VerbKit/
    Sources/VerbKit/
      Models/                 # Verb, VerbForms, VerbExample, TeGroup, VerbType, QuizAttempt
      Data/                   # VerbDataFetching, GitHubVerbFetcher, VerbSyncService, VerbStore
      Quiz/                   # buildQuestions, QuizViewModel
      Intents/                # StartQuizIntent, GetRandomVerbIntent
      Persistence/            # ModelContainer + App Group setup
    Tests/VerbKitTests/
data/
  verbs.json                  # source of truth, fetched via raw.githubusercontent.com
  manifest.json                # {version, sha256} of verbs.json, checked before re-fetching
scripts/
  generate-verb-data/          # maintainer-run Python pipeline, not shipped in the app
    target-verbs.txt           # curated list of dictionary-form verbs to include
    generate.py                # JMdict lookup + conjugation engine + Tatoeba example sourcing
```
