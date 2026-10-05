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
- **Search:** ranked search inside the Word Bank tab with tokens and chips
  (no query syntax), recent searches, saved searches shown as smart folders,
  and entries in iOS/macOS Spotlight. No app-wide search across Verbs and
  Grammar.
- **Import / export:** JSON only. Import creates missing folders and tags and
  merges with what is already there using a "combine both, lose nothing" rule.
- **Speech:** keep `SpeakButton`, with a note that it uses standard pitch, not
  the dialect's.
- **Review:** flashcards in both directions.
- **Meanings and links:** several senses per entry, structured standard
  Japanese equivalents (kanji + reading), kanji chips linking to Jisho,
  automatic links to the app's words (verbs today, adjectives and nouns once
  the form-agnostic data model lands), and a derived cross-dialect view.
- **Built on the form-agnostic data model (PR #16).** The Word Bank reuses its
  `WordClass`, `Word.id` and `FormID` instead of inventing parallel types.
  See "Dependencies on open PRs".

## Design

### Entry

| Field | Required | Example | Notes |
|---|---|---|---|
| Text | yes | おおきに | What was heard / written, as the user writes it |
| Reading | no | おおきに | Kana; drives furigana and romaji search |
| Kanji spelling | no | 大きに | Etymology or written form when the text is kana-only |
| Kind (`EntryKind`) | yes (default word) | word / phrase / sentence | Filterable |
| Word class | no, words only | verb / i-adjective / na-adjective / noun | The existing `WordClass`; filterable |
| Senses | no, 0…n | "thank you" | English meaning + optional note per sense |
| Standard equivalents | no, 0…n | ありがとう; 可愛い (かわいい) | Written form, reading, note |
| Linked word | no | 行く · short negative | A curated word plus, optionally, the form the dialect entry corresponds to (行かへん ↔ `short_neg`) |
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

Search is how entries are found again, so it gets its own logic layer in
VerbKit (`WordBankSearch`), separate from the views and fully unit-tested.
The existing `VerbSearch` is a yes/no match; this one also ranks and
explains its results.

#### The search field

- The existing `inlineSearch` modifier, prompt "Search word bank…".
- What's in the field is **text plus tokens**
  (`searchable(text:tokens:suggestedTokens:)`). Tokens are filters; the text
  is matched against entry content.
- The chip row under the field (Dialect ▾ by region › dialect, Kind ▾,
  Tag ▾) adds and removes the same tokens. Tokens are the single source of
  truth, so a chip and its token are always in sync.
- Inside a folder, search scopes (`searchScopes`) choose **This folder**
  (with subfolders, the default) or **All entries**.

#### Tokens

| Token | Example | Matches |
|---|---|---|
| Dialect tag | 熊本弁 | Entries with that tag |
| Region | 九州 | Entries with any dialect tag in that region |
| Prefecture | 岐阜県 | Entries with any dialect tag in that prefecture |
| Custom tag | #food | Entries with that tag |
| Folder | Trip 2026 › Takayama | That folder and its subfolders |
| Kind | Phrase | Entries of that kind |
| Special | Unfiled, No dialect tag | Entries without a folder or dialect tag |

- **Suggested tokens** appear while typing, matched with the tag-suggestion
  normalisation: "kuma" suggests 熊本弁, "kyushu" suggests 九州, "taka"
  suggests 高山弁 and the folder "Takayama". Only tokens that would return
  results are suggested. Picking one replaces the typed fragment.
- Different tokens combine with **AND**. Region and prefecture tokens are the
  way to say "any of these dialects".

#### Matching

- **Normalisation** (`JapaneseNormalizer`, shared with tag suggestions and
  import merging): NFKC (full/half width), katakana → hiragana, Latin case
  and diacritics folded (ō → o), whitespace trimmed.
- **Romaji:** a Latin query is also converted with the existing `Romaji`,
  which drops half-typed endings, so results narrow as you type ("ooki" →
  おおき). A Latin query matches both English fields directly and Japanese
  fields through its kana form.
- **Loose kana fallback:** if the exact kana finds nothing, long vowels are
  folded on both sides (おお/おう → お, ー removed), so "okini" still finds
  おおきに. Fallback matches rank below exact ones.
- **Several words:** the text is split on spaces; every word must match
  somewhere in the entry (AND), in any field. Japanese typed without spaces is
  one word. Text in quotes ("お腹すいた") must match as a whole phrase.
- **Fields searched,** strongest first: text; reading and kanji spelling;
  standard equivalents (written and reading); sense meanings; tag names
  (typing "kansai" finds entries tagged 関西弁 even without a token); sense
  notes; folder name; source and notes.

#### Ranking

- Each match scores **field weight × match quality**, where quality goes
  exact > starts with > word starts with > contains > loose fallback. An
  entry's score is its best match; with several words, the scores add up.
- Ties go to the most recently updated entry.
- **When there is text,** results are one flat list in rank order, not
  grouped. **With only tokens,** the list keeps its normal grouping and sort.

#### Results

- Each row shows **why it matched** when that isn't obvious: "Standard:
  ありがとう", "Meaning: thank you", "Note: …from Yuki at the izakaya…",
  with the matched part highlighted. VoiceOver reads the same text.
- Rows outside the current folder show their folder path.
- **No results:** "No results for 'X'" with ways out: drop a token ("Without
  熊本弁: 3 results"), switch to All entries when scoped, and **Add "X" as a
  new entry** (opens the editor with the text filled in, so search doubles as
  quick capture).

#### Recent searches

- With the field focused and empty, the last 10 searches (text + tokens) are
  shown, newest first. Tapping one restores it; swipe to remove; "Clear".
- A search is recorded when a result is opened or the search is submitted,
  not on every keystroke, and duplicates move to the top.
- Stored on this device only (`UserDefaults`), never exported or synced.

#### Saved searches

- **Save search** (in the search bar's menu, available when there is text or
  a token) stores the text, tokens, folder scope and sort under a name. The
  name defaults to the filters ("熊本弁 · Phrase") and can be changed.
- Saved searches appear in a **Saved searches** section on the root screen
  under the smart rows, each with a live count, and behave like smart
  folders: opening one runs the search.
- Rename, reorder, edit (re-opens the search to change it and save again)
  and delete. Deleting one never touches entries.
- Saved searches are user data: stored in the Word Bank store, included in
  full exports and imports (merged by id, then by name), and synced once
  iCloud arrives.
- A token that points to a deleted tag or folder is dropped from the saved
  search, with a note on it ("1 filter no longer exists").
- Saved searches can be used anywhere a folder can: **Review**, **Export**
  and the widget's source.

#### Spotlight

- Entries are indexed for system search on iOS and macOS. Typing おおきに or
  "thank you" in Spotlight finds the entry, and tapping it opens the entry in
  the app.
- Built on the `SpotlightIndexer` from PR #24 rather than a second
  mechanism: a third domain, `wordbank`, next to `verbs` and `lessons`. Each
  item's unique identifier is its `verbtable://wordbank/<uuid>` route URL,
  so a tapped result goes through the same `RootView.open(_:)` and
  `onContinueUserActivity(CSSearchableItemActionType)` path as verbs and
  lessons. Title is the text, description the reading, first standard
  equivalent and first meaning; keywords are reading, kanji spelling,
  equivalents, meanings, tag names and folder name.
- Unlike verbs and lessons (which replace their whole domain when the data
  changes), Word Bank items are updated **incrementally**: indexed on save,
  removed by identifier on delete, batched for imports and folder deletes.
  The whole domain is rebuilt only when its index version changes or the bank
  is restored from backup.
- `WordBankEntryAppEntity` (an `AppEntity` with an `EntityStringQuery` backed by
  `WordBankSearch`) lives in `App/Intents/` beside PR #24's `VerbIntents`, so
  Shortcuts can pick entries and the quick capture intent can return one.
- **Settings › Word Bank › Show in Spotlight** (on by default). Turning it
  off removes every indexed entry.
- Opening a Spotlight result uses the `wordbank` route, so it dismisses
  sheets like the existing deep links.

#### Performance

- Search runs in memory over the whole bank. Each entry's normalised search
  keys are computed once and cached in `WordBankStore`, and recomputed only
  when the entry changes. They are never stored.
- Target: under 16 ms per keystroke for 5,000 entries on a recent iPhone,
  checked with a package performance test.

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
- **Word links:** a standard equivalent is matched against the app's curated
  words (any `WordClass`): their `dict`, `kanji`, **and every conjugated
  surface in `forms` and `alternates`**, looked up through the `FormCatalogue`.
  So ありがとう finds nothing, 疲れる shows "Open 疲れる", and 行かない shows
  "行かない = 行く · Short · negative" (label from the catalogue) with a link
  to the page. A manually linked word shows the same way.
- **Dialect form vs standard form:** when the link has a form
  (行かへん → 行く, `short_neg`), the card shows the standard surface from
  `word.forms[formID]` next to the dialect one. Picking the form is offered
  automatically when an equivalent matched a conjugated surface, so linking
  usually takes one tap.
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

**As built (2026-10-06).**

- The file also carries `smartFolders` (name, tag names, any/all); a full
  backup includes them. Review history is not in the file yet: milestone 5
  adds it, and unknown fields are ignored, so older apps still read newer files
  of the same major version.
- A dialect tag from a file with no region, no prefecture and no catalogue
  match becomes a custom tag (a dialect tag needs a region). Only a hand-written
  tag record (one with no id) has gaps such as romaji filled from the bundled
  catalogue, so an export always imports back exactly.
- New folders, tags and entries keep the file's ids when those are unused
  locally, so Restore reproduces the bank exactly; otherwise they get fresh ids.
- Import is applied through one all-or-nothing write
  (`WordBankPersisting.apply`); a failed save leaves the bank as it was.
- **Restore backup** (Settings › Word Bank) replaces the bank with the backup
  after taking a backup of the current one. An empty bank is never backed up.
- A `.wordbank` file opened from outside the app (Files, AirDrop, Mail) shows
  the same import sheet.

All of this logic (`WordBankArchive` for the format, `WordBankImportPlanner`
producing the preview plan, `WordBankTransfer` backing up and applying) lives
in VerbKit and is unit-tested without UI.

### Starter packs (added 2026-10-06)

Ready-made `.wordbank` files that live in the GitHub repo and that the user can
add from inside the app: Kansai essentials, ordering food, slang, and so on.
A pack is an ordinary `.wordbank` file, so adding one is an import (see
"Import and export") with a catalogue in front of it and a new folder behind
it. It needs the archive format and `WordBankImportPlanner` from milestone 2.

**Decisions.**

- A pack always goes into **a new folder** at the root of the Word Bank, named
  after the pack (the sibling-name rule makes "Name (2)" if that exists). The
  pack's own folders become subfolders. The user can rename or delete it like
  any folder, and deleting it removes the whole pack.
- Tags are an **optional step**: "Also tag these", shown on the preview with
  the pack's tags listed as chips (the dialect tag, and any custom tags the
  pack defines), each switchable. It is on by default for the pack's own
  dialect tags and off for anything else. With the step off, entries are added
  with no tags and no tags are created. Tags that match existing ones are
  reused, as in any import.
- Nothing is downloaded until the user opens **Starter packs** (Word Bank menu
  › Starter packs) and taps Add. No pack data is fetched at launch.

**Where packs live.** `data/packs/<id>.wordbank` and `data/packs/index.json`.
The signed manifest gets a `packs` entry with the index's version and sha256,
exactly like `grammar` and `furigana`. The index lists each pack with its own
sha256, so the signature covers the index and the index covers every pack.
The app refuses an index that does not match the manifest, a pack that does not
match the index, and an untrusted manifest (shown as "Couldn't verify the pack
list"). Data changes need the owner's `sign_manifest.py sign` before merge.

**Index entry.**

```
id, title, summary, version, sha256, entryCount, size
region / dialect (optional), tags [names], languageNotes
review: "native-reviewed" | "community" | "unreviewed", reviewedBy (optional)
license, sources [text]
```

`license` and `sources` are required: a check rejects a pack without them.
`review` is shown on the list row and the preview ("Unreviewed: written by the
app's author, not checked by a native speaker"), so the user knows how far to
trust the content.

**Screen.** A list of packs with title, summary, entry count and review badge;
grouped by Dialects, Food, Slang, Everyday. Tapping one opens a preview: sample
entries, folders and tags it adds, how many entries are already in the bank,
review status, source and licence. Below that, the "Also tag these" step and
**Add to Word Bank**. The index is cached after the first successful fetch so
the list still opens offline; adding a pack needs the network. Packs already
added show "Added" and, when the index has a newer version, "Update".

**Adding.** Planner run with destination "Into a folder" set to a freshly
created folder, tags filtered by the step above, and `source` on each new
entry set to "Starter pack: <title>". One save; the automatic backup from the
import flow is taken first. Entries that match something already in the bank
are combined by the usual rules and stay in their current folder; the preview
says "n already in your Word Bank (kept where they are)".

**Updating.** The app remembers per pack: id, version and the folder id it
created (a small on-device record, not part of the bank and not synced yet).
Update re-imports the new file into that folder. Because importing never
overwrites or deletes, the user's edits survive, new entries appear, and
entries removed upstream stay. If the folder is gone the record is dropped and
the pack shows as not added.

**First packs.** Three, to prove the path: a 10-entry "Try the Word Bank"
sample (also offered from the empty state), "Kansai essentials" and "Ordering
food". All start as **unreviewed** until a native speaker or the owner checks
them.

**Tooling.** `scripts/validate_packs.py` checks every pack parses as a
`.wordbank` file, has required metadata, no duplicate entries, is under 2 MB
and matches its index sha256; `update_data.py --check` runs it.

**Errors.** Network failure, a hash mismatch, a newer major `version` and an
oversized file each show a plain message and change nothing.

**Testing.** VerbKit: index decoding and verification (bad hash, bad
signature, missing licence), the add flow against the planner (new folder
created, tags on/off, existing entries combined, second add changes nothing),
update (new entry added, edited entry untouched, deleted folder drops the
record), caching and offline. App: the list, preview and add on the
simulator.

**Out of scope for packs v1.** User-made or third-party packs, packs from
other URLs, automatic update checks, and syncing the installed-pack record.

### Suggestions while typing (added 2026-10-05)

Under the text, the editor offers tap-to-apply chips for a reading, standard Japanese,
meanings, kind and a likely dialect, with "Use all". Nothing is written until the user
taps. They come from Apple's on-device model (`FoundationModels`, guided generation), so no
text leaves the device; the dialect must be an id from the bundled catalogue and is checked
afterwards, low-confidence answers are dropped, and the card says to check them because
dialect words are often wrong. A coordinator in VerbKit (`EntrySuggestionModel`) waits for a
pause in typing, drops stale answers and hides what the entry already has; the model itself
is the only app-side piece, behind the `EntrySuggesting` protocol. When the model or
Japanese isn't available the card stays hidden and Settings says why. Settings › Word Bank ›
Suggest while typing turns it off.

### Smart folders (added 2026-10-05)

A smart folder is defined by one or more tags and shows every entry that has any one of
them or all of them (a per-folder switch). It sits under "Smart folders" on the root screen
with a live count, can be edited and deleted, and never moves or deletes entries. Deleting a
tag takes it out of every smart folder, which stays. This is the tag-only slice of "Saved
searches"; milestone 3 extends it to text, tokens and folder scope.

### Add / edit sheet

Text first, then reading, standard equivalents (＋ to add more), senses (＋),
kind, folder, tags (token picker with "New dialect tag…" / "New tag…"), kanji
spelling, word link (searchable picker over the app's words, then an
optional form picker listing the catalogue forms that word has),
source/notes. When the text has kanji and the reading is empty, the reading
is pre-filled from the furigana dictionary (`FuriganaDictionary.reading(of:)`,
PR #18) for the user to confirm or correct. Only
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
- The linked word is stored as two strings, never as a relationship: the
  `Word.id` (`"verb:いく"`, `"i-adjective:たかい"`) and an optional `FormID`
  raw value. The synced word cache (`VerbEntity` today, PR #16's payload
  `WordEntity` later) is rewritten or even re-created by a re-sync, so a
  relationship into it would be lost. A link whose word or form no longer
  exists is simply not shown. Import also accepts a bare verb `dict` (the
  form verb deep links keep, PR #16 open question 5) and maps it to
  `verb:<dict>`.
- Entry kind is its own `EntryKind` enum, not a reuse of `QuizQuestionKind`
  or `WordClass`; the optional word class is the existing `WordClass`.
- Naming: every Word Bank type is prefixed `WordBank…` (or `DialectTag`,
  `CustomTag`), never bare `Word…`, because `Word`, `WordClass`,
  `WordExample` and `WordEntity` belong to the curated data model. SwiftData
  classes end in `Entity` (`WordBankEntryEntity`); App Intents entities end in
  `AppEntity` (`WordBankEntryAppEntity`). The app target imports VerbKit, so an
  app type with the same name as a VerbKit type hides it (today's Siri
  `VerbEntity` already hides VerbKit's SwiftData `VerbEntity` inside the app).
- **Separate store:** the Word Bank models go in their own
  `ModelConfiguration` (`WordBank.sqlite` in the App Group container), inside
  the same `ModelContainer` as today. The synced verb/grammar data and the
  user's notebook never share a file, which keeps user data safe from data
  sync and lets iCloud sync later cover only this store.
- Store and persistence follow the existing pattern:
  `WordBankPersisting` protocol, `SwiftDataWordBankPersisting`,
  `@Observable WordBankStore` in the environment.
- PR #16 step 5 rebuilds the synced cache (and its open question 11 may drop
  the coexistence release and simply re-sync). Because the Word Bank lives in
  its own configuration and file, that work must never delete or migrate
  `WordBank.sqlite`; a test pins this.
- `dialects.json` is bundled in `Sources/VerbKit/Resources/` next to PR #16's
  `forms.json`, using the same `resources:` entry style in `Package.swift`.
- Nothing is seeded: the dialect catalogue is read-only bundled data used
  for suggestions, and tags are rows only once the user creates them.
  `DialectTag` stores an optional `catalogueID`.
- `WordBankSavedSearch` model: id, name, query text, tokens (as `Codable`
  descriptors holding ids, so a renamed tag or folder still matches), scope
  folder id, sort, order. Archive format version 1 has an optional
  `savedSearches` list.
- Automatic pre-import backups are `.wordbank` files in the app's
  Application Support folder, not in the database.

## Milestones

Each ships on its own:

1. **Core (done 2026-10-05, PR #51; also brought forward from later: on-device suggestions and smart folders over tags):** models, separate store, dialect catalogue, store, tab, list,
   folders, add/edit, detail (comparison card, senses, kanji chips, speech,
   text actions), tags and tag management with suggestions, search with
   tokens, chips and folder scopes, ranking, match explanations, no-results
   actions, recent searches.
2. **Import / export (done 2026-10-06, PR #53; iPad and macOS checks parked):** `.wordbank` format, export scopes, import preview,
   folder and tag generation, combine merge, automatic backups and restore.
2b. **Starter packs:** catalogue on GitHub, signed index, Starter packs screen,
   add into a new folder with the optional tag step, update, first three packs.
   Needs milestone 2's archive format and planner.
3. **Saved searches:** model, smart-folder section, edit, use in export
   (review and widget pick them up in their own milestones).
4. **Links:** word links (automatic and manual, with forms), dialect-vs-
   standard form card, same-meaning-in-other-dialects section, `wordbank`
   route. Needs PR #16's foundations (`Word`, `FormCatalogue`) merged.
5. **Flashcard review.**
6. **Widget.**
7. **Quick capture and Spotlight:** `WordBankEntryAppEntity`, the App Intent,
   the `wordbank` Spotlight domain and its setting. Needs PR #24 merged.
8. *(later)* iCloud sync, CSV and Anki formats, share extension, map of Japan
   by prefecture.

## Components

- VerbKit: `WordBank/` (models, `Sense`, `StandardEquivalent`, dialect
  catalogue + `dialects.json`, `TagSuggester`, `JapaneseNormalizer`, `WordBankSearch` (matching, ranking,
  match explanations, token model), recent search list, folder tree operations, `WordBankArchive`,
  `WordBankImportPlanner`, cross-dialect grouping, kanji extraction),
  `Persistence/` (entities, persisting), `Store/WordBankStore.swift`,
  `Lookup/TextLookupURL.swift` (`jishoKanji`), `Navigation/` (route case),
  `VerbModelContainer` (second configuration).
- App: `WordBankTab`, `WordBankListView`, `WordBankFolderView`,
  `FolderPicker`, `WordBankDetailView`, `WordBankEditor`, `TagPicker`,
  `TagManagerView`, `ImportPreviewSheet`, `FlashcardReviewView`;
  `MainTabView` gains the tab; `project.yml` declares the `.wordbank`
  document type and exported `UTType`.
- App Intents (`App/Intents/`, with PR #24's): `WordBankEntryAppEntity`,
  `AddToWordBankIntent`; `App/SpotlightIndexer.swift` gains the `wordbank`
  domain.
- App: `SavedSearchesSection`, `SaveSearchSheet`, `SearchExplanationLabel`.
- Widgets: `WordBankWidget` + intent.

## Platforms

iOS first; macOS must compile and work through the sidebar. iOS-only
modifiers stay behind `#if os(iOS)`.

## Testing

- Package tests for: search (kana, kanji, romaji, English, equivalents, tag
  token AND), cross-dialect grouping, kanji extraction, word matching
  (dict, kanji, every conjugated surface and alternate, across word
  classes, using test catalogues), linked word/form resolution including a
  missing word or form,
  tag suggestions (normalisation of kana/romaji/macrons/弁 suffixes,
  aliases, ranking, own-tag-first and duplicate blocking, related dialects
  from existing tags, already-applied tags excluded), catalogue file decodes
  and covers all 47 prefectures, persistence round trip
  in memory, review ordering, Jisho kanji URL encoding, the new route
  parsing.
- Folders: sibling-name uniqueness, move with cycle prevention, delete with
  keep vs delete contents, scoped search including subfolders.
- Search: normalisation (width, katakana, case, diacritics); romaji partial
  input; loose kana fallback ranked below exact; multi-word AND across
  fields; quoted phrases; every token type, including region/prefecture
  expansion and folder including subfolders; folder scope; ranking order
  (field weight, match quality, recency tie-break); match explanation picks
  the right field; no-results suggestions report correct counts; recent
  searches dedupe and cap at 10; saved search with a deleted tag drops it;
  saved searches round-trip through export/import; performance test for
  5,000 entries.
- Spotlight: entity fields and keywords; index updated on save, delete and
  import; turning the setting off removes everything.
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

## Dependencies on open PRs

Checked against the open PRs on 2026-10-03. None of them conflicts with the
Word Bank's user data, but several change what it should build on.

**Status 2026-10-04:** #16 (foundations, steps 1–2), #18, #20, #21, #23, #24
and #25 are merged into `main`; #16 also gained an `other` family ("More
forms") for #25's eight forms. Only #17 is still open, so Core can start from
`main`, and milestone 7 no longer waits on anything.

| PR | What it changes | Effect on the Word Bank |
|---|---|---|
| #16 Form-agnostic data model | `Word`, `WordClass` (promoted out of `GrammarPoint`), `FormID`, `Conjugations`, `FormCatalogue` + bundled `forms.json`; later `WordEntity` replaces `VerbEntity` | Entries get an optional `WordClass`; links use `Word.id` + `FormID`; word matching iterates all classes through the catalogue; type names avoid `Word…`; `dialects.json` sits beside `forms.json`. **Merge #16 (at least its foundations) before Core starts**, so Core uses the shared `WordClass` instead of adding a temporary copy. |
| #24 Siri, Shortcuts and Spotlight | `SpotlightIndexer` (domains, route URLs as ids), `RootView.open(_:)`, `onContinueUserActivity`, `App/Intents/VerbIntents.swift` | Word Bank adds a domain to the same indexer and its entity and intent beside the verb ones; `IndexedEntity` is dropped from this spec for consistency. Milestone 7 builds on it. |
| #17 Security hardening | `onOpenURL` ignores a route that doesn't resolve, before dismissing sheets | `Route.resolve` must also know Word Bank entries (a `wordbank` route resolves when the entry exists), or Word Bank links and Spotlight results would be ignored. |
| #18 Lesson search by kana reading | `FuriganaDictionary.reading(of:)` | Pre-fills an entry's reading and gives entries without a reading a derived one for search. |
| #21 Japanese voice picker | `Speaker` uses the chosen voice | The Word Bank's `SpeakButton` follows the picked voice with no extra work. |
| #23 Favourite verbs | Starred verb ids in shared defaults | No overlap. Favourites mark curated verbs; the Word Bank holds the user's own entries. |
| #20, #25 Quiz kinds and more forms | `QuizQuestion`, `QuizForm`, more forms in `verbs.json` | Flashcards stay independent of the quiz model (self-graded, own attempt rows), so they're unaffected. More forms just means more surfaces to match. |

Merge order that keeps rework lowest: **#16 → Word Bank Core**, with #17 and
#24 landed before milestones 4 and 7 respectively (as of 2026-10-04 only #17
is outstanding). If #16's later steps
(quiz, persistence) are still in flight, the Word Bank only needs its step 2
types.

## Out of scope

Shipped dialect content, a built-in kanji dictionary, dialect-accurate audio,
recording the user's own audio, live sharing between users (files can be
sent, but there is no shared bank), CSV/Anki formats and iCloud sync (until
milestone 8), search across Verbs/Grammar/Word Bank in one field, typo
tolerance for English (beyond the loose kana fallback).
