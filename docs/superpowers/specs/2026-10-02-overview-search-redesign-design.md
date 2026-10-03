# Overview screen: search, filters and toolbar redesign

## Problem

The Verbs overview spends its first screen on chrome. The top bar holds four
unlabelled icons (Guide, Progress, Random Quiz, ⋯) plus a separate search
circle. Two stacked filter rows (te-form chips and a Type segmented control in
its own card) push the first verb down. The collapsed search button is easy to
miss and sits far from the filters it works with.

The user picked these pains: too many top-bar icons, two filter rows, hidden
search. The Verbs / Grammar tab bar is not changed.

## Design

### Top bar (Verbs)

Two items:

- **Quiz** (the current Random Quiz): the one primary action, shown with a
  label.
- **⋯ menu**: Progress, Guide, Settings, Report a problem, in that order.

The separate search circle and `.searchToolbarBehavior(.minimize)` go away.

### Search

- A normal inline search field under the large title at the top of the list.
  Pulling the list down reveals it, as in standard iOS.
- Once the field has scrolled off screen, a magnifier button appears in the
  bar. Tapping it scrolls to the top and focuses the field.
- The level scope bar is unchanged (shown only while searching with hidden
  levels).
- Prompt shortens to "Search verbs…" (the current prompt lists every input
  type and truncates).

### Filters: one chip row

The row scrolls with the list and replaces both current filter rows:

1. **Type ▾** menu chip (All, Irregular, Ru-verbs, U-verbs). When a type is
   chosen, the chip shows its value ("Ru-verbs ▾") and is highlighted.
2. **All** and the te-form chips (って, んで, いて, いで, して), unchanged in
   behaviour.

The segmented-control section is removed. The navigation subtitle
(`filterSummary`), back-to-top button, empty states and "Clear filters" keep
their current behaviour (Clear still resets both filters).

### Grammar list

Same bar treatment and inline search, no filter chips (it has no filters).
Its ⋯ menu holds Settings and Report a problem, so Settings is reachable from
the Grammar tab too. Placeholder stays "Search grammar…".

## Components

- `App/VerbListView.swift`: toolbar, search, section structure, scroll
  tracking for the magnifier, focus handling.
- `App/GrammarListView.swift`: toolbar menu.
- `App/TypeFilterChip.swift` (new): the Type menu chip.
- `App/TeFormFilter.swift`: hosts the Type chip first in the row; chip styling
  shared with the new chip.

No changes to VerbKit, data, widgets, or filtering/search logic.

## Platforms

iOS is the target for this work. macOS must compile; iOS-only modifiers stay
behind `#if os(iOS)`. On macOS the toolbar keeps its current behaviour where
the iOS layout does not apply. iPad and macOS on-screen checks stay parked.

## Testing

- Logic is unchanged, so the package suite must stay green (369 tests).
- Builds: iOS and macOS schemes (`CODE_SIGNING_ALLOWED=NO` for macOS).
- On-screen on iPhone simulator: bar shows Quiz and ⋯ only; menu items open
  the right sheets; Type chip selects, highlights and clears; te-form chip and
  Type combine; magnifier appears after scrolling and focuses search; scope
  bar still works with hidden levels; empty states; Grammar bar and Settings
  access; widget deep links still dismiss sheets.

## Out of scope

Changing the tab bar, bottom search dock, new filters, iPad/macOS layout work.
