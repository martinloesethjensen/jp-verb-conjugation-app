# Agent guide — Verb Table

A native SwiftUI Japanese verb-conjugation app for iOS 26 and macOS 26. This file is for coding
agents: it records the architecture, the shared code that already exists, and the duplication that
must **not** be "cleaned up" casually.

## Repository map

| Path | Contents |
|---|---|
| `App/` | App target: SwiftUI views, view models, App Intents, Spotlight, speech, reminders |
| `Widgets/` | Widget extension: WidgetKit views and intents |
| `Packages/VerbKit/` | Shared Swift package: models, data sync, SwiftData persistence, quiz logic, search, routing. Tests run with `swift test` |
| `data/` | Published JSON data and the signed `manifest.json` |
| `scripts/` | Python data generation/signing/audio tools and shell helpers |
| `docs/` | Specs, plans, signing docs |

`JPVerbConjugation.xcodeproj` is generated from `project.yml` with XcodeGen and is **not
committed**. Never edit it; edit `project.yml` and run `make project`.

## Architecture rules

1. **Dependency direction:** `App` and `Widgets` import `VerbKit`; `VerbKit` never imports either.
2. **VerbKit is UI-free.** It currently has no SwiftUI/UIKit/AppKit/WidgetKit dependency. Keep it
   that way: models, sync, persistence, search, routes and other testable logic go there. SwiftUI
   views, colors, fonts and platform APIs stay in `App/` or `Widgets/`.
3. **Platform code:** one shared source tree for iOS and macOS. Use `#if os(iOS)` / `#if os(macOS)`
   only where APIs genuinely differ; do not fork whole screens.
4. **Widget sources are explicit.** The widget target compiles `Widgets/**` plus only
   `App/VerbColors.swift` (listed in `project.yml`). If a widget needs another App file, add it to
   the widget target's `sources` and run `make check-project`.
5. **Stores are injected, not global.** `JPVerbConjugationApp` creates the `@MainActor @Observable`
   stores and injects them with `.environment(...)`. Views read them with
   `@Environment(StoreType.self)`. Previews/tests construct their own.
6. **Persist before confirming.** Every sync service returns a result but records nothing.
   The store must durably save the payload *first*, then call `confirmSynced(_:)`, so a failed save
   is retried on the next launch. Do not simplify this ordering.
7. **Wording is a UI concern.** User-facing strings belong in `App/` (see `GrammarDisplay.swift`).
   `DataSyncStatus` in VerbKit is a known existing exception, not a pattern to copy.
8. **Data is signed.** Changes under `data/` must be regenerated with `make data` and signed with
   `make sign-commit`. CI rejects unsigned, stale or tampered data.

## Future Android client

Android is planned once the iOS app is ready. It is not in this repository yet, and no
cross-platform framework has been chosen. Until that changes:

- Treat the published `data/` files, the signed `manifest.json` scheme, stable verb/counter ids,
  `verbtable://` routes, and the versioned `.wordbank` JSON archive as **cross-platform contracts**.
  Keep them documented and free of Apple-only assumptions (App Group paths, SwiftData models,
  `UserDefaults`, Swift `Codable` quirks).
- Keep reusable rules — conjugation, quiz generation, search/normalization, import/export — in
  plain Swift types and functions, not in views. The `*Persisting` protocols are the storage seam;
  an Android client would provide equivalent SQLite/Room implementations.
- Do not add a cross-platform framework now, and do not distort the native SwiftUI app for a
  hypothetical port. Sharing may later mean a Kotlin implementation of the same contracts, a KMP
  extraction of the pure logic, or data-format reuse only — that is a project-level decision.
- When changing a published data schema, archive format, or route scheme, update the relevant
  `docs/` spec so an Android implementation can follow it.
- Python tooling under `scripts/` is already platform-neutral and should remain the only writer of
  published data and signatures.

## Commands

Run `make` for the full list. Common ones:

| Command | Purpose |
|---|---|
| `make test-swift` | Run VerbKit tests (macOS/Xcode required) |
| `make test-py` | Run script tests |
| `make check` | CI checks except Swift tests |
| `make check-project` | Validate `project.yml` paths and version consistency |
| `make project` | Regenerate the Xcode project |
| `make data` / `make data-check` | Regenerate / verify published data |
| `make sign-commit` | Sign the manifest and commit only `manifest.sig` |

## Use these first — do not reinvent

### VerbKit utilities

| Symbol | Use |
|---|---|
| `Romaji.toHiragana(_:)` | Convert romaji queries to hiragana (Hepburn/Nihon-shiki) |
| `JapaneseNormalizer.key/looseKey/tagKey/kanaForm` | Canonical Japanese comparison (NFKC, katakana→hiragana, long vowels, tags) |
| `KanjiExtraction.kanji(in:)` | Distinct kanji for lookup chips |
| `Verb.displayTitle` / `Word.displayTitle` | `"dict (kanji)"` title for widgets, Spotlight, intents and pickers |
| `LevelSettings` + `Leveled` | Hidden-JLPT-level filtering, summaries and visibility checks |
| `SpeechText.spoken/clipName` | Clean text for TTS and the recorded-clip filename contract |
| `DataVersion.isOlder(_:than:)` | Reject replayed/older manifests |
| `Route`, `Route+URL`, `QuizLink` | Navigation and deep links (`verbtable://`) |
| `FavouriteVerbs` | Persisted favourite ids |
| `FolderTree` | Word Bank folder queries (descendants, paths, moves) |
| `WordBankArchive`, `WordBankImportPlanner`, `WordBankTransfer`, `WordBankEntryCombiner`, `WordBankSmartFolder`, `WordBankBackupStore` | Import/export/merge/backup logic |
| `TagSuggester`, `RecentSearches`, `DialectCatalogue` | Word Bank tag and search supporting logic |
| `WordBankDates.day/timestamp` | Fixed, locale-independent date stamps in Word Bank file names and notes |
| `matchesSearch`, `matchesGrammarSearch`, `searchCounters`, `WordBankSearchIndex` | Search implementations |
| `ParticleBlank`, `ParticleQuiz`, `buildParticleQuestions` | Marked `particle_blanks` on examples and the particle quiz built from them (spec: `docs/superpowers/specs/2026-10-29-particle-blanks-design.md`) |
| `DataSyncStatus` | Per-file sync status shown in Settings |
| `DataFileSync` (internal) | Shared persist → confirm → record-status flow for `WordsStore`, `FuriganaStore` and `CountersStore` |
| `SyncVerification` (internal) | The six sync services' rollback rejection, hash verification and JSON decoding |
| `UserDefaults.verbKitAppGroup` | The App Group defaults (falls back to `.standard`); App code aliases it as `.appGroup` |

### App UI components and modifiers

| Symbol | Use |
|---|---|
| `JapaneseText` | Any Japanese text that may need furigana. Use instead of `Text`; it styles like `Text` |
| `WrappingFlowLayout` | Wrapping row layout for chips, tags and pills |
| `FilterChip` / `chipBackground(_:)` | Filter-row capsule: menu or single-choice, outlined while on |
| `LevelBadge(level:emphasis:)` | JLPT pill beside a row title or in a detail header; nil draws nothing |
| `glassCard(cornerRadius:fillsWidth:)` | Liquid Glass card for detail sections |
| `RowChevron` | Disclosure chevron at the end of an opening row |
| `SectionHeader(_:systemImage:)` | Detail-page section heading |
| `TagPill` | Dialect/custom tag capsule |
| `QuizChoiceButton` | Shared answer button (colors, shapes, correct/wrong states) |
| `QuizHeader`, `QuizChoiceGrid` | Quiz progress/score header and two-column answer grid |
| `QuizPromptCard`, `QuizFeedbackCard`, `QuizMissedCard` | Question, feedback and missed-question card surfaces |
| `quizAdvanceBar`, `quizQuitDialog` | Pinned Next/See Results button and the quit confirmation |
| `QuizResultsSummary` | Counter and connection quiz results; the verb quiz keeps its own `QuizResultsView` |
| `LevelScopeBar`, `HiddenMatchesRow`, `NoMatchInLevelsView` | "My levels / All levels" search behavior |
| `accentPill(_:)` | Pastel Liquid Glass capsule for verb-type accents |
| `formCard()` | Quiet grouped-card surface for form tables |
| `textActions(_:translate:)` | Lookup, copy, translate menu for text |
| `formLookupSheet(_:)` | "What form is this?" presentation |
| `folderDeleteDialog(_:store:)` | Word Bank folder-deletion confirmation |
| `inlineSearch(...)` | Platform-correct search field placement |
| `speakOnTap(_:)`, `SpeakButton` | Pronunciation UI |
| `openRoute` environment action | Navigate to a `Route` from any view |

