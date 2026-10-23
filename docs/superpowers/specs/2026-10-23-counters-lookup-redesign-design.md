# Counters: lookup-first redesign

Status: drafted in chat 2026-10-23, pending the owner's review. Revises the screens in
`2026-10-17-counters-design.md` (milestones 1 to 3); the reading data and quiz are unchanged.

## Problem

Walked on an iPhone 17 simulator with the real data, the Counters tab is thorough but slow to use:

- The home is 15 tall tiles over two screens. A learner who wants 本 has to guess whether it lives
  under "Long things" or "Drinks". Search, the tab's main entry point (3本, sanbon, umbrella), only
  appears after pulling the list down.
- Eight groups hold a single counter, so their "table" is one column that repeats the counter page.
- Some tiles say nothing ("日 · 日", "ろっ · いっ", "18 counters").
- A group table row is about 72 pt, so 11 rows take three screens.
- A counter page (本) runs about five screens and shows the readings twice: once in Count them and
  again in an 11-cell Readings grid. The pitfall sits near the bottom, and Practise is last.

## Goal

Someone who knows a word and needs its counter, or knows the counter and needs one number, gets
there in one or two taps and sees the answer without scrolling.

Success looks like:

- Search is visible the moment the tab opens.
- All counters are visible in about two screens, grouped by what they count.
- A counter's reading for any number is on screen with no scrolling.

## Non-goals

- New counters, months, durations, numbers above 10 (issue 124 and the out-of-scope list in the
  original spec). The layout must work with 18 counters and with roughly 40.
- Changes to readings, the quiz, the widget, or the sound classes.
- Changing the search results' content (Groups, Counters, Forms, Things). Only where they sit.
- iPad and macOS verification (parked), and Android and watchOS.

## Anti-goals

- Hiding information to look tidy: the pitfall and the "irregular" signal must stay more visible
  than today, not less.
- Making the app derive readings. It still only reads `counters.json`.
- Breaking old app builds: a new data key must be optional, and an unchanged cache must still work.

## Design

### Home: a directory

- **Search is a fixed field at the top** of the Counters sidebar, always visible, same placeholder
  and the same `CounterSearch` behaviour. Typing replaces the list with the existing four result
  sections; clearing restores it. The level scope bar behaves as now.
- **Below it, one compact list of every visible counter**, grouped in sections by what they count.
  Row: the counter (large kanji), its reading, what it counts, a chevron. Irregular counters add
  "irregular" in the meaning line. Row height is about 50 pt. Tapping a row opens the counter page.
- **Each section header has "Compare ›"**, which opens the table for that section's counters (see
  below). A section with a single counter has no Compare link.
- **Sections** (the owner chose these five on 2026-10-23, replacing the 13 grid tiles; 本 and つ appear
  in two sections, as they do in groups today; the two 日 rows are labelled "day of the month" and
  "number of days"):
  - Drinks: 杯, 本, つ
  - People & animals: 人, 匹
  - Things: 枚, 台, 冊, 個, 本, つ
  - Time, dates & age: 時, 分, 日 (date), 日 (days), 年, 歳
  - Money & counting events: 円, 回, 階

  Membership and order are as above; the builder only settles the exact wording of row meanings.
- **Sound patterns** is a plain last row, "Why do counters change sound?", opening the existing
  screen. The tile and its cryptic subtitle go. "All counters" goes (the list is the full list).
- Counters hidden by the level settings stay left out, and a section with none left is hidden.
- The toolbar keeps Quiz and the More menu.

### Compare table

The existing `GroupTableView`, fed by a section. Changes:

