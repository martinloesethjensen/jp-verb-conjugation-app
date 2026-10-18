# Stable verb ids (homophones)

Status: decided (A, `dict:kanji`, CI guard against the published manifest). Issue #27.

## Problem

`Verb.id` is the kana dictionary form (`var id: String { dict }`). Two verbs that are spelled the
same in kana cannot both exist: 着る and 切る are both きる. #19 had to leave 切る out for this reason.
The same will happen with other verbs (かける, あく, かわる, はく, ひく, …) as the list grows from 64
to about 100, and far more with adjectives and nouns (はし, あめ, かみ, あつい) once #42 lands.

The id is stored or linked in many places, so a change later is a migration:

| Where | How it uses the id |
|---|---|
| Favourites (`FavouriteVerbs`) | `Verb.id`s, one string in the shared App Group defaults |
| Quiz history (`QuizAttemptEntity.verb`) | **`verb.dict`**, not `verb.id`: written by `QuizViewModel.record` and read by `QuizProgress` |
| Progress sheet (`QuizProgressView`) | shows `weak.verb` as text and looks the kanji up by that string |
| Widget configuration (`VerbChoice.id`) | `Verb.id`, stored by WidgetKit in the user's widget |
| Widget "favour missed verbs" (`Widgets/VerbWidget.swift`) | matches history against `verbs.map(\.dict)` |
| Links: `Route.verb(id)`, `verbtable://verb/<id>` | `Verb.id`, percent-encoded. Used by widgets, Siri/Shortcuts (`ShowVerbIntent`), reminders (`DailyReminder`) and Spotlight (`SpotlightIndexer`, as the unique identifier) |
| Quiz distractors (`QuizGenerator`) | `$0.dict != entry.verb.dict` |
| Verb of the day (`DailyPick`) | an index into the stored order, not an id |
| `Word.id` (#16) | `"\(wordClass.rawValue):\(dict)"`, so already class-namespaced, but it still collides inside a class |

Links in the wild (a Shortcut, a Spotlight result, a notification) and saved favourites and history
must keep working.

## Options

| | A. Keep `dict`; explicit `id` only on a collision | B. Opaque id for every verb | C. Composite `dict` + kanji for every verb |
|---|---|---|---|
| Existing ids | unchanged | all change | all change |
| Migration of favourites, history, widget config, links | none | needed for every store | needed for every store |
| Survives fixing a spelling or kanji | yes (id is frozen) | yes | **no** |
| Readable in data and links | yes | no | yes |
| Cost | small | large | large |

C is already disproved by this project: #70 removed the 付ける kanji from つける because the meaning is
"turn on", which is usually written in kana. A kanji-based id would have changed.

B is the cleanest model but buys little here: spelling corrections are rare, and it forces a migration
of every store plus every link already shared.

## Recommendation: A

- A verb may carry an optional `id` in `verbs.json`. `Verb.id` is `id ?? dict`. Nothing changes for the
  64 verbs that exist.
- When a new verb's `dict` collides with an existing one, the **newer** verb gets an explicit id
  `dict:kanji`, for example `きる:切る`. The older verb keeps the bare `きる` for good.
- **An id never changes once shipped**, even if its verb's kanji or kana is corrected. Corrections
  edit the other fields.
- `update_data.py` checks that ids are unique and contain only letters, digits, kana, kanji and `:`
  (all of which `Route.encode` already percent-encodes safely), and that no existing id disappears
  (compare with the published manifest in CI).
- The same rule applies to adjectives and nouns; `Word.id` becomes `"\(wordClass.rawValue):\(id)"`
  with the same optional `id`.

## What has to change

1. `Verb` and `Word`: decode the optional `id` and use it everywhere `dict` stood in for an id. `Word(verb)`
   must pass the verb's id, not `dict`.
2. Quiz history: `QuizViewModel.record` writes `question.verb.id` instead of `.dict`. For every
   existing verb `id == dict`, so **old rows stay valid with no migration**. `QuizProgress` already
   treats the field as an opaque string. The two `QuizResult(verb:)` uses are display text on the
   results screen and stay as the kana. `QuizProgressView` must map a stored id back to its verb to
   show the kana and kanji, instead of printing the id (which would read `きる:切る`).
3. `Widgets/VerbWidget.swift`: match history against `verbs.map(\.id)`.
4. `QuizGenerator`: compare distractors by `id`, so a homophone is not dropped.
5. `update_data.py`: accept and validate `id`, add the uniqueness and charset checks, and add a test
   that a duplicate `dict` without an explicit `id` fails with a message that suggests the `dict:kanji` form.
6. Add 切る as the first collision. It exercises the whole path, and it is the verb that started this.
7. Tests: a `Verb` with an explicit id round-trips JSON and a `verbtable://` URL; favourites store it;
   two homophones both appear in a quiz and keep separate history; `Route.resolve` finds each.

Steps 1 to 5 are one PR. Step 6 follows with the data change.

## Risks and open questions

- **Telling homophones apart:** two verbs with the same kana need the kanji or meaning visible. The verb
  row already shows the kanji (`VerbRow`); the quiz prompt and the Progress sheet should too.
- **Spotlight** re-indexes when the set of ids changes (`SpotlightIndexer`), so a new id is picked up
  automatically.
- **Widget configuration** stored a bare `きる`, which keeps meaning 着る. Nothing to do.
- Decided: the explicit id has the form `dict:kanji`. It is self-describing and survives reordering; a
  numeric suffix would depend on ship order.
- Decided: there is a CI guard. `update_data.py --check` compares the ids in `data/verbs.json` with
  those in the last published `data/verbs.json` (`git show origin/main:data/verbs.json`) and fails if
  any published id has disappeared or changed. It makes `--check` depend on git history, so CI needs a
  fetch of `origin/main` (not a shallow clone), and a first run with no published file passes.
