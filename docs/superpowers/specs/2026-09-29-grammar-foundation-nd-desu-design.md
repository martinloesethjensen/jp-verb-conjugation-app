# Grammar Foundation + んです / なんです — Design

**Date:** 2026-09-29
**Status:** Implemented on branch `feature/grammar-nd-desu`, based on `main` at
`3b56c92`; refined while planning and while reconciling with newer `main`
(see "Refinements found along the way" at the end)
**Builds on:** [2026-09-23-native-apple-rewrite-design.md](2026-09-23-native-apple-rewrite-design.md)

## Summary

Add a **Grammar** content type to the app, alongside verbs, and use
んです / なんです as its first lesson. The work has two halves:

- A **Grammar section**: a list of grammar points, each with a detail page
  covering usages, how the ending attaches to each word class, its own
  conjugations, and examples.
- **Per-verb んです forms**: eight new optional fields on `VerbForms`, stored
  in `verbs.json`, shown in a new section on the verb detail screen and
  linked to the lesson.

## Decomposition

The original request (んです/なんです, potential-form deep-dive, nuance
endings, verb auxiliaries) is too large for one spec. It is split into four
sub-projects, each with its own spec → plan → implementation cycle (a fifth,
furigana, was added later):

1. **Grammar foundation + んです/なんです** — this document. Everything else
   reuses its model, sync path and screens.
2. **Potential form deep-dive** — content, plus the potential form's own
   conjugation matrix (explicitly out of scope in the rewrite spec). Specified
   in [2026-09-30-potential-form-design.md](2026-09-30-potential-form-design.md).
3. **Nuance endings** — わけ, はず, べき, ものだ, かもしれない (Yokubi
   groups these), and よう/みたい, そう, らしい, ぽい (also grouped there).
4. **Verb auxiliaries** — ている/てある first, then てしまう/ておく, then
   てみる, ながら, すぎる, やすい/にくい.
5. **Furigana** — added after sub-project 2's brainstorm. An on-by-default
   Settings toggle that shows readings above kanji on every screen that shows
   Japanese. Cross-cutting (it needs a way to store and draw readings), so it
   gets its own spec; it runs after sub-project 2 so a single pass can annotate
   all the lesson text and verb examples.

Sub-projects 2–4 are mostly content authoring once this one lands.

