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
- **Folders:** nested, and each entry lives in at most one folder (or
  "Unfiled"). Folders say where an entry is filed; tags say what it is.
- **Storage:** local first, in a model that already follows CloudKit's rules.
  iCloud sync is a later milestone.
- **Import / export:** JSON only. Import creates missing folders and tags and
  merges with what is already there using a "combine both, lose nothing" rule.
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
| Folder | no, 0…1 | Trip 2026 › Takayama | Unfiled when empty |
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
- Top bar follows the Verbs/Grammar pattern: **＋** (Add entry / New folder)
  and a **⋯ menu** (Review, Manage tags, Import, Export, Settings, Report a
  problem).
- The root screen starts with **All entries**, **Unfiled** and **Recently
  added**, then the top-level folders, then (at the root only) unfiled
  entries. Opening a folder shows its subfolders first, then its entries, with
  the folder path as the navigation subtitle.
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
- Inside a folder, search scopes (`searchScopes`) choose **This folder**
  (including subfolders, the default) or **All entries**. Results outside the
  current folder show their folder path.
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

### Folders

- **Create:** "New folder" in the ＋ menu creates it inside the folder being
  viewed. Names must be unique among siblings (compared case- and
  width-insensitively), so a folder path always names exactly one folder,
  which import relies on.
- **File an entry:** a Folder row in the add/edit sheet; adding from inside
  a folder pre-selects that folder.
- **Move:** "Move to…" on entries (also multi-select in edit mode) and on
  folders opens a folder picker; drag and drop on iPad and macOS. A folder
  can't be moved into itself or its own subfolders.
- **Rename** and **delete.** Deleting a folder asks: **Keep entries** (the
  default; entries and subfolders move up to the parent) or **Delete
  everything** (with the entry count shown).
- **Use elsewhere:** "Review this folder" and "Export this folder" act on the
  folder and its subfolders; the widget can be limited to a folder as well as
  a tag.
- No depth limit; the UI never needs one, since each level is its own screen.

### Import and export

**File format.** A JSON file with the extension `.wordbank` (a custom
`UTType` conforming to `public.json`, so the app opens it from Files, AirDrop
and Mail too). It has a header (`format: "word-bank"`, `version: 1`,
`exportedAt`), then `folders` (id, name, parent id), `dialectTags`,
`customTags` and `entries` (all fields, folder id, tag ids). Each entry also
carries its **folder path** (`["Trip 2026", "Takayama"]`) and tag
**names**, so a hand-written or generated file with no ids and no `folders`
list still imports: paths create folders, names match or create tags. Only
`text` is required per entry; unknown fields are ignored.

