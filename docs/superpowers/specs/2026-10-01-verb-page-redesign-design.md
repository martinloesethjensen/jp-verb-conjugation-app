# Verb Page Redesign — Design

**Date:** 2026-10-01
**Status:** Approved in brainstorming, pending written-spec review
**Builds on:** the [native rewrite spec](2026-09-23-native-apple-rewrite-design.md)
(section 10, the visual design direction),
[2026-09-29-grammar-foundation-nd-desu-design.md](2026-09-29-grammar-foundation-nd-desu-design.md),
[2026-09-30-potential-form-design.md](2026-09-30-potential-form-design.md),
[2026-10-01-nuance-endings-design.md](2026-10-01-nuance-endings-design.md) and
[2026-10-01-verb-auxiliaries-design.md](2026-10-01-verb-auxiliaries-design.md),
whose sections this reorganises. This is a UX redesign, not part of the grammar
roadmap.

## Summary

Each grammar sub-project added another collapsible section to the verb page, and the
expanded groups use glass tiles that look muddy on the page background. The verb
page is rebuilt around a short main page and sub-pages:

- **Main page:** the header, then one **Forms** card (a Plain / Polite table) and one
  **More** card of rows (Potential, んです, Auxiliaries, Grammar).
- **Sub-pages:** each extended group is its own pushed page, drawn with the same table.
- **Look:** quiet system-secondary cards instead of glass tiles, and the part of each
  form that changed is **bold, with the shared stem in grey**.
- **No data change, no new content.**

Decided with mockups: layout option **C** (short page with sub-pages), sub-page style
**the Plain / Polite table**, highlight style **weight and tone**.

## 1. Structure and navigation

### The main page

From the top: the header and action buttons, the notes callout and the description, as
today. Then two cards:

- **Forms card.** One table with **Plain** and **Polite** columns and rows present +,
  present −, past +, past −, and て-form (a single value, in the Plain column). It
  replaces the Polite, Plain and て-form collapsibles. Always open, with no
  disclosure arrows.
- **More card.** One row for each of **Potential**, **んです**, **Auxiliaries** and
  **Grammar**, with a preview form on the right (たべられる, たべるんです, たべている,
  "10 lessons") and a chevron.

A row is hidden when the verb has no such forms, so ある has no Potential row and its
Auxiliaries page shows only the stem rows and ながら. The Grammar row hides until
grammar has synced.

### Sub-pages

Tapping a row pushes a page titled with the group; each page is a `FormTable` plus its
links:

- **Potential:** the nine forms as a table (the て-form row has only a Plain value),
  then **Learn about 可能形**.
- **んです:** the same table with **Polite** and **Casual** columns, then its lesson link.
- **Auxiliaries:** the ている table, then a second table with a row per auxiliary
  (てしまう, ておく, てみる, ながら, すぎる, やすい, にくい; ながら has no Polite value),
  then the four lesson links.
- **Grammar:** a plain list of the lessons that attach to verbs (as today's Grammar
  section), one row each, opening the lesson through `openRoute`.

Each lesson link stays hidden until that lesson has synced. The links still call
`openRoute`, which switches to the Grammar tab, unchanged.

### Navigation mechanics

The Verbs tab is a `NavigationSplitView`; on iPad and macOS the detail column does not
push `NavigationLink`s by itself. The verb detail therefore gets its own
`NavigationStack` with a `navigationDestination(for: VerbSubPage.self)`.
`VerbSubPage` is a small enum (`potential`, `nDesu`, `auxiliaries`, `lessons`). The
stack is keyed on the verb's id, so choosing another verb returns to the main page. On
iPhone it is one more level of the stack.

## 2. The visual system and the highlight

### Surfaces

The glass tiles go. Groups become plain cards using the system's secondary background
(`.background.secondary`), which adapts to light and dark on iOS and macOS. Glass stays
where it earns it: the Examples / Test / Jisho buttons and the **Learn about …** link
buttons (`.glass` styles), the type pill, the notes callout, and the system's own
navigation and tab bars. Visual direction as before: `.glassEffect` for custom
surfaces that are not plain cards, no accessibility-specific modifiers.

