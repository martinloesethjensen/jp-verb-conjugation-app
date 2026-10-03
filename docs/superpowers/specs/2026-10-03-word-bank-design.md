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
四国, 九州・沖縄). The user's tag list starts empty: a tag exists only once
the user creates it, so the list holds only dialects they actually study.

**Custom tags** are a name and a colour.

### Tag suggestions

Creating a tag starts from a single field, "New tag…", in the tag picker
and in Manage tags. As the user types, suggestions appear in sections:

1. **Already yours.** Existing tags that match, shown first with "Use", so
   typing "kansai" when 関西弁 exists reuses it instead of making a
   duplicate. An exact match (after normalisation, below) blocks creating a
   second tag with the same name.
2. **Dialects.** Matches from a bundled **dialect catalogue**. Picking one
   creates a dialect tag with name, romaji, prefecture and region already
   filled in. Typing "takayama" suggests 高山弁 / 飛騨弁 (岐阜県, 中部);
   "kuma" suggests 熊本弁; "gifu" lists every dialect of 岐阜県 (飛騨弁, 美濃弁)
   plus a plain 岐阜県 prefecture tag.
3. **Custom tag ideas.** Matches from a short bundled list of common
   categories (greetings, food, slang, casual, polite, from a friend,
   overheard, …), offered with a colour already chosen.
4. **Create "…".** Always last: creates exactly what was typed as a custom
   tag, or as a dialect tag through a "Dialect…" option where the user picks
   prefecture and region (pre-selected when the typed text names one).

With an empty field the picker shows **Recently used** tags, then dialect
suggestions **based on the user's existing tags**: other dialects of the
same prefecture and region first (having 大阪弁 suggests 京都弁, 神戸弁,
河内弁), so related dialects are one tap away.

**Matching** happens in VerbKit (`TagSuggester`), not in the view, and is
unit-tested. Before comparing, both the query and candidates are normalised:
hiragana ↔ katakana, romaji through the existing `Romaji` conversion,
macrons and long vowels folded (Ōsaka = Oosaka = Osaka), case and spaces
ignored, and the dialect suffixes 弁 / べん / -ben / ben / 方言 / 言葉 removed. So
"osaka", "おおさか", "Osaka-ben" and "大阪弁" all find 大阪弁. A
match at the start of a word ranks above a match inside it; tags already on
the entry are not suggested again.

**Dialect catalogue:** a bundled JSON file in VerbKit (`dialects.json`), not
synced data, with one record per dialect: id, kanji name, kana reading,
romaji, aliases (飛騨弁 ↔ 高山弁, 関西弁 for the Kansai family), prefecture(s),
region. It covers all 47 prefectures (each also available as a plain
prefecture tag) and the well-known dialects within them. A dialect spanning
several prefectures (関西弁, 東北弁) lists them all and has a region but no
single prefecture. A tag created from the catalogue keeps its catalogue id,
so suggestions can tell it's already used and later catalogue updates can
fill in missing romaji without touching the name the user sees. The user
can rename any tag freely.

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
- Nothing is seeded: the dialect catalogue is read-only bundled data used
  for suggestions, and tags are rows only once the user creates them.
  `DialectTag` stores an optional `catalogueID`.
- Export / import: JSON of entries and tags, via `fileExporter` /
  `fileImporter`. Import merges by `UUID`.

## Milestones

Each ships on its own:

1. **Core:** models, separate store, dialect catalogue, store, tab, list, add/edit,
   detail (comparison card, senses, kanji chips, speech, text actions), tags
   and tag management with suggestions, search with tokens and chips, JSON export/import.
2. **Links:** verb links (automatic and manual), same-meaning-in-other-dialects
   section, `wordbank` route.
3. **Flashcard review.**
4. **Widget.**
5. **Quick capture** App Intent.
6. *(later)* iCloud sync, share extension, map of Japan by prefecture.

## Components

- VerbKit: `WordBank/` (models, `Sense`, `StandardEquivalent`, dialect
  catalogue + `dialects.json`, `TagSuggester`, `WordBankSearch`, cross-dialect grouping, kanji extraction),
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
  tag suggestions (normalisation of kana/romaji/macrons/弁 suffixes,
  aliases, ranking, own-tag-first and duplicate blocking, related dialects
  from existing tags, already-applied tags excluded), catalogue file decodes
  and covers all 47 prefectures, persistence round trip
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
