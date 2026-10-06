# Grammar building blocks: design

Status: approved in chat 2026-10-06. Mockups: the "Verb Table Redesign" canvas (row 2,
"Building blocks" and "How patterns attach").

## Problem

Learners understand what a pattern means quickly ("you had better…", "because…"). What
they get wrong is the joining: たべたほうがいい or たべるほうがいい, しずかので or
しずかなので. Today each grammar point describes its attachment in free text
("ます-stem + すぎる"), so the app cannot link a pattern to the form it needs, show it
with another word, or quiz it, and every pattern feels like a new set of rules.

There are only a handful of forms a pattern attaches to. Teach those once as building
blocks, tag every pattern with the block it takes, and a new pattern becomes "a meaning
plus a block". This matches how the owner's evening class (Genki I, lesson 12: ので,
〜ほうがいいです, 〜すぎる) presents grammar, without tying the app to one textbook.

## Decisions

- **Content (option B):** a small list of N5 い-adjectives, な-adjectives and nouns,
  about 30 words, alongside the 64 verbs. Not full adjective pages.
- **Rules (option B):** each attachment rule names its slot(s) and the ending that
  follows, so the app builds the pattern for any word. Irregulars live in the slot
  forms, not in each grammar point. A rule without an ending falls back to a tag.
- **Forms are generated in the data pipeline (approach A):** `update_data.py` fills
  adjective and noun forms by rule, as it already does for verb forms. The app has no
  conjugation code for this.
- **Courses (option C):** curated textbook lesson mappings in the data, plus an
  on-device "My course" that can start from a textbook or from nothing. Never limited to
  one textbook.
- **Three milestones,** each shipping on its own: 1 foundations, 2 connection quiz,
  3 courses.

## Design

### Slots

Six forms a pattern attaches to, per word class (model words たべる, たかい, しずか, あめ):

| Slot | Form id | Verb | い-adj | な-adj | Noun |
|---|---|---|---|---|---|
| `plain` | `short_pos` | たべる | たかい | しずかだ | あめだ |
| `plainNeg` | `short_neg` | たべない | たかくない | しずかじゃない | あめじゃない |
| `plainPast` | `short_past` | たべた | たかかった | しずかだった | あめだった |
| `plainPastNeg` | `short_past_neg` | たべなかった | たかくなかった | しずかじゃなかった | あめじゃなかった |
| `stem` | `stem` | たべ | たか | しずか | (none) |
| `te` | `te` | たべて | たかくて | しずかで | あめで |

- The verb stem is the ます form without ます (たべ, のみ, し, き).
- **いい** and compounds ending in いい (かっこいい) take よ: よくない, よかった, よくなかった,
  よくて, stem よ (so よすぎる).
- **The な switch** (`da_to_na`): for な-adjectives and nouns, `plain` drops だ and adds
  な (しずかな, あめな). It touches only that one slot; past and negative forms are
  unchanged (しずかだったので). This is the only rule the app applies itself.
- A noun has no `stem`; a rule asking for one is invalid.

### Data

**`data/words.json`** (new, hand-authored except the generated forms):

```json
{
  "words": [
    { "class": "i-adjective", "dict": "たかい", "kanji": "高い",
      "meaning": "expensive; tall", "jlpt": "N5",
      "forms": { "short_pos": "たかい", "short_neg": "たかくない", "short_past": "たかかった",
                 "short_past_neg": "たかくなかった", "stem": "たか", "te": "たかくて" } }
  ]
}
```

- `class` is `i-adjective`, `na-adjective` or `noun` (`WordClass` raw values). Verbs stay
  in `verbs.json`.
- `update_data.py` fills `forms` from `class` and `dict` and `--check` fails when they are
  stale. Authors never write forms by hand; an override is not supported in milestone 1.
- `dict` for a な-adjective is the bare stem (しずか), as `Word.dict` already documents.
- The furigana coverage check includes `words.json`: every kanji needs a reading in
  `furigana.json`, and `kanji` must spell `dict`.