- **Rows about 40 pt instead of 72**, so 1 to 10 and 何 fit on one screen on an iPhone without the
  tab bar covering the last row. The reading stays large enough to read; the written form
  (一杯) moves from above the reading to a smaller trailing or inline position (builder's call).
- **Irregular counters get a visible signal in the column header** ("irregular") as well as the
  footnote, because their cells carry no orange marks.
- Tapping a header still opens the counter. Tap to speak, long-press to copy, and the Speak menu are
  unchanged. Up to three columns fill the width; more scroll sideways with the number column pinned
  (as built).

### Counter page

Replaces Count them plus the Readings grid with one block, and moves the rest behind a control.

1. **Header:** counter, reading, speaker, level, meaning, and the sections it belongs to as small
   links. The decorative symbol goes.
2. **Pitfall hint:** the counter's first pitfall heading and a line of its explanation, with "More"
   expanding the full pitfalls (all of them, with their examples). Counters with no pitfall show
   nothing here.
3. **Reading block:** the large reading for the selected number, the written form small above it,
   tinted with the dot when the number changes sound, spoken on tap. As built: tapping the reading
   speaks it; the thing picker and its symbol repeat are dropped from this block (the picker moves
   to Things).
4. **Number strip:** 1 to 10 and 何 in one row. Tap selects. Changed numbers are tinted and dotted
   as now, so the strip itself shows the pattern. A caption says what the tint means
   ("Orange changes sound"). Selected number is ringed; `focus` from a Forms search result selects
   it. The strip must fit one row at the default text size and wrap or scroll at accessibility
   sizes.
5. **Irregular counters** (人, つ, 時, both 日) show a grid of the 11 readings in place of the strip,
   because every cell differs and a tint says nothing. Tapping a cell selects it into the reading
   block above.
6. **Segmented control:** Examples (default), Things, Related. Things keeps the chips and the
   "also counted by" behaviour; the Count them thing picker (swapping the symbol) lives here or is
   dropped, builder's call, as the strip makes it less useful.
7. **Practise this counter** stays as a button below the segmented content, always reachable without
   scrolling past long sections.

Target: about one and a half screens for 本, down from five.

### Sound patterns

Replaces the six class cards ("K sounds", "H sounds (b/p)") with a table a learner can read by the
counter's first sound. Mocked up in the 2026-10-23 session ("by number and first sound").

- **Table:** rows 1, 3, 6, 8 and 10 (the numbers that ever change); columns か行 (個 回 階), さ行 (冊 歳),
  は行 (本 杯 匹 分) and "other" (枚 台 年 円). Each cell is one real reading from a sample counter of that
  column, with the same tint and dot as elsewhere when that counter's `changed` includes the number.
  Columns come from the counter's `sound` class (`k`, `s`, `h-b` and `h-p`, `plain`), a closed set the
  screen already depends on. The sample counter per column is a fixed choice (個, 冊, 本, 枚) falling
  back to the first counter of that class if the sample is hidden by the level settings.
- **Selecting a number row** shows one sentence under the table and the affected counters as chips
  that open their pages ("6 → ろっ before か行 and は行 …. Before さ行 it stays ろく"). Tapping a column
  header lists that column's counters. The sentence is built from the data the way today's caption is
  (which columns change at that number, and the shared stem such as ろっ); the app does not
  invent a reading.
- **3 and 4** are not squash cases (さんぼん is voicing, よんぷん is its own change), so their
  sentences say that instead of reusing the squash wording. If wording the app cannot build from the
  data is needed, it becomes an optional authored field in `counters.json`, and the owner re-signs.
- **Exceptions box:** what each counter changes beyond its class, as the current "Exceptions" line
  (年 and 円 at 4, 階 at 3, 分 at 3 and 4), plus "人, つ, 時, 日: learn each reading" for irregular counters.
- Opened from the last home-list row, "Why counters change sound". Default selection is 6.
- Not a route; same as today.

### Data

The home sections are authored data, not app logic, so the app does not guess that 杯 and 本 belong
together.

- `counters.json` gains an optional top-level `sections` array next to `groups`:
  `{ "id", "title", "counters": ["hai", "hon", "tsu"] }` in display order. The existing `groups`
  stay as they are, because the quiz uses them for distractors and the counter page and search
  results use them today.
- `update_data.py` validates: section ids unique, counters resolve, every counter is in at least
  one section.
- The app falls back to `groups` (one section each) when `sections` is absent, so an old cache and
  tests without the key keep working. Old app builds ignore the key.
- This is a `data/` change: the owner re-signs `manifest.json` before merge.

## Constraints

- Accessibility: VoiceOver labels as now ("sound changes" on tinted cells); Dynamic Type through the
  accessibility sizes; Reduce Motion respected. These are unchecked today and should be checked as
  part of this work, not later.
- Routes keep working: `verbtable://counter/<id>` and `verbtable://counters/<id>` (a group id) still
  resolve. Group routes land on the section table when one contains those counters, otherwise on
  the existing group table (builder's call; do not break the URLs).
- Widget deep links into `verbtable://counter/<id>` are unchanged.
- Reuse the existing components (`ReadingCell`, `ReadingsGrid`, `CountThemCard`, `ThingChips`,
  `GroupTableView`) where they fit; follow the app's existing glass-style conventions.

## Answers a builder will need

From the project as it stands:

- **Duplicates are fine.** A counter id may appear in several sections (本, つ), as it does in `groups`
  today. 日 is two counters, `nichi-date` and `nichi-days`. Home rows are identified by section id plus
  counter id. The validator requires every counter to be in at least one section and
  rejects a counter listed twice in the same section.
- **"Irregular" is `Counter.sound == "irregular"`,** which the app already reads
  (`GroupTableView`, `ReadingsGrid`). No new field.
- **Examples, Things (the "What it counts" chips) and Related all exist today.** The segmented control
  only moves them; no new content.
- **Pitfalls are `heading` plus `explanation` plus examples.** The hint is the first pitfall's heading
  and the first sentence of its explanation, cut in the app. No new field.

My calls (the owner can change any of them):

- **`groups` stay for everything they do today:** quiz distractors, the Groups section of search
  results, and `verbtable://counters/<id>` routes. A group result in search opens the existing group
  table. Only the home list, its Compare link, and the counter header's "belongs to" links use
  `sections`.
- **Titles are English, like the rest of the Counters data.**
- **Row identity, state restoration:** the Counters destination is in-memory state, so nothing
  persisted needs migrating. Deep links are unchanged.
- **Compare layout:** 1 to 10 and 何 fit one iPhone screen at the default text size. At accessibility
  sizes the table scrolls, with `@ScaledMetric` rows as built.
- **Delivery in two stages:** the `sections` data and the home list first (the data PR needs the
  owner's signature, so it goes first and small), then the Compare table and the counter page.

## Left to the builder

- Exact section membership and order (within the five above), and the final copy of headers.
- Row and cell sizes, as long as 1 to 10 and 何 fit one iPhone screen and tap targets stay at least
  44 pt.
- Whether the thing picker survives and where.
- iPad and macOS: keep what the split view does today; do not redesign for them here.
- Tests: update the existing view-model and search tests; add decoding tests for `sections` and the
  fallback.

## Testing

- **Python:** `sections` validation (unknown counter id, a counter in no section, duplicate ids);
  `--check` still passes.
- **VerbKit:** decoding with and without `sections`; fallback from `groups`; level-settings
  visibility drops empty sections.
- **App, in the simulator:** home at default and largest text, search over the list and back, Compare
  on a three-column and a six-column section, 本 (changed pattern) and 人 (irregular) pages, Forms
  search landing on a number, a pitfall More expansion, VoiceOver spot-check.
- Compare screenshots with the 2026-10-23 baseline recorded in this session's critique.

## As built

What changed from the design while building it, and what has not been checked. The plan is
`docs/superpowers/plans/2026-10-23-counters-lookup-redesign.md`.

- **Sections are in the data, not yet published.** `data/counters.json` has the five sections and
  `manifest.json` changed, but the manifest is not re-signed: the owner runs `make sign-commit` before the
  data merges. Until it is published, the app falls back to one section per group (13 headings), which is
  how the published data looks on a device today.
- **Compare table rows are 44 pt.** The written form (三本) was dropped from compact table cells instead of
  moved inline: the row and column headers already say it, the accessibility label keeps it, and
  alternate readings (はちほん) still fit on a second line. 1 to 10 fit one screen; the 何 row sits partly
  under the tab bar until scrolled.
- **The number strip cells are about 33 pt wide and 44 pt tall** at the default text size (eleven cells in
  one row, as specified). At accessibility sizes it scrolls with 56 pt cells.
- **The thing picker and the objects row went with Count them.** The Things segment keeps the chips.
- **The counter page's section links** show only sections with more than one counter.
- **Sound patterns sentences come from the data only** ("3 changes in は行"). A richer explanation of the
  voicing at 3 would need an authored field, so it is not built.
- **`GroupTableView` takes a group or a section.** Group routes and search results still open the group
  table; section Compare links open the same view with no summary line.

Checked on the iPhone simulator (a temporary, uncommitted seed injected the five sections): the home list,
Compare on a three-column and a six-column section, the largest text size on Compare and Sound patterns,
the 本 page (hint with More and Less, strip, segments) and the 人 grid, the Sound patterns table with
selecting a number and a column. Checked on the shipped data (no sections): the fallback home, search for
"umbrella", `verbtable://counter/hon` and `verbtable://counters/drinks`.

Not checked: hiding N5 in Settings, VoiceOver, Reduce Motion, a Forms search landing on its number,
Practise, a counter with no pitfalls, the largest text size on the counter page, iPad and macOS.
