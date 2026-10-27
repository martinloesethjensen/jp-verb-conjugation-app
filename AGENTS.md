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
| `LevelSettings` + `Leveled` | Hidden-JLPT-level filtering, summaries and visibility checks |
| `SpeechText.spoken/clipName` | Clean text for TTS and the recorded-clip filename contract |
| `DataVersion.isOlder(_:than:)` | Reject replayed/older manifests |
| `Route`, `Route+URL`, `QuizLink` | Navigation and deep links (`verbtable://`) |
| `FavouriteVerbs` | Persisted favourite ids |
| `FolderTree` | Word Bank folder queries (descendants, paths, moves) |
| `WordBankArchive`, `WordBankImportPlanner`, `WordBankTransfer`, `WordBankEntryCombiner`, `WordBankSmartFolder`, `WordBankBackupStore` | Import/export/merge/backup logic |
| `TagSuggester`, `RecentSearches`, `DialectCatalogue` | Word Bank tag and search supporting logic |
| `matchesSearch`, `matchesGrammarSearch`, `searchCounters`, `WordBankSearchIndex` | Search implementations |
| `DataSyncStatus` | Per-file sync status shown in Settings |

### App UI components and modifiers

| Symbol | Use |
|---|---|
| `JapaneseText` | Any Japanese text that may need furigana. Use instead of `Text`; it styles like `Text` |
| `TagPill` | Dialect/custom tag capsule |
| `QuizChoiceButton` | Shared answer button (colors, shapes, correct/wrong states) |
| `QuizResultsView` | Verb-quiz results screen (counter/connection quizzes currently have their own) |
| `LevelScopeBar`, `HiddenMatchesRow`, `NoMatchInLevelsView` | "My levels / All levels" search behavior |
| `accentPill(_:)` | Pastel Liquid Glass capsule for verb-type accents |
| `formCard()` | Quiet grouped-card surface for form tables |
| `textActions(_:translate:)` | Lookup, copy, translate menu for text |
| `formLookupSheet(_:)` | "What form is this?" presentation |
| `folderDeleteDialog(_:store:)` | Word Bank folder-deletion confirmation |
| `inlineSearch(...)` | Platform-correct search field placement |
| `speakOnTap(_:)`, `SpeakButton` | Pronunciation UI |
| `openRoute` environment action | Navigate to a `Route` from any view |
| `chipBackground(_:)` | Shared filter-chip capsule background |

## Duplication: intentional vs. backlog

### Intentional — leave alone without a deliberate design decision

- **Per-file manifest types** (`VerbManifest`, `GrammarManifest`, `FuriganaManifest`,
  `WordsManifest`, `CountersManifest`) are separate on purpose: each file's sync state compares
  independently, so editing grammar does not re-download verbs. Do not merge them.
- **Six concrete sync services** (`Verb`, `Grammar`, `Furigana`, `Words`, `Counters`, `Forms`) each
  follow the same contract. The comments say this duplication is deliberate. **However**,
  `FuriganaSyncService` says "Revisit at a fourth file" and there are now six. Treat a generic
  sync service as a pending design decision, not a mechanical cleanup.
- **`RubyFlowLayout`** is intentionally specialized (glued punctuation, max lines, baseline
  alignment). Do not fold it into a generic flow layout.

### Extraction backlog (documented, not yet implemented)

| ID | Duplication | Locations | Proposed extraction |
|---|---|---|---|
| U1 | Two wrapping `Layout` implementations | `ChipFlowLayout` in `App/Counters/ThingChips.swift`; `PillFlow` in `App/WordBank/TagPill.swift` | One shared `WrappingFlowLayout` in `App/UI/`, keeping `PillFlow`'s rounding slack |
| U2 | Filter-chip style repeated | `TypeFilterChip.swift`, `TeFormFilter.swift`, `WordBankSearchSupport.swift` | `FilterChip` view or `.filterChipStyle(isOn:accent:)` |
| U3 | JLPT level pill | `VerbRow`, `GrammarListView`, `GrammarDetailView`, `CounterListView`, `CounterDetailView`, `GroupTableView` | `LevelBadge` with emphasis variants |
| U4 | Glass card chain | `GrammarDetailView`, `CounterDetailView`, `AttachmentSection`, `VerbDetailView`, `WordBankDetailView` | `.glassCard(cornerRadius:)`; keep `formCard()` distinct |
| U5 | Row chevron | `DirectoryRow`, `MoreRowsCard`, `WordBankListView`, `TagManagerView`, `WordBankEditor`, `WordBankImportSheet` | `RowChevron` view |
| U6 | Section header | `GrammarDetailView`, `WordBankDetailView` | `SectionHeader(title:systemImage:)` |
| U7 | `"dict (kanji)"` title formatting | `VerbIntents`, `SpotlightIndexer`, `VerbWidgetIntent`, `BuildingBlocksView` | `Verb.displayTitle` / `Word.displayTitle` in VerbKit |
| U8 | App Group defaults setup | `App/UserDefaults+AppGroup.swift`, `VerbModelContainer`, `LevelSettings`, `QuizSessionStore` | One public app-group `UserDefaults` helper in VerbKit |
| U9 | Word Bank `DateFormatter` setup | `WordBankExport`, `WordBankEntryCombiner`, `WordBankBackupStore` | Static `WordBankDates` helper |
| U10 | Widget theme | `VerbWidgetViews`, `CounterWidgetViews`, `GrammarWidgetViews` | `Widgets/WidgetTheme.swift` (navy, gradient, empty state, JLPT palette) |
| U11 | Quiz screen shell | `QuizQuestionView`, `CounterQuizView`, `ConnectionQuizView` | Shared shell for header, choice grid, pinned Next, feedback, quit dialog and results |
| U12 | Sync-service flow | six `*SyncService` types | Generic `ManifestSyncService` **only after** a design decision |
| U13 | Store sync orchestration | `WordsStore`, `FuriganaStore`, `CountersStore` | Shared persist/confirm/record-status coordinator |
| U14 | `ChipFlowLayout` placement | defined in `ThingChips.swift`, used by `SoundPatternsView` too | Move with U1 |

## Traps

- Adding a Swift file under `App/` is automatically part of the app target, but **not** the widget
  target. Widgets only see files named in `project.yml`.
- `project.yml` repeats `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` per target; change both
  together and run `make check-project`.
- Do not commit `.xcodeproj`, `DerivedData`, `.build`, signing keys or `__pycache__`.
- Data edits without a fresh signature fail CI even when the JSON is valid.
- `UserDefaults.appGroup` is currently an App-only extension; VerbKit code uses
  `UserDefaults(suiteName: VerbModelContainer.appGroupIdentifier) ?? .standard` directly.
- The app and widgets rely on the App Group container at runtime; a signing/team misconfiguration
  makes the app fall back to an in-memory store. VerbKit tests use `VerbModelContainer.makeInMemory()`.