- New manifest entry `words` (version and sha256), signed like the others. A
  `WordsSyncService` and storage follow the `GrammarSyncService` pattern, so new words
  arrive without an app update. Decoded into the existing `Word` model.

**Form catalogue** (`scripts/form_catalogue.py` → `forms.json`):

- `short_pos`, `short_neg`, `short_past`, `short_past_neg` and `te` also apply to
  `i-adjective`, `na-adjective` and `noun`.
- New form `stem` for `verb`, `i-adjective` and `na-adjective`. `update_data.py` fills it
  for verbs from the ます form (the existing `masu_stem` helper).

**Grammar attachment rules** (`grammar.json`) gain three optional fields:

```json
{ "word_class": "na-adjective",
  "slots": ["plain", "plainNeg", "plainPast", "plainPastNeg"],
  "da_to_na": true,
  "then": "ので",
  "pattern": "short form (だ → な) + ので",
  "example": "静かだ → 静かなので" }
```

- `slots`: one or more slot names. Absent means the rule is free text only, as today.
- `da_to_na`: only valid with `plain` among the slots and a `na-adjective` or `noun`
  class.
- `then`: the ending appended to the slot form. Absent means tag only (the chip shows,
  no examples are built).
- `pattern` and `example` stay as the human-readable line.
- `update_data.py` rejects unknown slots, `stem` on a noun rule, `da_to_na` where it
  cannot apply, and `then` without `slots`.

**Grammar card field** `contrasts` (optional list):

```json
"contrasts": [
  { "pattern": "〜から", "id": null,
    "explanation": "ので sounds softer and more polite, so it suits explaining yourself. から is more direct and can sound like an excuse.",
    "examples": [ { "jp": "電車が遅れたので、遅刻しました。", "en": "The train was late, so I was late." },
                  { "jp": "電車が遅れたから、遅刻した。", "en": "The train was late, that's why I was late." } ] }
]
```

`id` links to another grammar point when one exists.

**Textbook mappings (milestone 3)** in `grammar.json`:

```json
"books": [ { "id": "genki-1", "title": "Genki I", "edition": "3rd", "lessons": 12 } ],
"grammar": [ { "id": "node", "taught_in": [ { "book": "genki-1", "lesson": 12, "reviewed": false } ] } ]
```

Only lesson numbers and our own pattern names, never a book's text or examples.
`update_data.py` checks that each `book` exists and each `lesson` is within range.

### VerbKit

