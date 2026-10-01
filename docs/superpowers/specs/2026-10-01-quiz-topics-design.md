# Quiz Topics — Design

**Date:** 2026-10-01
**Status:** Approved in brainstorming, pending written-spec review
**Builds on:** the [native rewrite spec](2026-09-23-native-apple-rewrite-design.md)
(the quiz, section 10 for the visual direction) and the grammar sub-projects that added
the forms: [んです](2026-09-29-grammar-foundation-nd-desu-design.md),
[potential](2026-09-30-potential-form-design.md) and
[verb auxiliaries](2026-10-01-verb-auxiliaries-design.md). Those forms have no `FormKey`
case, so the quiz cannot ask about them today.

## Summary

The quiz today is a port of the web app: random (verb, form) pairs from the nine basic
forms, four choices, a 20-second timer. This adds:

- A **topic sheet** before every quiz: **Basic forms**, **Potential**, **んです**,
  **Auxiliaries** or **Everything**.
- **Every generated form** (potential, んです, ている and the other auxiliaries) as quiz
  material: 48 form fields per verb, 24 for ある.
- A second question kind, **identify the form**, beside today's **conjugate**.

Decided in brainstorming: a topic picker before the quiz (not forms mixed into one
pool), and *conjugate + identify* as the two question kinds. Sentence fill-in,
per-topic scores or history, and any data or script change are out of scope.

## 1. What the user gets

- **Random Quiz** and **Test this verb** both open a short sheet first: a list of topics
  with a Start button. Everything is preselected on Random Quiz; on Test this verb the
  sheet lists only the topics that verb has (ある has no Potential, for example).
- **Conjugate:** "What is the **Potential · polite · past** form of…" with the verb,
  its kanji and meaning, and four choices, as today.
- **Identify:** "Which form is **たべられました**?" with the verb shown for context and
  four form labels as the choices.
- Each question is one kind or the other at random, in every topic, Basic included.
- The 20-second timer, the question-count setting (5 to 30), the feedback and the
  results screen work as before. The results screen shows the form's label and its
  string for both kinds.
- For one verb the count is capped at how many questions that verb's chosen topic can
  produce (a verb has at most 9, 9, 8 or 22 forms per topic, so one verb in Basic gives
  at most 9, as today).

## 2. The forms catalogue (VerbKit)

`FormKey` stays as it is (nine cases, used by the basic forms elsewhere). A new
`QuizForm` describes everything quizzable:

```swift
public enum QuizTopic: CaseIterable { case basic, potential, nDesu, auxiliaries }

public struct QuizForm: Hashable, Sendable {
    public let id: String                       // the JSON key, e.g. "pot_masu_past"
    public let topic: QuizTopic
    public let label: String                    // "Potential · polite · past"
    public let value: @Sendable (VerbForms) -> String?
    public static let all: [QuizForm]           // 48 entries, in display order
}
```

Each entry reads one field of `VerbForms` through a key path. Counts: Basic 9,
Potential 9 (`potential` and the eight `pot_*`), んです 8, Auxiliaries 22 (ている 9,
しまう, おく, みる, すぎる, やすい, にくい each plain and polite, and ながら).

`QuizForm.forms(in:topic:for:)` returns the forms of a topic that a verb actually has
(non-empty), so ある simply has fewer.

### Labels

Built from parts, not 48 hand-written strings: **name · register · tense · polarity**,
where the name is the topic (Potential, んです, ている, てしまう, …) and is left out for
Basic, register is plain, polite or casual, tense is shown only for past, and polarity
only for negative. Examples: `て-form`, `Plain · negative`, `Polite · past · negative`,
`Potential · polite`, `んです · casual · past`, `ている · polite · negative`,
`てしまう · polite`, `ながら`.

## 3. Question generation

`buildQuestions(verbs:topic:count:)` replaces the old function. The pool is every
(verb, form) pair the verbs have in the topic (Everything is all four topics). It is
shuffled, `count` entries are taken, and each gets a kind at random:

