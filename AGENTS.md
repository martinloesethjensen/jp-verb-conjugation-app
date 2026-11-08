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
| `schema/` | A JSON Schema per `data/` file, checked by `update_data.py`; the contract other clients read |
| `review/` | The teacher/native-speaker review site: `api` (Rust Cloudflare Worker), `web` (Svelte). See `review/README.md` |
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
   `App/VerbColors.swift`, `App/Theme/ThemePalette.swift` and `App/Theme/ThemePalettes.swift`
   (listed in `project.yml`). If a widget needs another App file, add it to
   the widget target's `sources` and run `make check-project`.
5. **Stores are injected, not global.** `JPVerbConjugationApp` creates the `@MainActor @Observable`
   stores and injects them with `.environment(...)`. Views read them with
   `@Environment(StoreType.self)`. Previews/tests construct their own.
6. **Persist before confirming.** Every sync service returns a result but records nothing.
   The store must durably save the payload *first*, then call `confirmSynced(_:)`, so a failed save
   is retried on the next launch. Do not simplify this ordering.
7. **Wording is a UI concern.** User-facing strings belong in `App/` (see `GrammarDisplay.swift`).
   `DataSyncStatus` in VerbKit is a known existing exception, not a pattern to copy.
8. **Data is signed once per batch.** Changes under `data/` must be regenerated with `make data`
   and committed with everything it writes, but feature PRs are **not** signed and never touch
   `data/manifest.sig`. If a data PR conflicts with main, run `make data-merge`, which resolves the
   generated files and stops only on real conflicts in hand-authored files. The owner publishes merged
   changes with `make data-release`; never run it, `make sign-commit` or `make review-pull` yourself. CI rejects stale
   or invalid data on PRs, and checks the signature on `main` (red there means "not released yet").

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
| `make data-merge` | Merge `origin/main` into a data branch, regenerating the generated files |
| `make data-release` | Owner only: sign everything merged since the last release on a `data-release/<date>` PR |
| `make sign-commit` | Sign the manifest and commit only `manifest.sig` (used by `make data-release`) |
| `make review-pull` | Owner only: pull accepted review-site work into a `review-pull/<date>` data branch (needs the export token in the Keychain) |
| `make review-test` / `make review-build` | Test / build the review site |

## Use these first — do not reinvent

### VerbKit utilities

| Symbol | Use |
|---|---|
| `Romaji.toHiragana(_:)` | Convert romaji queries to hiragana (Hepburn/Nihon-shiki) |
| `JapaneseNormalizer.key/looseKey/tagKey/kanaForm` | Canonical Japanese comparison (NFKC, katakana→hiragana, long vowels, tags) |
| `KanjiExtraction.kanji(in:)` | Distinct kanji for lookup chips |
| `SVGPathData.parse(_:)`, `SVGPoint` | SVG `d` strings to path elements (arcs as cubics), Foundation-only |
| `StampShape`, `StampStroke` | The twelve results/icon stamps as path data in the seal's 120-unit box |
| `FormHighlight.range(of:for:in:)` | Where a kana form sits in an example sentence, spelled with the verb's kanji or in kana |
| `TextUnit.emphasizing(_:characters:)` | Marks a character range of furigana units emphasised, splitting plain units and keeping ruby whole |
| `Verb.units(for:)` / `Verb.dictionaryUnits` | A kana form (or the dictionary form) as ruby units spelled with the verb's kanji stem |
| `PotentialPattern(verb:)` | How the potential form is built (ru, u, する, くる); nil without one |
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
| `GlobalSearch.results`, `SearchScope`, `GlobalSearchResults` | The Search tab's one search over all four, with the level setting, hidden-match count and the romaji reading line |
| `ParticleBlank`, `ParticleQuiz`, `buildParticleQuestions` | Marked `particle_blanks` on examples and the particle quiz built from them (spec: `docs/superpowers/specs/2026-10-29-particle-blanks-design.md`) |
| `DataSyncStatus` | Per-file sync status shown in Settings |
| `DataFileSync` (internal) | Shared persist → confirm → record-status flow for `WordsStore`, `FuriganaStore` and `CountersStore` |
| `SyncVerification` (internal) | The six sync services' rollback rejection, hash verification and JSON decoding |
| `UserDefaults.verbKitAppGroup` | The App Group defaults (falls back to `.standard`); App code aliases it as `.appGroup` |
| `ThemeID`, `ThemeGroup`, `ThemeChoice`, `AppearanceSetting` | The ten themes (each with a light and dark half), picker groups, seasonal override, the Appearance setting and the one-time migrations from `appearanceMode` and plan 1's keys (spec: `docs/superpowers/specs/2026-11-06-paper-ink-redesign-design.md`) |

### App UI components and modifiers