- `GrammarSlot` (enum of the six slots, with its form id) and `SlotForm`: given a `Word`
  and a slot, return the form, applying `da_to_na` when asked. Returns nil when the word
  has no such form (a noun's stem).
- `AttachmentRule` gains `slots: [GrammarSlot]`, `daToNa: Bool`, `then: String?`, and
  `func build(for word: Word, slot: GrammarSlot) -> String?` (slot form plus ending).
- `GrammarPoint` gains `contrasts: [GrammarContrast]` and (milestone 3)
  `taughtIn: [LessonRef]`. Old JSON without these fields still decodes.
- `attachesToVerbs` and the verb page's Grammar section read the rules as today; slots
  only add information.
- Milestone 2: `ConnectionQuestion` builder (grammar point × rule × slot × random word
  of that class) and answer checking against `build`, normalised with the existing
  kana comparison.
- Milestone 3: `CourseStore` (on-device, its own store, not the synced data): a course
  is an optional base book plus the user's lessons, each a name and ordered grammar ids,
  stored as edits over the base mapping so data updates still apply.

### App

**Grammar tab:**

- A "Building blocks" row at the top opens the table: four classes × six slots with one
  model word each. Tapping a cell explains the slot and lists the grammar points that use
  it (from the slot tags). A word picker swaps the model word for any word in the data.
- Milestone 3: a "By lesson" view (My course) next to "By level" (JLPT).

**Grammar card,** in this order for every point:

1. Meaning (`summary`).
2. How it attaches: one row per word class with the slot chip, the ending and a live
   example (しずか + なので). Tapping a chip opens Building blocks at that slot. "Try
   another word" cycles the example through the words of that class. Rules without
   slots show their `pattern` text as today.
3. Examples (`usages`).
4. Don't confuse with (`contrasts`), when present.
5. Traps (`pitfalls`).
6. Practise this pattern (milestone 2).
7. Milestone 3: the lesson tag from My course or the chosen textbook, with "unreviewed"
   shown for unreviewed mappings.

**Connection quiz (milestone 2):** a quiz kind in the existing quiz. The prompt shows a
word and an ending (たかい + ので); the learner types or picks the joined form. Questions
come from grammar points with `then`, a random word of the rule's class and one of its
slots. A wrong answer names the block that was needed ("な-adjectives take な before
ので"). Started from a card (that pattern) or from the quiz topic sheet ("Connections").
Progress is recorded like other quiz kinds.

**My course (milestone 3):** Settings › Grammar › My course. Pick a textbook (its mapping
becomes the starting point) or start empty; name lessons; add, remove and reorder grammar
points per lesson.

### Content (milestone 1)

- About 30 N5 words, roughly 12 い-adjectives (including いい and the taste words
  あまい, からい, にがい, すっぱい, しょっぱい), 9 な-adjectives and 9 nouns.
- New grammar points `node` (〜ので) and `hou-ga-ii` (〜ほうがいいです), each with a
  contrast (ので vs から; ほうがいい after た vs the dictionary form) and traps
  (しずかなので, not しずかだので; never なかったほうがいい).
- Slots and endings added to existing points where they fit: すぎる, やすい, にくい
  (`stem`), んです (`plain` with `da_to_na`, and the other plain slots), ている, てしまう,
  ておく, てみる (`te`).
- All written by the assistant and unreviewed until the owner or a native speaker checks
  them. Every `data/` change is re-signed by the owner before merge.

## Milestones

1. **Foundations (done 2026-10-06):** words.json and its sync, form catalogue changes, slot fields on
   grammar rules and their validation, `contrasts`, the Building blocks screen, the new
   grammar card, ので and 〜ほうがいいです, slots on existing points.
2. **Connection quiz.**
3. **Courses:** textbook mappings, My course, By lesson view, lesson tags on cards.

**As built (milestone 1):**

- `stem` is a slot form, not a form-catalogue entry: the catalogue is also the list of forms
  shown on verb pages and quizzed, so a catalogue `stem` would have added a "Stem" row and
  stem questions. Verbs derive it from the ます form; adjectives have it in words.json.
- ので and 〜ほうがいいです are N4, matching the common lists the app follows for levels.
- ている, てしまう, てみる are tagged with their slot but have no ending, because an ending
  would build forms for verbs that do not take them (あっている).
- Building blocks opens as a sheet (from the Grammar list and from a lesson's slot chips),
  not a pushed screen: a link in the split view's sidebar would land in the detail column.

## Testing

- **Python (`test_update_data.py`, `test_form_catalogue.py`):** generated forms for each
  class including いい, かっこいい, な-adjectives and nouns; slot validation (unknown
  slot, noun stem, misplaced `da_to_na`, `then` without slots); furigana coverage for
  words.json; book and lesson checks (milestone 3).
- **VerbKit:** slot → form for every class; the な switch only on `plain`; `build` for
  every rule in the real grammar.json against every word of its class (no nil where a
  form should exist); old grammar JSON without new fields decodes; words sync like
  grammar (manifest, signature, hash); quiz question building and checking (milestone 2);
  course merge of a base mapping with user edits (milestone 3).
- **App:** simulator checks per milestone (Building blocks table and word picker, card
  chips and live examples, quiz flow, My course). iPad and macOS checks stay parked until
  the owner resumes them.

## Out of scope

- Multi-part templates (〜たり〜たりする, 〜ば〜ほど).
- Verb negative + すぎる (たべなさすぎる) and adjective ない + すぎる (なさすぎる) as built
  forms; they stay as pitfall text.
- Audio for the new words.
- Syncing My course across devices.
- Full word pages for adjectives and nouns.
