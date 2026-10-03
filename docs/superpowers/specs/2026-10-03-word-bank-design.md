# Word Bank: a personal, tagged notebook for dialects and outside Japanese

## Problem

Everything in the app is curated: verbs and grammar arrive from the data sync.
There is nowhere to keep Japanese learned outside the app: dialect words from
friends (関西弁, 熊本弁, 高山弁…), phrases overheard, sentences a teacher wrote
down. The user wants a place to collect these, organise them by dialect and
region with tags, find them again with search, and review them.

## Decisions

- **Name:** "Word Bank", a third tab next to Verbs and Grammar.
- **Content is user-added only.** The app ships no entries.
- **Tags have no rules.** An entry may have any number of tags, or none.
  Dialect tags are the headline feature but not a requirement; the notebook
  also holds slang, phrases from friends, notes.
- **Two tag kinds:** structured dialect tags (dialect → prefecture → region)
  and free-form custom tags.
- **Storage:** local first, in a model that already follows CloudKit's rules,
  with JSON export as backup. iCloud sync is a later milestone.
- **Speech:** keep `SpeakButton`, with a note that it uses standard pitch, not
  the dialect's.
- **Review:** flashcards in both directions.
- **Meanings and links:** several senses per entry, structured standard
  Japanese equivalents (kanji + reading), kanji chips linking to Jisho,
  automatic links to app verbs, and a derived cross-dialect view.

## Design

### Entry

| Field | Required | Example | Notes |
|---|---|---|---|
| Text | yes | おおきに | What was heard / written, as the user writes it |
| Reading | no | おおきに | Kana; drives furigana and romaji search |
| Kanji spelling | no | 大きに | Etymology or written form when the text is kana-only |
| Kind | yes (default word) | word / phrase / sentence | Filterable |
| Senses | no, 0…n | "thank you" | English meaning + optional note per sense |
| Standard equivalents | no, 0…n | ありがとう; 可愛い (かわいい) | Written form, reading, note |
| Linked verb | no | 行く | Manual link for conjugated dialect forms (行かへん) |
| Tags | no, 0…n | 関西弁, #from-Yuki | Dialect and custom tags |
| Source / notes | no | "Yuki, izakaya in Osaka" | Free text |
| Created / updated | auto | | Sorting, "recently added" |

Senses exist because dialect words are often false friends: Kansai なおす means
"put away", standard なおす means "fix". A sense note such as
"≠ standard 直す (fix)" captures that.

### Tags

**Dialect tags** have a name (Japanese + romaji, e.g. 熊本弁 / Kumamoto-ben), a
prefecture (one of the 47) and a region (北海道, 東北, 関東, 中部, 関西, 中国,
四国, 九州・沖縄). Presets are seeded on first use: one tag per prefecture plus
well-known dialects (大阪弁, 京都弁, 博多弁, 名古屋弁, 津軽弁, 沖縄方言, …). The
user can add their own dialect tags (高山弁 / 飛騨弁 → 岐阜県 → 中部) and hide
presets they don't use. Presets are rows like any other, so they can be renamed.

**Custom tags** are a name and a colour.

### Tab and list

- `Tab("Word Bank", systemImage: "books.vertical")` in `MainTabView`, its own
  `NavigationSplitView` like the other tabs; `.sidebarAdaptable` makes it a
  sidebar item on iPad and macOS.
- Top bar follows the Verbs/Grammar pattern: **＋** (Add) and a **⋯ menu**
  (Review, Manage tags, Export, Settings, Report a problem).
- Grouping (menu chip): by region › dialect (entries without a dialect tag go
  in "Untagged"), by date added, or A–Z.
- Row: text with furigana, first standard equivalent, first sense, tag pills.
- Empty state explains the feature and offers "Add your first entry".

### Search

- The existing `inlineSearch` modifier, prompt "Search word bank…".
- Matches text, reading, kanji spelling, senses, standard equivalents (written
  and reading) and notes, with the existing `Romaji` matching, so "ookini",
  おおきに and "thank you" all find おおきに.
- Tags are **search tokens** (`searchable(text:tokens:)`): typing "kuma"
  suggests 熊本弁. Several tokens combine (AND), together with free text.
- A chip row under the search field, like the Verbs tab: dialect/region menu
  chip, kind chip, custom tag chip.
- Search logic lives in VerbKit (`WordBankSearch`), next to `VerbSearch` and
  `GrammarSearch`, so it is unit-tested.

### Detail page

- Large text with furigana from the reading, `SpeakButton` with a small
  "standard pronunciation" caption, existing text actions (Copy, Open in
  Jisho, Translate for sentences).
- **Comparison card:** 方言 おおきに → 標準語 ありがとう, one row per standard
  equivalent with furigana and its own text actions.
- **Meanings:** numbered senses with their notes.
- **Kanji chips:** one chip per distinct kanji in the text, kanji spelling and
  standard equivalents. Tapping opens Jisho's kanji page
  (`TextLookupURL.jishoKanji`, new). No built-in kanji dictionary.
- **Verb links:** a standard equivalent whose written form or reading matches a
  verb in the app (`dict` or `kanji`) shows "Open 行く" via `openRoute`. A
  manually linked verb shows the same way. A dialect verb form can also show
  the standard conjugation side by side (行かへん ↔ 行かない) when the user
  links the verb.