**Export.** Everything (full backup), one folder with its subfolders (that
folder becomes the file's root), the current selection, or the current
search results. A full backup can include review history; other exports
never do. Shared through the share sheet or saved with `fileExporter`.

**Import flow.**

1. Pick a file (`fileImporter`) or open a `.wordbank` file from outside the
   app.
2. Choose the destination: **Word Bank root** (folder paths kept as they
   are) or **Into a folder…** (the file's folders are created inside it).
3. A **preview** shows what will happen before anything is saved: new
   entries, entries combined with existing ones, unchanged entries, new
   folders (as paths), new tags, and skipped records with reasons.
4. **Import** applies everything in one save; if the save fails, nothing
   changes.
5. Before applying, the app writes an automatic backup of the current bank
   (the last three are kept; **Settings › Word Bank › Restore backup**), so
   any import can be undone.

**Matching.** Order matters: folders, then tags, then entries.

- *Folders:* by id; otherwise by path from the destination, segment by
  segment, using the sibling-name comparison above. Anything unmatched is
  created, parents first. A matched folder keeps its local name.
- *Dialect tags:* by id, then catalogue id, then normalised name (the
  `TagSuggester` normalisation). *Custom tags:* by id, then normalised name.
  Unmatched tags are created.
- *Entries:* by id; otherwise by normalised text plus reading. When the file
  has no reading, text alone matches only if exactly one local entry has that
  text; if several do, the imported entry is added as new rather than
  guessed.

**Combining a matched entry** (nothing is ever deleted or overwritten):

- Text, kind and anything else already filled in locally stay as they are.
- Empty local fields (reading, kanji spelling, linked verb, source) are
  filled from the file.
- Senses, standard equivalents and tags are **unioned**; duplicates are found
  with the same normalisation as search.
- Notes: if the file's note differs and isn't already contained in the local
  one, it is appended under "Imported <date>".
- Folder: an entry already filed stays where it is; an unfiled one moves to
  the imported folder.
- Created date becomes the earlier of the two; updated date is set only if
  something actually changed.

Importing the same file twice therefore changes nothing the second time; the
preview reports everything as unchanged.

**Validation.** A file with a newer major `version` is refused with a
message asking to update the app. Records without text, references to
missing folders or tags (which fall back to the path or name), and
malformed values are skipped or repaired and listed in the preview. Files
over 20 MB are refused.

All of this logic (`WordBankArchive` for the format, `WordBankImportPlanner`
producing the preview plan, applied by the store) lives in VerbKit and is
unit-tested without UI.

### Add / edit sheet

Text first, then reading, standard equivalents (＋ to add more), senses (＋),
kind, folder, tags (token picker with "New dialect tag…" / "New tag…"), kanji
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

- `WordBankEntry`, `WordBankFolder`, `DialectTag`, `CustomTag`,
  `WordBankReviewAttempt`.
- No `@Attribute(.unique)`; every property optional or defaulted; all
  relationships optional with inverses (entry ↔ dialect tags, entry ↔ custom
  tags, entry ↔ review attempts, entry → folder ↔ folder entries, folder →
  parent ↔ folder children). Identity by a `UUID` property. Sibling-name
  uniqueness is enforced by the store, since CloudKit can't.
- Deleting a folder never cascades at the model level; the store moves or
  deletes contents explicitly, according to the user's choice.
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
- Automatic pre-import backups are `.wordbank` files in the app's
  Application Support folder, not in the database.

## Milestones

Each ships on its own:

1. **Core:** models, separate store, dialect catalogue, store, tab, list,
   folders, add/edit, detail (comparison card, senses, kanji chips, speech,
   text actions), tags and tag management with suggestions, search with
   tokens, chips and folder scopes.
2. **Import / export:** `.wordbank` format, export scopes, import preview,
   folder and tag generation, combine merge, automatic backups and restore.
3. **Links:** verb links (automatic and manual), same-meaning-in-other-dialects
   section, `wordbank` route.
4. **Flashcard review.**
5. **Widget.**
6. **Quick capture** App Intent.
7. *(later)* iCloud sync, CSV and Anki formats, share extension, map of Japan
   by prefecture.

## Components

- VerbKit: `WordBank/` (models, `Sense`, `StandardEquivalent`, dialect
  catalogue + `dialects.json`, `TagSuggester`, `WordBankSearch`, folder tree operations, `WordBankArchive`,
  `WordBankImportPlanner`, cross-dialect grouping, kanji extraction),
  `Persistence/` (entities, persisting), `Store/WordBankStore.swift`,
  `Lookup/TextLookupURL.swift` (`jishoKanji`), `Navigation/` (route case),
  `VerbModelContainer` (second configuration).
- App: `WordBankTab`, `WordBankListView`, `WordBankFolderView`,
  `FolderPicker`, `WordBankDetailView`, `WordBankEditor`, `TagPicker`,
  `TagManagerView`, `ImportPreviewSheet`, `FlashcardReviewView`;
  `MainTabView` gains the tab; `project.yml` declares the `.wordbank`
  document type and exported `UTType`.
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
  in memory, review ordering, Jisho kanji URL encoding, the new route
  parsing.
- Folders: sibling-name uniqueness, move with cycle prevention, delete with
  keep vs delete contents, scoped search including subfolders.
- Import / export: lossless round trip; folder-scoped export re-roots paths;
  hand-written file with only paths and names creates folders and tags;
  import into a chosen folder nests paths; matching order and every rule
  above (id, catalogue id, normalised name, text + reading, ambiguous text
  added as new); combine rule field by field; re-importing the same file is
  a no-op; newer version refused; invalid records reported; failed save
  leaves the bank unchanged; backup written before apply and restorable.
- Existing suite stays green; verb data sync must not touch Word Bank rows
  (test: sync after adding entries leaves them intact).
- Builds: iOS and macOS schemes. On-screen checks on the iPhone simulator for
  each milestone.

## Out of scope

Shipped dialect content, a built-in kanji dictionary, dialect-accurate audio,
recording the user's own audio, live sharing between users (files can be
sent, but there is no shared bank), CSV/Anki formats and iCloud sync (until
milestone 7).
