# JLPT Levels: Hide Levels in Settings — Design

**Date:** 2026-10-01
**Status:** Approved in brainstorming, pending written-spec review
**Builds on:** the grammar data (`GrammarPoint.level`), the verb and grammar lists, the
quiz topics and the widgets.

## Summary

Verbs and grammar lessons get a **JLPT level** (N5 to N1). A new **Levels** section in
Settings lets the user hide levels. Hidden levels disappear from the lists, the quiz and the
widgets. Because hiding can make a search look broken, search says when levels are hidden and
offers an **All levels** scope in the search bar that searches everything without changing the setting.

Decided in brainstorming: JLPT (not WaniKani) as the scale, and *hide* (not dim). WaniKani
levels are per kanji, the content is proprietary and would need an account token, so a
"hide verbs whose kanji I haven't learned" feature is a separate, later idea.

Out of scope: WaniKani, per-feature level settings, hiding in direct navigation (links),
levels N2 and N1 content (the model supports them, there is no data yet).

## 1. Data

- New `JLPTLevel` in VerbKit: `n5, n4, n3, n2, n1`, raw values `"N5"`…`"N1"`, `Comparable`
  (N5 easiest), `CaseIterable`, `Codable`, `Sendable`.
- `Verb.jlpt: JLPTLevel?` and `GrammarPoint.jlpt: JLPTLevel?`, JSON key `jlpt`. A missing value
  decodes to `nil`; `nil` means "no level" and is **always shown** (so a data update that
  lacks levels never hides content).
- `GrammarLevel` (beginner/intermediate) and its JSON key `level` are **replaced** by `jlpt`.
  The app is not released, so there is no older build to stay compatible with. Display text
  for the level badge becomes "N5"…"N1".
- Persistence: the SwiftData entities store `jlpt` (raw string, optional). Adding an optional
  attribute is a lightweight migration; existing rows read as nil until the next sync, and the
  per-build resync (`UserDefaultsSyncStateStore`) refreshes them on the first launch of the build.
- `data/verbs.json` and `data/grammar.json` get a `jlpt` value on every entry; the manifest is
  regenerated with `scripts/update_data.py`. Values are **curated and provisional** (the JLPT
  publishes no official lists): grammar `n-desu` N4, `potential` N4, `certainty` N3,
  `obligation` N3, `appearance` N3, `ppoi` N2, `teiru` N5, `teshimau` N4, `temiru` N4,
  `sugiru` N4; verbs N5 except しぬ, いそぐ, みせる, かえす N4. The owner reviews them in the PR.

## 2. The setting

- Key `hiddenJLPTLevels` in the App Group defaults (the app and the widgets read the same
  suite), stored as the *hidden* set, a comma-separated string of raw values. Default: nothing
  hidden. Storing the hidden set means a level added to the data later (for example N2) shows
  up automatically instead of being hidden by an older choice.
  `LevelSettings` in VerbKit reads and writes it and answers `isVisible(_ level: JLPTLevel?)`
  (`nil` is always visible), `hiddenCount`, and `summary` (see section 3).
- Settings > **Levels**: one toggle per level that exists in the data (verbs and grammar
  combined), so empty N2/N1 toggles do not appear. At least one level of verbs and of lessons
  must stay visible: a toggle is disabled when turning it off would leave a dataset with no
  visible level. A footer explains that hidden levels are left out of lists, the
  quiz and the widgets, and that search can still look at all levels.
- Changing the setting reloads widget timelines.

## 3. Where it applies

- **Verb and grammar lists:** only visible levels are listed. The verb list's filter subtitle
  (under the title) also names the level limit when any level is hidden, for example
  "って · Ru-verbs · N5–N4" (a contiguous run is written as a range, otherwise a comma list).
  The grammar list gets the same subtitle.
- **Quiz:** Random Quiz draws only from visible-level verbs. *Test this verb* still works on
  any verb you opened.
- **Widgets:** verb of the day, random verb and the grammar equivalents pick from visible
  levels only. *Pick a verb/lesson* is unaffected (an explicit choice). The picker in the widget
  edit screen lists all.
- **Not hidden:** direct navigation (`verbtable://` links, a lesson linked from a verb page,
  the selected item). Hiding only shapes browsing, quizzing and the widgets.

## 4. Search

When levels are hidden, search must make that obvious and make searching everything one tap.

- Both lists use SwiftUI search scopes: `.searchScopes($scope)` with two scopes, **My levels**
  (default) and **All levels**, shown under the search field while searching. The scope bar only
  appears when at least one level that exists in *that list's* data is hidden.
- **My levels** matches within visible levels. **All levels** matches everything. The scope is a
  per-search choice: it does not change the setting, and it resets to My levels when the search
  field is dismissed.
- When a search in My levels finds results but hidden levels also match, the list ends with an
  info row: "N more in hidden levels. Switch to All levels in the bar above."
- When My levels finds nothing but All levels would, the empty state says so ("No match in
  N5–N4", "3 in other levels. Switch to All levels in the bar above."); this replaces the plain
  "No results" message.
- The hints are information only. A button that set the scope in code left the native scope bar
  highlighting the old scope (SwiftUI does not push a programmatic change into the bar), so the
  scope is only ever changed by the user through the bar.
- Search with scope All levels shows the level badge on each row, so hidden-level items are
  recognisable.
- Verb rows get a small level badge (as grammar rows already have) so levels are visible
  everywhere they are used.

## 5. Structure and testing

- **VerbKit:** `JLPTLevel`, `LevelSettings`, level-aware filtering helpers
  (`visibleVerbs(_:levels:)`, `matchesLevel`), the data fields and persistence.
- **App:** `SettingsView` Levels section, `VerbListView` / `GrammarListView` scopes and subtitle,
  `VerbRow`/`GrammarRow` badge, quiz entry using visible verbs, `GrammarDisplay`.
- **Widgets:** pick from visible levels (read `LevelSettings` from the App Group defaults).
- **Swift tests:** decoding with and without `jlpt`; ordering and ranges in `LevelSettings.summary`;
  `isVisible(nil)`; the last level cannot be turned off; filtering helpers; the real-data files
  all carry a valid `jlpt`; counting hidden matches for the "N more" row.
- **Simulator:** Settings toggles (including the last-one rule), lists with levels hidden,
  the scope bar appearing only when something is hidden, All levels search, the "N more" info row
  and empty-state text, the subtitle, quiz and widget picking from visible levels.

## Risks

| Risk | Covered by |
|---|---|
| Hiding makes search look broken | The scope bar, the "N more" info row and the empty-state text |
| Curated levels are wrong | They are provisional and reviewed in the data PR |
| A data update without `jlpt` hides content | `nil` is always visible |
| All levels turned off | The last toggle is disabled |
| Widget picks shift when the setting changes | Documented; the day pick indexes into the visible list |
| Persistence migration | Optional attribute (lightweight) plus the per-build resync, which needs a build-number bump (done: build 2) |

## Files this touches

- **New:** `JLPTLevel.swift`, `LevelSettings.swift` (VerbKit), tests.
- **Edited:** `Verb.swift`, `GrammarPoint.swift`, the SwiftData entities and persisting,
  `data/verbs.json`, `data/grammar.json`, `data/manifest.json`, `SettingsView.swift`,
  `VerbListView.swift`, `GrammarListView.swift`, `VerbRow.swift`, `GrammarDisplay.swift`,
  `RootView.swift`, the widget providers and `GrammarWidgetViews.swift`.