Ideas beyond んです/なんです come from the author's grammar knowledge,
cross-checked against the structure of the Yokubi grammar guide
([Morgawr/yokubi](https://github.com/Morgawr/yokubi), CC-BY-4.0): its table
of contents and its lesson on explanatory のだ/んです (Lesson 20) informed the
usage list and the sub-project grouping above. Lesson prose and examples in
this project are written independently and are not copied from Yokubi. If
any Yokubi wording or examples are ever adapted, CC-BY-4.0 attribution must
be added to the app's credits.

## 1. Data model

`GrammarPoint` is a new `Codable`, `Sendable` model in `VerbKit/Models`:

- `id` — slug, e.g. `n-desu`
- `title` — e.g. `んです`
- `summary` — one line
- `level` — beginner / intermediate
- `usages: [GrammarUsage]` — each has a `heading`, an `explanation`, and
  `examples: [GrammarExample]` (`jp`, `en`)
- `attachment: [AttachmentRule]` — one per word class and, where the rule
  differs, per condition: `wordClass`, optional `condition` (e.g.
  "non-past, affirmative"), `pattern`, a worked `example`, optional `note`
- `conjugations: [GrammarConjugation]` — the ending's own forms, each with
  `form`, `register` (polite / casual / formal), optional `note`
- `pitfalls: [GrammarPitfall]` — common mistakes and nuances ("Watch out"):
  `heading`, `explanation`, and `examples` (which may be omitted)
- `related: [String]` — ids of other grammar points

`WordClass` is a new small enum (verb, i-adjective, na-adjective, noun). It is
kept separate from `VerbType`, which classifies verbs only.

`VerbForms` gains eight **optional** fields, following how the advanced forms
were added. All attach to the verb's plain forms:

| Field | Example (食べる) |
|---|---|
| `nd_pos` | 食べるんです |
| `nd_neg` | 食べないんです |
| `nd_past` | 食べたんです |
| `nd_past_neg` | 食べなかったんです |
| `nd_casual_pos` | 食べるんだ |
| `nd_casual_neg` | 食べないんだ |
| `nd_casual_past` | 食べたんだ |
| `nd_casual_past_neg` | 食べなかったんだ |

The んじゃない / んじゃありません variants live in the grammar point's
conjugation matrix, not per verb.

**Decision recorded:** these forms are *stored* in `verbs.json` rather than
computed on-device from the plain forms. Computing them would avoid a schema
change (they are fully derivable), but stored fields allow hand-tuning odd
cases and keep verb data self-describing. The cost is ~8 more fields and
reliance on the generation step in section 2 to keep them consistent.

The new fields do not get `FormKey` cases in this project, so they do not
appear in quiz questions.

## 2. Sync, persistence and pipeline

**Manifest (backward compatible).** `manifest.json` keeps top-level
`version` and `sha256` for `verbs.json` and adds an optional
`grammar: {version, sha256}` block for `grammar.json`. Already-installed
builds ignore the unknown key; a missing `grammar` block means nothing to
sync.

**Two independent sync legs.**

- `VerbDataFetching` gains `fetchGrammarData()`.
- A new `GrammarSyncService` mirrors `VerbSyncService`: compare the manifest
  entry to the last synced one, fetch only on change, verify the SHA-256,
  decode, then save. It is deliberately a second concrete service, not a
  generic `ContentSyncService<T>`; revisit if sub-projects 2–4 add a third
  file.
- Sync state stores a separate last-synced manifest per file.

**Sync contract.** Like `VerbSyncService`, `GrammarSyncService.sync()` records
nothing as synced. The caller persists the points and only then calls
`confirmSynced(_:)`. If sync recorded state itself, a persistence failure would
look like "nothing changed" on the next attempt and the lessons would never be
fetched again.

**Failure isolation.** Verbs remain the first-launch gate. Grammar is
non-blocking: `VerbStore` syncs verbs first, then grammar in the background.
A grammar failure never affects verbs; the Grammar tab shows a "not
downloaded yet" state and retries on the next sync. Errors reuse
`VerbSyncError`'s existing cases.

**Persistence.** New `GrammarPersisting` protocol
(`loadAllGrammarPoints`, `replaceAllGrammarPoints`) with a SwiftData
`GrammarEntity`. Like `VerbEntity`, it stores the point as a `Codable` blob,
is replace-synced (removed lessons disappear locally), and shares the same
`ModelContainer` and App Group. It also stores each point's position in the
source file (`sortOrder`), so lessons keep their authored order — a SwiftData
fetch is otherwise unordered.

**Pipeline.** Section 9 of the rewrite spec describes a Python generator,
but it is not in the repo. This project requires it to:

1. fill the `nd_*` fields deterministically by appending んです / んだ to each
   verb's plain forms, and
2. recompute both manifest hashes.

`grammar.json` is hand-authored prose; the pipeline only validates its
schema and hashes it. If the full generator is not built by the time this is
implemented, the minimum deliverable is a small standalone script for those
two jobs.

## 3. UI and navigation

The rewrite spec has not been implemented in `App/` yet (only the app entry
point exists), so this section builds on that spec's navigation design.

**Top-level navigation.**

- All platforms: a `TabView` with **Verbs** and **Grammar** tabs, each tab
  its own `NavigationSplitView` (list/detail at regular width, a stack on
  iPhone). It uses the sidebar-adaptable style, so on iPad and Mac the tabs
  can become a sidebar. Quiz, history and settings stay reachable from the
  Verbs tab as the rewrite spec describes.
- This changes the rewrite spec, which assumed the verb list is the app root.
- The sidebar-adaptable style needs iOS 18 / macOS 15; the project's floor is
  now iOS 26 / macOS 26, so it is available. Only the default state was
  checked on an iPad simulator (a floating Verbs | Grammar switcher above the
  verb list/detail split); the toggled sidebar, where the tabs and each tab's
  own split view are both sidebars, was not exercised.

**Visual style** follows the rewrite spec's design direction (its section 10):
custom surfaces — level badges, lesson cards, the んです form tiles, link
buttons — use `.glassEffect()` / `.glass` button styles, standard containers
are left alone, and no accessibility-specific modifiers are added.

**Grammar list.** Rows show title, summary and a level badge. `.searchable`
matches title, summary and example `jp` text. No filter chips in v1. If
grammar has not synced, show the "not downloaded yet" state with Try Again.

**Grammar detail** (single scrolling page, in order):

1. Summary and level
2. How it attaches — one row per word class: pattern, worked example, note
3. Usages — one card each: heading, explanation, examples with tap-to-reveal
   English
4. Conjugations — grouped by register
5. Watch out — the lesson's pitfalls, examples included
6. Related — links to other grammar points that exist locally (empty until
   more exist)

**Verb detail additions.** A collapsible **"んです"** section after
"Advanced", collapsed by default, hidden when the verb has no `nd_*` fields.
It shows the eight forms in a polite/casual grid. A "Learn about んです →"
row navigates to `n-desu`, resolved by grammar id and hidden if that point
has not synced.

**Routing.** A single `Route` enum (`.verb(id)`, `.grammar(id)`) is the one
path for cross-links and later widget/Shortcuts deep links. The app exposes
it to views as an `openRoute` environment action, so a verb page can jump to
a lesson without any parameters threaded through existing views. Because an
iPhone `NavigationSplitView` shows its list until told otherwise, opening a
lesson also sets the grammar tab's `preferredCompactColumn` to `.detail`;
otherwise a link to a tab that hasn't been visited yet would land on the list.

furigana or reading toggles (now scheduled as sub-project 5)

## 4. Lesson content: `n-desu`

**Summary line:** んです (the spoken form of のです) marks a sentence as
explanation, context or reason rather than a bare statement.
行きません = "I won't go"; 行かないんです = "I'm not going (and there's a
reason or context)".

**Attachment**

| Word class | Rule | Example |
|---|---|---|
| Verb | plain form + んです | 食べるんです / 食べないんです / 食べたんです / 食べなかったんです |
| い-adjective | plain form + んです | 高いんです / 高くないんです / 高かったんです |
| な-adjective, noun (non-past affirmative) | stem + **なんです** | 静かなんです / 学生なんです |
| な-adjective, noun (past, negative) | だ-forms + んです | 学生だったんです / 学生じゃないんです |

The な in なんです is the plain だ becoming な before の, so it appears only
in the non-past affirmative. The polite form never precedes it:
✗食べますんです.

**Usages** (two examples each in the data)

1. Asking for or giving a reason — どうしたんですか。頭が痛いんです。
2. Softening a request or lead-in (with が / けど) —
   すみません、道を聞きたいんですが。
3. Refusing with a reason — 今日は行けないんです。(potential form; bridge
   to sub-project 2)
4. Reacting to something noticed (with ね) — 日本語が上手なんですね。
5. Emphasis or background, including the cleft type — 実は、まだ食べていない
   んです。 / 昨日買ったのは、この本なんです。
6. Checking an inference — 疲れているんですか。
7. Acknowledging what someone told you ("oh, is that so") — そうなんですか。
   / そうなんだ。

**The ending's own conjugations**

| Register | Forms |
|---|---|
| Polite | んです · んですか · んですが/けど · んですね · んじゃないですか · んじゃありません · んでした (rare) |
| Casual | んだ · んだよ · の？ / んだ？ · の (soft statement) · んじゃない |
| Formal/written | のです · のだ · のではありません |

Note on の as a statement (行くの。): it sounds softer and, for many
speakers, feminine. As a question (行くの？) it is neutral and very common.

**Pitfalls stated explicitly in the lesson**

- **Negation.** 食べないんです is an explanation. 食べるんじゃない /
  食べるんじゃありません is a strong "don't eat!", and 食べたんじゃない
  means "it's not that I ate".
- **Overuse.** For plain new information use the ordinary polite form
  (毎日学校に行きます). んですか asks for an explanation, so it can sound
  probing ("what's going on?") or, with the wrong tone, demanding or
  aggressive. It is not a neutral question marker.
- **Past.** The past goes on the verb (食べたんです). 〜んでした exists but is
  rare; mentioned as an aside only.

**Deliberately excluded:** なので/ので and なんで ("why", casual). They are
listed in `related` for a later sub-project.

**Content conventions:** examples follow the existing data convention (mostly
hiragana, kanji where natural). English explanations are learner-friendly,
not linguistically exhaustive.

## 5. Testing

- **Sync** (mock `VerbDataFetching`): grammar manifest unchanged → skipped;
  changed → fetched; hash mismatch → `malformedData`; a grammar failure
  leaves the verb sync result unaffected.
- **Decoding**: `grammar.json` decodes against `GrammarPoint`; the real data
  file is used as the fixture.
- **`nd_*` data**: fixture test checking values against hand-verified forms
  for one verb per class (ichidan, godan, する, 来る).
- **Logic in `VerbKit`**: grammar search matching and `Route` resolution get
  unit tests.
- **UI**: verified by running in Simulator per platform, consistent with the
  rewrite spec (no UI/snapshot tests).

## 6. Open items

- The Python generator from rewrite-spec section 9 does not exist, so the
  minimal standalone script from section 2 is built: `scripts/update_data.py`.
- The UI half (sections 3's screens) builds on the core app's verb list and
  detail screens, so it can only be implemented once those exist; the data
  and logic half has no such dependency.

## Refinements found along the way

Discovered while writing and verifying the implementation plan, and again
when reconciling it with a `main` that had moved on (the core app UI was built
and several fixes landed). The sections above already reflect them.

- The lesson content promised "pitfalls", but the data model had nowhere to
  put them: added `pitfalls` (sections 1, 3).
- Attachment rows for な-adjectives and nouns differ by tense/polarity, so a
  rule needs an optional `condition` (section 1).
- Persisted grammar keeps authored order via `sortOrder` (section 2).
- `sync()` must not record the manifest; the caller confirms after
  persisting. `main` adopted this contract for verbs after the plan was
  written, and grammar follows it (section 2).
- The platform floor moved from iOS 17 / macOS 14 to iOS 26 / macOS 26, which
  makes the sidebar-adaptable tab style available; an earlier revision of
  this spec had dropped it (section 3).
- Cross-links use an `openRoute` environment action plus
  `preferredCompactColumn` (section 3).
- The conjugation table gained んじゃありません and んでした, which section 1
  already said the matrix would hold (section 4).
- `List(selection:)` rows need an explicit selection: with `ForEach` over
  `Identifiable` items, SwiftUI matches selection against the row's `id`, not
  the element, so taps silently do nothing. `main` settled on a `Button` that
  sets the selection plus `.tag(value)`, and the grammar list uses the same
  pattern.
- The rewrite spec's design direction (Liquid Glass surfaces, no
  accessibility modifiers) applies to the new screens (section 3).