- **Same meaning in other dialects:** other entries sharing a standard
  equivalent, with their dialect tags ("ありがとう: おおきに 関西弁, だんだん
  出雲弁"). Derived at read time, never stored, so it needs no upkeep.
- Tags, source/notes, dates; Edit and Delete.

### Add / edit sheet

Text first, then reading, standard equivalents (＋ to add more), senses (＋),
kind, tags (token picker with "New dialect tag…" / "New tag…"), kanji
spelling, verb link (searchable picker over app verbs), source/notes. Only
text is required. When text is entered and an existing entry has the same
text, the sheet offers to open it instead of creating a duplicate.

### Flashcard review

- Started from the ⋯ menu or from a tag/filter ("Review these").
- Direction: dialect → meaning/standard, standard → dialect, or mixed.
- Self-graded ("Knew it" / "Didn't know"), since free-form answers can't be
  checked like conjugations. Reuses the quiz screen layout, not its grading.
- Results stored as their own attempt rows, separate from conjugation quiz
  history, so Weak spots and quiz progress are unaffected. Entries missed
  recently are shown first.

### Widget

"Word of the day" from the user's own entries, optionally limited to one tag
(widget intent parameter). Shows text, reading, first standard equivalent and
dialect tag; tapping deep-links to the entry (`verbtable://wordbank/<id>`, a
new `Route` case). Placeholder when the bank is empty. Uses the shared App
Group container like the existing widgets.

### Quick capture

An "Add to Word Bank" App Intent (Siri, Shortcuts, Spotlight) with text,
optional standard equivalent, meaning and dialect tag parameters. It writes
straight to the store. A share extension can build on it later.

## Data model

New SwiftData models in VerbKit, CloudKit-compatible from the start:

- `WordBankEntry`, `DialectTag`, `CustomTag`, `WordBankReviewAttempt`.
- No `@Attribute(.unique)`; every property optional or defaulted; all
  relationships optional with inverses (entry ↔ dialect tags, entry ↔ custom
  tags, entry ↔ review attempts). Identity by a `UUID` property.
- Senses and standard equivalents are `Codable` value arrays on the entry
  (`[Sense]`, `[StandardEquivalent]`); they are edited with the entry and
  never shared, so they don't need to be models.
- The linked verb is stored by verb `dict` string, not a relationship, so a
  data sync that rewrites `VerbEntity` rows can never break or delete it. A
  link to a verb that no longer exists is simply not shown.
- **Separate store:** the Word Bank models go in their own
  `ModelConfiguration` (`WordBank.sqlite` in the App Group container), inside
  the same `ModelContainer` as today. The synced verb/grammar data and the
  user's notebook never share a file, which keeps user data safe from data
  sync and lets iCloud sync later cover only this store.
- Store and persistence follow the existing pattern:
  `WordBankPersisting` protocol, `SwiftDataWordBankPersisting`,
  `@Observable WordBankStore` in the environment.
- Dialect presets come from a bundled list in VerbKit and are seeded once
  (tracked by a flag), so user edits are never overwritten.
- Export / import: JSON of entries and tags, via `fileExporter` /
  `fileImporter`. Import merges by `UUID`.

## Milestones

Each ships on its own:

1. **Core:** models, separate store, presets, store, tab, list, add/edit,
   detail (comparison card, senses, kanji chips, speech, text actions), tags
   and tag management, search with tokens and chips, JSON export/import.
2. **Links:** verb links (automatic and manual), same-meaning-in-other-dialects
   section, `wordbank` route.
3. **Flashcard review.**
4. **Widget.**
5. **Quick capture** App Intent.
6. *(later)* iCloud sync, share extension, map of Japan by prefecture.

## Components

- VerbKit: `WordBank/` (models, `Sense`, `StandardEquivalent`, dialect preset
  list, `WordBankSearch`, cross-dialect grouping, kanji extraction),
  `Persistence/` (entities, persisting), `Store/WordBankStore.swift`,
  `Lookup/TextLookupURL.swift` (`jishoKanji`), `Navigation/` (route case),
  `VerbModelContainer` (second configuration).
- App: `WordBankTab`, `WordBankListView`, `WordBankDetailView`,
  `WordBankEditor`, `TagPicker`, `TagManagerView`, `FlashcardReviewView`;
  `MainTabView` gains the tab.
- Widgets: `WordBankWidget` + intent.

## Platforms

iOS first; macOS must compile and work through the sidebar. iOS-only
modifiers stay behind `#if os(iOS)`.

## Testing

- Package tests for: search (kana, kanji, romaji, English, equivalents, tag
  token AND), cross-dialect grouping, kanji extraction, verb matching,
  preset seeding runs once and never overwrites edits, persistence round trip
  in memory, export/import round trip and merge, review ordering, Jisho kanji
  URL encoding, the new route parsing.
- Existing suite stays green; verb data sync must not touch Word Bank rows
  (test: sync after adding entries leaves them intact).
- Builds: iOS and macOS schemes. On-screen checks on the iPhone simulator for
  each milestone.

## Out of scope

Shipped dialect content, a built-in kanji dictionary, dialect-accurate audio,
recording the user's own audio, sharing entries between users, iCloud sync
(until milestone 6).