| Symbol | Use |
|---|---|
| `JapaneseText` | Any Japanese text that may need furigana. Use instead of `Text`; it styles like `Text` |
| `JapaneseText(_:emphasizing:)` | The same with a character range underlined (and bold where the font has a bold face), furigana on or off |
| `VerbExampleRow`, `VerbExampleCard` | A verb's example sentence with its form tag and the form underlined; the card puts rows on ruled paper |
| `ThemeStamp`, `SealView` | A theme half's results stamp and the 122 pt 活 seal, drawn like the launch image and icon (first frame now, alternate icons later) |
| `LaunchHandoff` | iOS first frame: copies the launch screen, fades in the theme's paper and stamp, then fades to content (skipped with Reduce Motion) |
| `VerbSubPageHeader`, `verbSubPage(title:)` | A verb sub-page's header (verb, title, optional headline form) and its paper/title chrome |
| `WrappingFlowLayout` | Wrapping row layout for chips, tags and pills |
| `FilterChip` / `chipBackground(isOn:)` | Filter-row capsule: outlined in ink while off, filled with `button` while on; an accent adds a dot |
| `LevelBadge(level:emphasis:)` | Outlined JLPT pill beside a row title or in a detail header; nil draws nothing |
| `\.palette` / `ThemePalette` | The current theme's colours (paper, card, ink, muted, rule, mark, good, button, accent). Read these, not `.secondary`/`.white`, in restyled views |
| `paperCard(cornerRadius:fillsWidth:ruled:)` | Card for detail sections: `card` fill, `rule` outline. Glass stays on bars and toolbars. `ruled: true` adds the genkō grid, for example sentences and results |
| `PaperButtonStyle` (`.paper` / `.paperSecondary`) | Ink-filled or outlined full-width capsule for content buttons, instead of glass |
| `paperBackground()`, `paperRow()` | Paper behind a screen's List/ScrollView/Form; card-coloured list rows |
| `TypeLabel(_:teGroup:emphasis:title:)` | A verb type as a dot + ink label (shapes with Differentiate Without Color; filled pill in Pastel/Ice cream) |
| `Font.headword(_:scale:)` / `Font.sentence(_:)` | Hiragino Mincho W6 for Japanese headwords, W3 for example sentences and phrases; both scale with Dynamic Type |
| `themedRoot()`, `ThemePickerView` | Root palette/appearance wiring (once, in `RootView`) and Settings › Theme |
| `RowChevron` | Disclosure chevron at the end of an opening row |
| `SectionHeader(_:systemImage:trailing:)` | Detail-page section heading, with an optional trailing hint or button |
| `TagPill` | Dialect/custom tag capsule |
| `QuizChoiceButton` | Shared answer button (colors, shapes, correct/wrong states) |
| `QuizHeader`, `QuizChoiceGrid` | Quiz progress/score header and two-column answer grid |
| `QuizPromptCard`, `QuizFeedbackCard`, `QuizMissedCard` | Question, feedback and missed-question card surfaces |
| `quizAdvanceBar`, `quizQuitDialog` | Pinned Next/See Results button and the quit confirmation |
| `QuizScoreCard`, `quizResultsActions(practise:onPractise:onDone:)` | The results score in a red hand-drawn ring on ruled paper, and the pinned Practise/Done buttons |
| `QuizResultsSummary` | Counter and connection quiz results, built on `QuizScoreCard`; the verb quiz keeps its own `QuizResultsView` |
| `LevelScopeBar`, `HiddenMatchesRow`, `NoMatchInLevelsView` | "My levels / All levels" search behavior |
| `accentPill(_:)` | Pastel Liquid Glass capsule; used by `TypeLabel` for filled pills — prefer `TypeLabel` |
| `formCard()` | Quiet grouped-card surface for form tables |
| `textActions(_:translate:)` | Lookup, copy, translate menu for text |
| `formLookupSheet(_:)` | "What form is this?" presentation |
| `folderDeleteDialog(_:store:)` | Word Bank folder-deletion confirmation |
| `inlineSearch(...)` | Platform-correct search field placement |
| `speakOnTap(_:)`, `SpeakButton` | Pronunciation UI |
| `openRoute` environment action | Navigate to a `Route` from any view |
| `dismissOnLink(_:)` | Close a read-only sheet or popover when a `verbtable://` link opens a page (not for editors or quizzes) |

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
layout, filter chip, level pill, paper card, chevron, section header, quiz chrome, title
formatter, App Group defaults helper, date formatter or widget theme.

- U11: the quiz chrome lives in `App/UI/QuizChrome.swift`; the verb, counter and connection
  quizzes share it. `QuizResultsView` stays the verb quiz's richer results screen.
- U12: decided to keep the six concrete sync services; only `SyncVerification` is shared.
- U13: `DataFileSync` owns the persist → confirm → record-status order for `WordsStore`,
  `FuriganaStore` and `CountersStore`. `VerbStore` and `FormCatalogueStore` keep their own
  flows because their state and first-launch handling differ.
- U14: the flow layout lives in `App/UI/WrappingFlowLayout.swift` (moved with U1).

## Traps

- The launch screen, the iOS app icon and `App/Launch/SealGlyph.swift` are generated by
  `swift scripts/generate-icon.swift --font <ShipporiMinchoB1-Bold.ttf>`. Don't hand-edit them; the font
  (SIL OFL) is a generation-time input and is never committed. iOS caches launch screens: uninstall the app to see a new one.

- Adding a Swift file under `App/` is automatically part of the app target, but **not** the widget
  target. Widgets only see files named in `project.yml`.
- `project.yml` repeats `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` per target; change both
  together and run `make check-project`.
- Do not commit `.xcodeproj`, `DerivedData`, `.build`, signing keys or `__pycache__`.
- Data edits that were not regenerated with `make data` fail CI even when the JSON is valid. A merged
  data change leaves the `data` check on `main` red until the owner runs `make data-release`.
- `UserDefaults.appGroup` is an App-only alias of VerbKit's `UserDefaults.verbKitAppGroup`; use
  `userDefaults.verbKitAppGroup` (not a new `UserDefaults(suiteName:)`) inside VerbKit.
- VerbKit deliberately has no SwiftUI dependency. Shared SwiftUI components live in `App/UI/` and
  are visible to the app only; the widget target still gets just `Widgets/**` plus
  `App/VerbColors.swift` and the two palette files.
- A colour a widget needs must live in `App/Theme/ThemePalette*.swift` (or `VerbColors.swift`);
  widgets get the palette through `widgetThemed(date:)`, not `themedRoot()`.
- The app and widgets rely on the App Group container at runtime; a signing/team misconfiguration
  makes the app fall back to an in-memory store. VerbKit tests use `VerbModelContainer.makeInMemory()`.
