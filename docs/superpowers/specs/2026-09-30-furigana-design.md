# Furigana — Design

**Date:** 2026-09-30
**Status:** Approved in brainstorming, pending written-spec review
**Builds on:** [2026-09-29-grammar-foundation-nd-desu-design.md](2026-09-29-grammar-foundation-nd-desu-design.md)
(sub-project 1, whose sync and persistence pattern this reuses),
[2026-09-30-potential-form-design.md](2026-09-30-potential-form-design.md)
(sub-project 2), and the [native rewrite spec](2026-09-23-native-apple-rewrite-design.md)
(section 10, the visual design direction).
This is **sub-project 5** of the grammar work.

## Summary

Show readings (furigana) above kanji wherever the app displays Japanese, behind a
Settings toggle that is **on by default**.

The work has four parts:

- **Data:** a new published file, `data/furigana.json`, holds a central reading
  dictionary. No existing string is edited.
- **Logic:** a pure, unit-tested `FuriganaDictionary` in `VerbKit` turns a string
  into drawable units.
- **Drawing:** a `JapaneseText` view draws those units with a small custom SwiftUI
  layout, because SwiftUI's `Text` cannot draw ruby.
- **Setting:** a **Show furigana** toggle in Settings.

## Findings that shaped the design

- **No native ruby in SwiftUI.** Neither the Foundation nor the SwiftUI interface in
  the iOS SDK (Xcode 27) mentions ruby. CoreText has `CTRubyAnnotation`, but it is only
  reachable through UIKit/AppKit views. The decision is a custom SwiftUI layout.
- **The scope is small.** Conjugation forms are all kana, verb examples are 169
  strings of which only 10 contain kanji, the lessons have 73 strings with kanji
  (mostly example sentences), and there are only **92 distinct kanji** in total. The
  quiz shows a kanji hint under each question, so it gets furigana too.
- **Published data is also read by older app builds.** Whatever is stored must not
  change how existing strings look to them.

## 1. Reading data and how it reaches the app

### `data/furigana.json`

A third published file, beside `verbs.json` and `grammar.json`:

```json
{ "version": "1.0.0", "description": "…",
  "readings": { "食": "た", "日本語": "にほんご", "来": "く", "来ら": "こ", "来た": "き", "今日": "きょう" } }
```

- A **key** is a run of kanji, optionally followed by a few kana that disambiguate
  it. The **value** is the hiragana reading of the **kanji run only**, so okurigana is
  never part of the ruby.
- **Matching.** The text is read left to right. At each kanji, the app takes the
  longest key that matches there, where the key's kanji part may be any prefix of the
  current kanji run and its kana part (at most three kana) must match the text that
  follows. The value is drawn above the matched kanji. So a run of several words such as
  遅れ is read as a whole (おく) rather than kanji by kanji, and a shorter key (遅, おそ)
  still applies when no longer one matches. One `食` entry covers 食べる, 食べた and
  食べられる. Only ambiguous kanji need longer keys (来 is く, こ or き depending on what
  follows: 来る = く, 来られる = こ via the key 来ら, 来た = き).
- **Unknown runs stay plain.** A kanji run with no entry is drawn without a reading,
  so nothing breaks while data is catching up.
- **Content.** The roughly 100 existing kanji runs, drafted and then reviewed by the
  maintainer, like lesson text.

### Guards (in `scripts/update_data.py`)

- **Coverage.** Fail if any kanji run in `verbs.json` or `grammar.json` has no
  reading, naming the run and where it occurs. A new lesson cannot ship without its
  readings.
- **Hygiene.** Values must be hiragana only, and every key must contain a kanji.
- **Cross-check.** Applying the dictionary to each verb's `kanji` field must give
  exactly that verb's kana `dict` form. This validates the 23 verb readings
  automatically.
- **Manifest.** The script hashes `furigana.json` into a third optional block,
  `furigana: {version, sha256}`, bumping its version like `grammar`'s. The top-level
  `version`/`sha256` keep meaning `verbs.json`.