- **Conjugate** (as today). Correct answer is the form's string. Distractors: the same
  verb's other forms in the topic first, then the same form of other verbs, both
  excluding the correct string, de-duplicated, up to three, shuffled with the correct one.
- **Identify.** Correct answer is the form's label. Distractors: labels of the same
  verb's other forms in the topic, up to three, de-duplicated, shuffled.

Why identify is safe: no verb has the same string under two forms (checked over all 25
verbs), so a string maps to one label. The generator still drops any pool entry whose
string equals another form's string for the same verb, so data that ever breaks this
cannot produce a question with two right answers.

A question is dropped, not padded, when it cannot get at least two choices, so a verb
with very few forms never shows a one-button question.

### Model changes

`QuizQuestion` gains `kind: Kind` (`.conjugate` or `.identify`) and `formLabel`; its
`form: FormKey` becomes `form: QuizForm`. `QuizResult` carries the form's label and
string for both kinds. `QuizViewModel` is unchanged apart from these types.

## 4. The app

- **`QuizTopicSheet`** — a list with radio rows (Basic forms, Potential, んです,
  Auxiliaries, Everything), each with its form count, and a Start button. Takes the
  verbs in play (all, or the one) to decide which rows show.
- **`RootView`** shows the sheet from `onRandomQuiz` and `onQuiz`, then builds the
  questions and presents the quiz as today.
- **`QuizQuestionView`** picks the prompt by kind; the choice buttons are unchanged.
  Choice text is the form string (conjugate) or the label (identify); long labels may
  wrap to two lines.
- **`QuizResultsView`** uses the label from the result instead of `formLabels`.
- **`FormLabels.swift`** is deleted once nothing uses it.
- Visual direction as before: standard controls, glass for custom surfaces, no
  accessibility-specific modifiers.

## 5. Testing, rollout and risks

### Testing

- **Swift (VerbKit):**
  - Catalogue: 48 entries, topic sizes 9 / 9 / 8 / 22, unique ids, every id is a JSON
    key, and every field the real data populates appears exactly once.
  - Labels: hand-written cases for each part (`て-form`, `Polite · past · negative`,
    `ている · polite`, `ながら`).
  - Generator: only non-empty forms; four distinct choices when enough exist and never
    fewer than two; the correct answer is always among the choices exactly once;
    identify choices are labels of the same verb; ある has no Potential questions;
    Everything covers all topics; the old Basic behaviour is kept for conjugate.
  - A real-data pass over all 25 verbs × all topics × both kinds.
- **Simulator (iPhone):** every topic, both kinds, the sheet from Random Quiz and
  from Test this verb on a normal verb and on ある, long labels not clipping, the
  results screen.

### Rollout

App-only: no data, script or model-schema change. A push changes the app source only.

### Risks

| Risk | Covered by |
|---|---|
| A form added to the data is missing from the catalogue | The coverage test over the real data |
| An identify question with two right answers | The generator's string-collision guard and its test |
| Long labels clip in a two-column choice grid | Wrapping, and the simulator check |
| A verb with few forms produces a weak question | The two-choice minimum and the count cap |
| The old nine-form quiz changes behaviour | The Basic conjugate test, plus identify now also appearing in Basic (intended) |

## Files this touches

- **New:** `QuizForm.swift`, `QuizTopic.swift` (VerbKit), `App/QuizTopicSheet.swift`,
  and tests.
- **Edited:** `QuizGenerator.swift`, `QuizQuestion.swift`, `QuizResult.swift`,
  `QuizViewModel.swift` (types only), `App/RootView.swift`, `QuizQuestionView.swift`,
  `QuizResultsView.swift`, and the quiz tests.
- **Deleted:** `App/FormLabels.swift`.

## Not in this sub-project

- Sentence fill-in questions, per-topic scores, streaks or history.
- Quizzing the eight model fields the data does not populate (volitional, passive,
  causative, causative-passive, conditionals, imperative, たい).
- A setting for the question mix, or an identify-only or conjugate-only mode.
- Any data or script change.