## Duplication: intentional vs. backlog

### Intentional — leave alone without a deliberate design decision

- **Per-file manifest types** (`VerbManifest`, `GrammarManifest`, `FuriganaManifest`,
  `WordsManifest`, `CountersManifest`) are separate on purpose: each file's sync state compares
  independently, so editing grammar does not re-download verbs. Do not merge them.
- **Six concrete sync services** (`Verb`, `Grammar`, `Furigana`, `Words`, `Counters`, `Forms`) each
  follow the same contract and stay concrete by decision (U12). Each file keeps its own manifest,
  result type and sync-state entry, so syncing one never disturbs another. The rules that must not
  drift — rollback rejection, hash verification, decoding — live once in `SyncVerification`. Do
  not replace the six with a generic `ManifestSyncService`; revisit only if a file stops fitting
  this shape.
- **`RubyFlowLayout`** is intentionally specialized (glued punctuation, max lines, baseline
  alignment). Do not fold it into a generic flow layout.

### Extraction backlog (done)

U1–U14 are complete. Use the shared symbols above instead of reintroducing a local flow
layout, filter chip, level pill, glass card, chevron, section header, quiz chrome, title
formatter, App Group defaults helper, date formatter or widget theme.

- U11: the quiz chrome lives in `App/UI/QuizChrome.swift`; the verb, counter and connection
  quizzes share it. `QuizResultsView` stays the verb quiz's richer results screen.
- U12: decided to keep the six concrete sync services; only `SyncVerification` is shared.
- U13: `DataFileSync` owns the persist → confirm → record-status order for `WordsStore`,
  `FuriganaStore` and `CountersStore`. `VerbStore` and `FormCatalogueStore` keep their own
  flows because their state and first-launch handling differ.
- U14: the flow layout lives in `App/UI/WrappingFlowLayout.swift` (moved with U1).

## Traps

- Adding a Swift file under `App/` is automatically part of the app target, but **not** the widget
  target. Widgets only see files named in `project.yml`.
- `project.yml` repeats `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` per target; change both
  together and run `make check-project`.
- Do not commit `.xcodeproj`, `DerivedData`, `.build`, signing keys or `__pycache__`.
- Data edits without a fresh signature fail CI even when the JSON is valid.
- `UserDefaults.appGroup` is an App-only alias of VerbKit's `UserDefaults.verbKitAppGroup`; use
  `userDefaults.verbKitAppGroup` (not a new `UserDefaults(suiteName:)`) inside VerbKit.
- VerbKit deliberately has no SwiftUI dependency. Shared SwiftUI components live in `App/UI/` and
  are visible to the app only; the widget target still gets just `Widgets/**` plus
  `App/VerbColors.swift`.
- The app and widgets rely on the App Group container at runtime; a signing/team misconfiguration
  makes the app fall back to an in-memory store. VerbKit tests use `VerbModelContainer.makeInMemory()`.