### Sync and storage

- Older builds ignore the new manifest block. A new build with no dictionary yet (or
  offline on first launch) shows no furigana; a cached dictionary works offline.
- `VerbDataFetching` gains `fetchFuriganaManifest()` and `fetchFuriganaData()`;
  `SyncStateStoring` gains a per-file last-synced entry; `VerbModelContainer`'s schema
  gains a `FuriganaEntity` holding the dictionary as one JSON blob (like
  `GrammarEntity`).
- **`FuriganaSyncService`** mirrors `GrammarSyncService`, including its contract:
  `sync()` records nothing, and the caller persists and only then calls
  `confirmSynced(_:)`. It is a third concrete copy of the pattern, on purpose:
  `VerbSyncService` has a different manifest shape so a shared abstraction would not
  cover all three, and refactoring two working services is not worth it yet. Revisit
  at a fourth file.
- **`FuriganaStore`** (`@Observable`, new) owns the dictionary, its sync and its
  cache. `VerbStore` is untouched. The app entry starts it beside `VerbStore`; the two
  load independently and every failure is silent.

## 2. The view and the layout

The logic that decides *what to draw* is pure and lives in `VerbKit`; only drawing
lives in the app.

- **`FuriganaDictionary`** (VerbKit) exposes `units(for text: String) -> [TextUnit]`,
  each unit being plain text or a base with a reading.
  - A maximal kanji run becomes a ruby unit using the longest matching key.
  - An unknown kanji run stays plain.
  - English words, with their trailing space, are single units.
  - Kana is chunked a few characters at a time, so lines can break almost anywhere,
    as Japanese allows.
  - Closing punctuation (。、」）！？) attaches to the previous unit, so a line never
    starts with it.
  - Okurigana, the hiragana piece that directly follows a ruby unit (the べる of 食べる),
    attaches to that unit, so a line never breaks between a kanji and its ending.
- **`JapaneseText(_ text: String)`** (app) is the drop-in replacement for `Text`. It
  uses plain `Text` when furigana is off, the dictionary is not loaded, or the string
  has no kanji. Otherwise it flows the units with a custom `Layout`.
- **Styling is inherited.** Units are ordinary `Text`s, so `.font`, `.foregroundStyle`,
  `.bold()` and alignment set by callers come through the environment; call sites only
  change `Text(x)` to `JapaneseText(x)`.
- **Ruby size.** SwiftUI cannot report a font's point size, so each reading is
  rendered in the inherited font, scaled to half, and placed centred over its base.
  The layout reserves half a line's height above the text.
- **Baselines.** Both layouts report the text's first and last baseline, so a
  `JapaneseText` aligns with neighbouring `Text` in rows and stacks, and kanji sit on
  the same baseline as kana. A `lineLimit` is honoured by capping the number of lines
  and clipping.
- **Line height** is uniform within a string that has any ruby, so lines do not
  jitter. A unit is as wide as the wider of its base and its reading, so neighbours
  never collide.
- **Two risks to verify by running, not assume:** that scaled text stays crisp, and
  that the lesson page (about 40 example sentences on one eager scroll view, roughly a
  thousand small views) scrolls smoothly. If it does not, merge more kana per unit.
- Visual style follows the rewrite spec's section 10: no accessibility-specific
  modifiers, and `.glassEffect()` surfaces are unchanged.

## 3. The setting and what changes on screen

### The setting

A new `showFurigana` preference, **on by default**, stored in the same shared
settings as appearance and quiz length. Settings gets a "Reading" section with a
**Show furigana** toggle. `RootView` reads it once and passes it down through the
environment, so one toggle flips every screen live, with no relaunch.

### Screens that switch from `Text` to `JapaneseText`

Every data-driven string that can contain kanji:

- **Verb list and detail:** the kanji form in the row and the page header, and the
  verb's description and note (three verbs have kanji there).
