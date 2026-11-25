# Study reminders — design

Status: agreed and built 2026-11-25. Extends the opt-in Verb of the day reminder
(`ReminderScheduler`, `DailyReminder`) with two more local notifications. No server: everything is
scheduled on the device, like today's reminder.

## Owner's choices

1. **Separate switches.** Settings › Reminders has three switches, each off by default with its own
   time: **Verb of the day** (09:00), **Review** (18:00), **Streak keeper** (20:00).
2. **Tapping the review reminder starts a Weak spots quiz** with the usual question count, through a
   new link, `verbtable://quiz/weak`.

## The two new reminders

**Review.** "8 forms to review" — sent at its time on each of the next 14 days while there are weak
(verb, form) pairs among the verbs at the visible levels (`QuizProgress.weakPairs(among:)`).
- The count is exact when it is scheduled: weakness only changes when a quiz is answered, and every
  answer reschedules.
- Skipped on a day you have already answered a quiz question, and on a day the streak keeper is
  scheduled (so at most two of our notifications arrive on one day: Verb of the day plus one of
  these).
- None when there are no weak pairs.

**Streak keeper.** "Keep your 5-day streak" — only one is ever pending:
- not practised today, current streak ≥ 1 (it ended yesterday) and its time not passed → today,
  with the current streak;
- practised today → tomorrow, with the current streak (practising tomorrow extends it);
- otherwise none. A streak that breaks while the app stays closed gets no further nudges.

The current streak and "practised today" use `QuizProgress` (any quiz kind counts, as for the streak
today) and the device calendar.

## Rescheduling

Pending requests are replaced (by identifier prefix: `verb-of-the-day-`, `review-`, `streak-`)
whenever the app becomes active, a quiz answer is recorded, or a reminder setting, the levels or the
verbs change. Turning a switch on asks for notification permission once; if it is denied the switch
stays off and the footer says how to allow it.

## Link

`verbtable://quiz/weak` starts a Weak spots quiz over the verbs at the visible levels. With no weak
pairs it opens the quiz topic sheet instead. `QuizLink` gains a weak-spots form; `quiz` and
`quiz/<topic>` are unchanged. Unknown paths still return nil. An Android client would treat it like
any other `verbtable://` route.

## Wording (App)

- Review: title "Time to review", body "8 forms to review. Tap for a Weak spots quiz." (1 form: "1
  form to review…").
- Streak keeper: title "Keep your 5-day streak", body "One quick quiz keeps it going." (1 day: "Keep
  your streak going").
- Settings footer: "Review: only when you have weak spots. Streak keeper: only on days you haven't
  practised yet."

Out of scope: per-notification actions (answer in the notification), Word Bank resurfacing,
rotating verb/grammar/counter, background refresh.
