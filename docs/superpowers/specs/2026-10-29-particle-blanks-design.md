# Particle blanks and the particle quiz (issue #106)

Status: shipped behind no flag; content unreviewed. Part of the cross-platform data contract.

## Problem

Particles cause the most errors at N5–N4, and the app never tested them. Lessons teach particle
choices (が/を with the potential and たい, に with 住む/乗る/入る) with no practice.

## Data: `particle_blanks` on examples

Any example object in `data/grammar.json` (usage, pitfall and contrast examples) or
`data/verbs.json` (verb examples) may carry an optional `particle_blanks` list. Examples without it
are unchanged; most have none.

```json
{ "id": "46ekb4", "jp": "水が飲みたいです。", "en": "I want to drink some water.",
  "particle_blanks": [{ "particle": "が", "at": 1, "accept_also": ["を"] }] }
```

| Key | Type | Meaning |
|---|---|---|
| `particle` | string | The particle at the blank. One of は が を に で へ と も から まで の や より か. |
| `at` | integer | Where the particle starts in `jp`, counted in **Unicode code points** from 0 (Python `str` indices; Swift `unicodeScalars`; Kotlin `codePointCount`/`offsetByCodePoints`, not `String.substring` on UTF-16). |
| `accept_also` | string list, optional | Other particles that are just as right at this blank (が/を with たい or the potential, に/へ for a destination). Same particle set; never repeats `particle`. |

`scripts/update_data.py` rejects a list that is empty, a blank whose particle does not occur at
`at`, a blank at offset 0, overlapping blanks, unknown keys and malformed `accept_also`.

### Blank ids

A blank is addressed by its example's stable id (`scripts/stable_ids.py`) and its index in the
list: `"<example id>#<n>"`, for example `46ekb4#0`. Quiz history and the review site use this id.
Add new blanks at the end of an example's list so existing ids keep their meaning. An example
without a stable id makes no question.

The blanks are part of the example object, so reviewing the example on the review site (by its id)
covers them; editing a blank changes the example's content hash like any other edit.

### What to mark

Only blanks where, given the sentence and its English translation, one particle is right (plus any
listed in `accept_also`). Be conservative: leave out a blank when a common particle the quiz could
offer also makes a correct sentence with the same meaning. The first pass marks N5 lesson examples
only; content ships unreviewed until teachers review it on the review site.

## Quiz

- Question kind `particle` (`QuizQuestionKind.particle`): one marked blank; the sentence with the
  particle replaced by ＿＿＿, its translation, and four choices.
- Choices: the marked particle plus three wrong particles drawn at random from the common ten
  (は が を に で へ と も から まで), never one in `accept_also`, and never a **substitute** that
  could stand in its place with the sentence still correct:

  | Answer | Never offered |
  |---|---|
  | が, を | は, も |
  | は | が, も |
  | も | は, が, を |
  | に | まで |
  | へ | に, まで |

  A choice is right when it is the particle or in `accept_also` (the latter are never shown).
- Feedback names the right particle ("The particle is に, not で."), shows the whole sentence and
  any accepted alternatives, and links to the lesson or verb the example comes from.
- Only lessons and verbs visible under the learner's JLPT level settings are used; a lesson's level
  is the grammar point's `jlpt`, a verb example's is the verb's.
- Started from the quiz sheet ("Particles"); length is the user's quiz question count. No timer.

## History

Each answer is a quiz attempt of kind `particle` (raw value `"particle"`):

| Field | Value |
|---|---|
| `subject` | the blank id, `"<example id>#<n>"` |
| `formID` | the right particle (`"に"`) |
| `errorTag` | for a wrong answer, `wrong_particle:<particle picked>`; nil when right |

`wrong_particle:*` is one Progress confusion category ("You often pick the wrong particle").
Particle attempts count toward streaks and totals but never make weak verb spots. An older build
skips attempts of a kind it does not know.

## Relation to #58

The transitive/intransitive pair quiz (ドア＿開いた → が) can reuse this mechanism unchanged:
mark the が/を blank on the pair's example sentences (`k3mzb2` ドアが開いている is already marked).