- **Verb examples:** the Japanese sentence on the Examples sheet.
- **Quiz:** the kanji hint under each question.
- **Grammar list:** each lesson's title and summary.
- **Lesson page:** the header title and summary; the attachment cards (condition,
  pattern, example lines, note); every usage heading and explanation; the example
  rows; the conjugation forms and notes; the "Watch out" headings and explanations;
  and the related-lesson links.

**Already kana, so unchanged:** all conjugation tiles, the んです and Potential
sections, and the quiz's options and answers.

### Deliberately left plain

- **Navigation titles** (早見表, and the lesson name in the nav bar), because the
  system nav bar cannot host a custom view. The large title inside each lesson page
  does get furigana.
- **Hard-coded app chrome:** the verb-type guide (it uses Markdown bold and contains
  一段 and 五段) and the て-form legend. Giving these readings means teaching
  `JapaneseText` Markdown, which is a follow-up.

## 4. Testing, rollout and risks

### Testing

- **Segmentation (Swift unit tests)** for `FuriganaDictionary.units(for:)`: longest
  match; 来 choosing く / こ / き from the kana after it; compounds such as 日本語; an
  unknown kanji run staying plain; English words keeping their spaces; closing
  punctuation attaching backwards; chunking; the empty string; and mixed strings such
  as *"Written 来られる and read こられる."*
- **Real data (Swift):** every kanji run in `verbs.json` and `grammar.json` resolves;
  applying the dictionary to each verb's `kanji` gives exactly its `dict` form; all
  values are hiragana; the manifest's third hash matches the file.
- **Script (Python):** the coverage check exits 1 and names the missing run and where
  it occurs; hiragana-only values; keys must contain a kanji; the verb cross-check
  fails with a clear message; the manifest's third block and versions.
- **Sync, cache and store:** `FuriganaSyncService` mirrors the grammar sync tests
  (including confirm-after-persist), plus a persistence round-trip. `FuriganaStore`
  covers cached load, silent failure, and "no dictionary means plain text".
- **Drawing (Simulator):** toggle on and off; the lesson page, Examples sheet and verb
  header; a long sentence wrapping; light and dark; iPad. Crispness and scroll
  performance are checked explicitly.

### Rollout

`verbs.json` and `grammar.json` do not change, so their versions stay put. Only
`furigana.json` and the manifest's new block are added. A new build run before the
data is published shows no furigana until the data arrives, then it just works.

### Risks

| Risk | Covered by |
|---|---|
| A wrong reading | Maintainer review of the drafted dictionary, plus the verb cross-check |
| A new lesson ships without readings | The coverage check in the script |
| A sluggish lesson page | The Simulator performance check, with merged kana chunks as the fallback |
| Scaled text looks soft | The Simulator crispness check |

## Files this touches

- **New:** `data/furigana.json`; in VerbKit, the dictionary and unit types, the
  manifest entry, the sync service, persistence (`FuriganaPersisting`,
  `FuriganaEntity`, a SwiftData implementation) and `FuriganaStore`; in the app,
  `JapaneseText`, the flow layout and the environment key; tests.
- **Edited, patch-style on top of the latest `main`** (never replaced wholesale): the
  fetcher and sync-state protocols and their test mocks; `GitHubVerbFetcher`;
  `VerbModelContainer`; `scripts/update_data.py` and its tests; `SettingsView`;
  `RootView`; `JPVerbConjugationApp`; the call sites listed in section 3;
  `data/manifest.json` (by the script).

## Not in this sub-project

- Markdown inside `JapaneseText` (so the verb-type guide stays plain).
- Navigation-bar titles.
- Romaji.
- Tap-to-hide on a single word, or a per-screen override of the setting.
- Sub-projects 3 and 4 (nuance endings, verb auxiliaries); their lessons will get
  furigana for free once their kanji are in the dictionary, and the coverage check
  will insist on it.
