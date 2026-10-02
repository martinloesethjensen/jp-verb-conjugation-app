# Quiz Progress and Weak Spots — Design

**Date:** 2026-10-02
**Status:** Approved in brainstorming, pending written-spec review
**Implements:** GitHub issue #3 (save quiz results, Weak spots quiz, streak and stats, widget
favouring weak verbs, reset).
**Builds on:** the [quiz topics design](2026-10-01-quiz-topics-design.md), the
[JLPT levels design](2026-10-01-jlpt-levels-design.md) and the widgets.

## Summary

Every answered quiz question is saved. From that history the app offers a **Weak spots** quiz
topic, a daily **streak**, a **Progress** screen, an option on the Verb Table widget to favour
verbs you miss, and a way to reset it all.

Out of scope: syncing history across devices, spaced-repetition scheduling, per-topic
goals, exporting history.

## 1. Data

- New SwiftData entity `QuizAttemptEntity` in the App Group store (added to both schemas in
  `VerbModelContainer`; a new table is a lightweight migration): `id: UUID`, `verb: String`
  (`Verb.dict`), `formID: String` (`QuizForm.id`), `kind: String` (`conjugate`/`identify`),
  `outcome: String` (`correct`/`wrong`/`timedOut`), `date: Date`. Append-only; no pruning.
- `QuizAttempt` (plain `Sendable` struct) mirrors it, with `QuizOutcome` and
  `QuizQuestionKind` raw-value coding.
- `QuizHistoryStoring` protocol (`record`, `loadAll`, `deleteAll`) with a SwiftData
  implementation (`SwiftDataQuizHistory`) and an in-memory test double.
- `QuizResult` gains `formID` so a result can be recorded; `QuizViewModel` takes an optional
  recorder closure invoked once per answer and once per timeout (from the same places that
  append results). Practise missed records too. With no recorder the view model behaves as today.

## 2. Weak spots

- Weakness is computed per (verb, form) pair from that pair's most recent 5 attempts: a miss is
  `wrong` or `timedOut`; each attempt is weighted by recency (newest weight 5 down to oldest
  weight 1); weakness = weighted misses divided by total weight. A pair is **weak** when its
  recent window contains at least one miss and its weakness is greater than 0. Newer correct
  answers lower weakness and eventually clear the pair (a pair whose last 5 attempts are
  correct is not weak).
- Pairs are ranked by weakness (higher first), then by most recent attempt, then verb order.
- `buildQuestions(pairs:count:kinds:)` is a new entry point taking explicit (verb, form) pairs,
  reusing the existing question builder (distractors and the two-choice minimum are
  unchanged). Weak spots takes the top `count` weak pairs from the visible-level verbs.
  Fewer weak pairs means a shorter quiz; it is never padded.
- The quiz topic sheet gets a **Weak spots** row first, showing the number of weak pairs.
  With none, the row is disabled with "Answer some questions first". Choosing it ignores the
  topic rows. For *Test this verb* it considers only that verb's pairs. The rest of the sheet
  and quiz flow is unchanged when there is no history.
- Hidden JLPT levels are left out of the Weak spots pool.

## 3. Streak and Progress

- A calendar day (the user's local calendar) counts when it has at least one attempt with
  outcome `correct` or `wrong`; timeouts do not count.
- **Current streak:** consecutive counted days ending today, or ending yesterday when today has
  no counted attempt yet (the streak survives until the day ends). **Best streak:** the longest
  run in the history.
- **Progress sheet**, opened by a chart toolbar button on the Verbs list next to the guide and
  quiz buttons: current and best streak; total answered; accuracy (correct / answered,
  timeouts excluded from the denominator, shown as a percentage); answers per day for the last
  7 days as a small bar chart; the 5 weakest verbs (aggregate weakness of their pairs) and the
  5 weakest forms (by form label). Shows everything regardless of hidden levels. An empty
  state when there is no history.

## 4. Widget

The Verb Table widget's configuration gains a **Favour verbs I miss** switch (default off).
When on, *Verb of the day* and *Random verb* choose from verbs that have at least one weak
pair (in verb order, so the day pick stays stable), still limited to visible levels; with
none, they fall back to the normal pool. *Pick a verb* is unaffected. Widgets reload when a
quiz ends and when history is reset.

## 5. Reset

Settings gets **Reset quiz history** (destructive, with a confirmation dialog). It deletes
every attempt, so the streak and weak spots start over, and reloads widget timelines.

## 6. Structure and testing

- **VerbKit:** `QuizAttempt`, `QuizOutcome`, `QuizHistoryStoring`, `SwiftDataQuizHistory`,
  `QuizAttemptEntity`, `QuizProgress` (pure: weakness, ranking, streaks, stats, with an
  injected `Calendar` and "now"), `buildQuestions(pairs:…)`, the recorder hook on
  `QuizViewModel`.
- **App:** recorder wiring in `RootView`/`QuizView` (plus a widget reload on quiz end),
  `QuizTopicSheet` Weak spots row, `ProgressView` sheet and toolbar button, `SettingsView`
  reset, widget intent parameter and provider.
- **Swift tests:** weakness (window, recency weights, clearing after correct answers, timeouts
  as misses), ranking ties, streak (consecutive days, gaps, today-empty rule, DST day and
  midnight boundaries, timeouts not counting), stats and accuracy, per-verb and per-form
  aggregates, `buildQuestions(pairs:)` (shorter when few pairs, no padding, distractors),
  the recorder firing once per answer and timeout and not when absent, persistence
  round-trips and `deleteAll`.
- **Simulator:** record answers in a quiz, Weak spots row (disabled then enabled), a Weak spots
  quiz, Progress numbers, reset confirmation, the widget switch.

## Risks

| Risk | Covered by |
|---|---|
| Streak or weak spots wrong around midnight/DST | Injected calendar and clock in `QuizProgress`, with boundary tests |
| History grows large | Append-only rows are small (hundreds to low thousands); revisit pruning if it ever matters |
| Recorder double-counts | One call per answer/timeout, tested |
| Widget stale after a quiz | Reload on quiz end and on reset |
| Weak spots with very little history is dull | Shorter quiz, never padded; row disabled with no history |

## Files this touches

- **New:** `QuizAttempt.swift`, `QuizAttemptEntity.swift`, `QuizHistoryStoring.swift`,
  `SwiftDataQuizHistory.swift`, `QuizProgress.swift` (VerbKit), `App/ProgressView.swift`
  (named to avoid clashing with SwiftUI's `ProgressView`, so e.g. `QuizProgressView`), tests.
- **Edited:** `VerbModelContainer.swift`, `QuizResult.swift`, `QuizViewModel.swift`,
  `QuizGenerator.swift`, `RootView.swift`, `QuizView.swift`, `QuizTopicSheet.swift`,
  `VerbListView.swift`, `SettingsView.swift`, `Widgets/VerbWidget.swift`,
  `Widgets/VerbWidgetIntent.swift`.
