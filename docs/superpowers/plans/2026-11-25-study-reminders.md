# Study reminders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in Review reminder ("8 forms to review", opens a Weak spots quiz) and Streak keeper ("Keep your 5-day streak") beside the Verb of the day reminder.

**Architecture:** VerbKit gets a pure, tested `StudyReminderPlan` that turns the quiz history, the weak-pair count, the settings and "now" into dated reminder items (no wording), and `QuizLink` learns `verbtable://quiz/weak`. App formats the text, schedules the requests in `ReminderScheduler`, adds the switches to Settings › Reminders, reschedules on quiz answers, and opens Weak spots from the link.

**Tech Stack:** SwiftUI, UserNotifications, VerbKit (Foundation), XCTest.

**Spec:** `docs/superpowers/specs/2026-11-25-study-reminders-design.md`.

## Global Constraints

- Every switch is off by default; Verb of the day 09:00, Review 18:00, Streak keeper 20:00.
- At most two of our notifications per day: Review is skipped on a day the streak keeper is scheduled and on a day already practised.
- Only one streak keeper pending at a time (today if not practised and the streak ended yesterday; tomorrow if practised today).
- Review count = weak pairs among verbs at the visible levels; none when zero.
- Wording lives in App; VerbKit returns kinds, dates, counts and URLs only.
- Identifier prefixes `verb-of-the-day-`, `review-`, `streak-`; a refresh replaces all three sets.
- Accessibility checks are parked; macOS must compile but isn't checked.

## Review Focus

1. **Time already passed today:** a review or streak time earlier than now schedules from tomorrow (review) or nothing for today (streak). Test: `testTimesThatHavePassedAreSkipped`.
2. **Midnight and the calendar:** "practised today" uses the calendar day of `now`; an answer at 23:59 then a refresh at 00:01 schedules today's streak keeper. Test: `testPractisedYesterdayOnlySchedulesToday`.
3. **Link with no weak spots:** `verbtable://quiz/weak` with none opens the topic sheet, not an empty quiz. Checked on the simulator.
4. **Permission denied:** the switch stays off and the footer explains. Checked by reading the code path (simulator permission was already granted).
5. **Reset quiz history:** clears streak and weak spots; the next refresh removes pending review/streak requests. Test: `testNoHistoryMeansNoStudyReminders`.

---

### Task 1: VerbKit — the plan and the link

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Reminder/StudyReminderPlan.swift`
- Modify: `Packages/VerbKit/Sources/VerbKit/Navigation/QuizLink.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/StudyReminderPlanTests.swift`

**Interfaces — Produces:**
- `public struct StudyReminderSettings: Equatable, Sendable { public var reviewEnabled: Bool; public var reviewMinutes: Int; public var streakEnabled: Bool; public var streakMinutes: Int; public init(...) }` with `static let reviewDefaultMinutes = 18 * 60`, `streakDefaultMinutes = 20 * 60`.
- `public enum StudyReminderKind: Equatable, Sendable { case review(count: Int), streak(days: Int) }`
- `public struct StudyReminderItem: Equatable, Sendable { public let kind: StudyReminderKind; public let fireDate: DateComponents; public let identifier: String; public let url: URL? }` — review url `QuizLink.weakSpots.url`, streak url `QuizLink(topic: nil).url`.
- `public enum StudyReminderPlan { public static func items(attempts: [QuizAttempt], weakCount: Int, settings: StudyReminderSettings, now: Date, days: Int = DailyReminder.daysAhead, calendar: Calendar = .current) -> [StudyReminderItem] }` — identifiers `review-yyyyMMdd`, `streak-yyyyMMdd`; uses `QuizProgress(attempts:calendar:now:).currentStreak` and "any attempt dated today".
- `QuizLink`: `public var weakSpots: Bool` (default false), `public static let weakSpots = QuizLink(weak)`; url `verbtable://quiz/weak`; `init?(url:)` parses `weak`; topic stays nil for it.

- [ ] **Step 1: failing tests** — `testReviewIsDailyWhileThereAreWeakSpots` (14 items at 18:00 from tomorrow when today's time passed; count carried), `testNoWeakSpotsMeansNoReview`, `testReviewSkipsAPractisedDay`, `testStreakTodayWhenNotPractised` (streak 5 ended yesterday, 19:00 now → one streak item today at 20:00, days 5, and no review today), `testStreakTomorrowWhenPractisedToday`, `testPractisedYesterdayOnlySchedulesToday`, `testTimesThatHavePassedAreSkipped`, `testSwitchesOffScheduleNothing`, `testNoHistoryMeansNoStudyReminders`, `testWeakQuizLinkRoundTrips` (`verbtable://quiz/weak` ↔ `QuizLink.weakSpots`; `quiz/basic` unchanged; `quiz/nope` nil).
- [ ] **Step 2:** `make test-swift` → fails to compile (missing symbols).
- [ ] **Step 3:** implement.
- [ ] **Step 4:** `make test-swift` → all pass.
- [ ] **Step 5:** commit "VerbKit: study reminder plan and the weak-spots quiz link".

### Task 2: App — scheduling, settings and the link

**Files:**
- Modify: `App/ReminderScheduler.swift` — `refresh(verbs:attempts:)`: removes all three prefixes, then schedules Verb of the day (as now), then `StudyReminderPlan.items` with `weakCount` from `QuizProgress(attempts:).weakPairs(among:)` over visible verbs whose form exists in `QuizForm.all`; formats text with a new `StudyReminderText` (App) per the spec's wording; keys `reviewReminderEnabled`, `reviewReminderMinutes`, `streakReminderEnabled`, `streakReminderMinutes` in `.appGroup`.
- Modify: `App/RootView.swift` — `ReminderRefresh` adds the four settings and `quizHistory.attempts.count`; pass `attempts`; in `open(_:)`, a `QuizLink` with `weakSpots` builds `questions(for: .weakSpots, verbs:)` (visible verbs) and starts it with topic `.weakSpots`, or sets `topicSheetVerbs` when empty.
- Modify: `App/SettingsView.swift` — the section header becomes "Reminders"; three switches (`paperSwitch()`), each with its `DatePicker` when on; the existing permission flow shared by all three (one helper); footer per the spec, or the denied text.
- Modify: AGENTS.md (`StudyReminderPlan`, `QuizLink.weakSpots` rows) and the spec's status line.

- [ ] **Step 1:** implement; build iOS and macOS → no errors.
- [ ] **Step 2:** simulator: turn on Review and Streak keeper; with history giving weak spots and no answer today, set both times two minutes ahead and relaunch → the streak keeper arrives (review skipped that day); answer one question, set the review time ahead → nothing today (practised), tomorrow's pending (check `pendingNotificationRequests` via a debug log or by setting the clock); open `verbtable://quiz/weak` with `xcrun simctl openurl` → a Weak spots quiz starts; after Reset quiz history → no review/streak pending.
- [ ] **Step 3:** commit "Reminders: review and streak keeper".