### One table component

`FormTable` draws every group: a small bold caption row for the column headers
(Plain, Polite — or Polite, Casual), then a row per form with a secondary caption on
the left, the value cells on the right, and hairline separators. Rows that would be
tight (the longest 9-kana auxiliary forms) shrink slightly (`minimumScaleFactor`)
rather than wrap.

### The highlight (weight and tone)

In every value cell, the part shared with the dictionary form is the **stem**: regular
weight, secondary grey. What changed is the **ending**: bold, primary.

- たべる → たべ**られる**, たべ**ます**, たべ**ている**
- のむ → の**める**, の**みます**, の**んでいる**
- No shared prefix (くる → き**ます**, する → **できる**): the whole form is bold.
- Identical to the dictionary form (the Plain present): normal, no emphasis.

No colour and no underline, so nothing reads as a link (the ru-verb accent is blue),
and it works the same in dark mode.

`FormSplit.split(_ form: String, from dict: String) -> (stem: String, ending: String)`
in VerbKit returns the longest common prefix with the kana dictionary form and the
rest. It is pure and unit-tested. `FormCell` renders it as one `Text` from two styled
pieces (`Text + Text`), so it wraps and scales like ordinary text. It applies only to
form cells in the tables; headers, captions, previews and lesson text are unchanged.

## 3. Implementation, testing and rollout

### New pieces

- **VerbKit:** `FormSplit`.
- **App:** `FormTable`, `FormCell`, `VerbFormsCard`, `MoreRowsCard`, `VerbSubPage`,
  and the pages `PotentialPage`, `NdesuPage`, `AuxiliariesPage`, `VerbLessonsPage`.
- **Retired** once their content has moved: `FormGroupSection`, `PotentialFormsSection`,
  `NdesuFormsSection`, `AuxiliaryFormsSection`, `VerbGrammarSection`. `formLabels`
  shrinks to the short row labels. `VerbDetailView` is rewritten around the two cards.
- **Not touched:** the quiz, the Examples sheet, the lessons, the data and the scripts.

### Behaviour that must survive

- Potential, んです and Auxiliaries rows hide when the verb has none of those forms.
- Each lesson link hides until its lesson has synced; the Grammar row hides until
  grammar has synced.
- Lesson links land on the lesson from a cold start (the Grammar tab need not have
  been opened).

### Testing

- **Swift:** `FormSplit` against hand-written cases (たべる, のむ, かう, いく, する,
  くる, ある, an identical form, an empty ending) and a real-data test over all 25
  verbs checking that stem plus ending always rebuild the form.
- **Simulator:** the main page and each sub-page on iPhone, iPad and macOS, in light and
  dark; pushing a sub-page and going back; choosing another verb while on a sub-page;
  ある, する and たべる; the longest forms (いそいでしまいます) not wrapping; a lesson
  link landing on the lesson from a cold start.

### Rollout

App-only: nothing is published to the data repository, so a push changes the app
build and not what older builds see.

### Risks

| Risk | Covered by |
|---|---|
| Pushing inside the split view's detail column behaves differently on iPad and macOS | The detail `NavigationStack`, plus iPad and macOS checks |
| Long forms wrap in a two-column table | `minimumScaleFactor` and a check on the longest forms |
| The grey stem is too faint in dark mode | The system `.secondary`, checked on screen |
| Replacing five views at once is a large diff | One group per task, so the page works after each |

## Files this touches

- **New:** the VerbKit and app pieces above, and tests.
- **Edited, patch-style on top of the latest `main`:** `VerbDetailView.swift`,
  `FormLabels.swift`, `RootView.swift` only if the detail's stack needs wiring there.
- **Deleted:** the five retired section views.

## Not in this redesign

- Long-press actions on forms and examples (copy, open in Jisho) and sending examples
  to translation apps (DeepL, Google Translate, Apple Translate). Both are saved as
  follow-ups; each form and example stays its own view so they are cheap to add.
- Highlighting on the Examples sheet, the lessons or the quiz.
- Any data or script change.
