# Home Screen Widgets and Romaji Search — Design

**Date:** 2026-10-01
**Status:** Approved in brainstorming, pending written-spec review
**Builds on:** the [native rewrite spec](2026-09-23-native-apple-rewrite-design.md). The
App Group store (`VerbModelContainer.make()`) was built so a widget could read it.

## Summary

Two independent pieces, one spec:

- A **Home Screen / Lock Screen widget** that shows a verb, configurable per widget.
- **Romaji search**: typing `taberu` or `tabemashita` finds 食べる, in the verb list
  and the grammar list.

Out of scope: audio, favourites as an app feature, an interactive or quiz widget, a
Control Center control, Spotlight or Siri indexing, any data or script change.

## 1. Widget

### What the user gets

One widget, **Verb Table**, with an edit screen (App Intents) offering:

- **Mode:** *Verb of the day* (default), *Random verb*, or *Pick a verb*.
- **Verb:** shown only for *Pick a verb*, a searchable list of all verbs.

Which verb shows:

- **Verb of the day:** index = days since a fixed epoch, modulo the verb count, over the
  stored verb order. Every widget and device shows the same verb; it changes at midnight.
- **Random verb:** a new random verb every 3 hours.
- **Pick a verb:** the chosen one, never changing. If it no longer exists after a data
  update, the widget falls back to the verb of the day.

Sizes:

- **Small:** kanji (or dictionary form), reading, meaning, the polite form.
- **Medium:** the same, plus a grid of て-form, past, negative and potential.
- **Lock Screen:** rectangular (dictionary form, meaning, polite form) and inline
  (dictionary form and meaning).

Styling follows the app (type, colours, glass where the system provides it). Tapping
opens that verb in the app. With an empty store (first launch, data not yet
downloaded) the widget shows "Open Verb Table to load verbs".

### Structure

- **New target** `VerbTableWidgets` (app extension) in `project.yml`, iOS and macOS,
  embedded in the app, with the same App Group entitlement and the VerbKit dependency.
- **`VerbKit/Widget/VerbOfTheDay.swift`** (testable, no WidgetKit): pure functions
  `verbOfTheDay(verbs:on:calendar:)` and `randomVerb(verbs:using:)`.
- **Widget code** reads verbs through `SwiftDataVerbPersisting` on the shared container,
  builds a timeline (midnight for day, 3 hours for random, none for pick), and renders
  the views.
- **Deep link:** URL scheme `verbtable` (added to the app's Info.plist through
  `project.yml`); `verbtable://verb/<id>` with the id percent-encoded. A VerbKit
  `Route(url:)` parses it and the app's `onOpenURL` feeds the existing navigation, the
  way an in-app verb route does.
- The widget never writes the store and does not sync; the app remains the only writer.
  After the app syncs, `WidgetCenter.shared.reloadAllTimelines()` refreshes widgets.

### Testing

- **Swift (VerbKit):** verb of the day is stable within a day, changes the next day,
  wraps at the end of the list, and handles an empty list; `Route(url:)` parses valid
  links and rejects others (wrong scheme, unknown host, missing id, encoded ids).
- **Simulator:** add each size; edit-screen mode switching; Pick a verb; tap-through to
  the verb; empty-store placeholder; a build for macOS.

## 2. Romaji search

### What the user gets

In the verb list (and grammar list) the query is also tried as romaji:

- `taberu` finds 食べる; `tabemashita` finds it through the polite past form; `te` style
  and every kana form that search covers today are searchable.
- Spellings accepted: Hepburn and Nihon-shiki (`shi`/`si`, `tsu`/`tu`, `chi`/`ti`,
  `fu`/`hu`, `ja`/`zya`), long vowels (`ou`, `oo`, `ō`), doubled consonants (`kka` →
  っか), `n`, `nn` and `n'` for ん, and small kana (`xtu`, `ltu`, `ya` after a consonant).
- Input is case-insensitive; surrounding space is trimmed.
- As-you-type: a half-typed ending (`tab`) converts up to the last complete kana (`た`) and
  drops the leftover letters, so results narrow as you type rather than vanish.
- The English meaning match keeps running on the raw text (`eat` still works). A query
  matches if any of: raw match (today's behaviour), or the converted kana matches.
- A query with no Latin letters is untouched.

### Structure

- **`VerbKit/Search/Romaji.swift`**: `Romaji.toHiragana(_ text: String) -> String?`
  (nil when the text has no Latin letters). Table-driven longest-match, with the
  sokuon, ん and long-vowel rules above.
- **`matchesSearch`** and **`matchesGrammarSearch`** add the romaji fallback. No change
  to the call sites.
- Katakana in the query is not converted (out of scope; verbs are hiragana).

### Testing

- **Swift:** each spelling variant, the `n` rules (`kan`, `kanji`, `kanna`, `n'a`),
  sokuon, long vowels, partial input, mixed kana and Latin input, empty and
  non-Latin input; `matchesSearch` for `taberu`, `tabemashita`, `eat` and a
  no-match; a real-data pass: every one of the 25 verbs is found by the romaji of its
  dictionary form and of its polite form.

## Rollout and risks

App plus a new extension target; no data, script or model-schema change. A build
number bump is only needed when the user releases.

| Risk | Covered by |
|---|---|
| Widget cannot read the store (entitlement or container mismatch) | Simulator check of all sizes with real data |
| Verb of the day differs between widget and elsewhere | One shared pure function, tested |
| Romaji search surprises (`n` before vowels, `ou` vs `oo`) | Dedicated converter tests |
| Romaji adds false matches in the grammar list | The fallback only applies when the query has Latin letters and the kana form matches Japanese text |
| The widget extension breaks the macOS build | macOS build check before merging |

## Files this touches

- **New:** `Packages/VerbKit/.../Search/Romaji.swift`, `.../Widget/VerbOfTheDay.swift`,
  `.../Navigation/Route+URL.swift`, `Widgets/` (the extension: bundle, widget, intent,
  views, entitlements, assets), and tests.
- **Edited:** `VerbSearch.swift`, `GrammarSearch.swift`, `project.yml`,
  `App/JPVerbConjugationApp.swift` or `RootView.swift` (`onOpenURL`, timeline reload
  after sync).
