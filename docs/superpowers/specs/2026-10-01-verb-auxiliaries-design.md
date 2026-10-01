# Verb Auxiliaries — Design

**Date:** 2026-10-01
**Status:** Approved in brainstorming, pending written-spec review
**Builds on:** [2026-09-29-grammar-foundation-nd-desu-design.md](2026-09-29-grammar-foundation-nd-desu-design.md)
(sub-project 1), [2026-09-30-potential-form-design.md](2026-09-30-potential-form-design.md)
(sub-project 2, whose generated-forms pattern this reuses),
[2026-10-01-nuance-endings-design.md](2026-10-01-nuance-endings-design.md)
(sub-project 3, whose lessons, mutual-link guard and verb-page Grammar section this
extends), [2026-09-30-furigana-design.md](2026-09-30-furigana-design.md) and the
[native rewrite spec](2026-09-23-native-apple-rewrite-design.md) (section 10, the
visual design direction). This is **sub-project 4** of the grammar work.

## Summary

Add the verb auxiliaries in three parts:

- **Content:** four lessons in `data/grammar.json`, in the existing lesson shape.
- **Data:** 22 generated optional forms per verb in `data/verbs.json`, built by
  `scripts/update_data.py` from each verb's て-form and ます-stem.
- **App:** an **Auxiliaries** section on the verb page, with links to the lessons.

## 1. The lessons (`data/grammar.json`)

Four lessons in the roadmap order, written independently (not copied from Yokubi),
mostly hiragana with kanji where natural, and reviewed by the maintainer. No model
change.

| id | title | level | covers |
|---|---|---|---|
| `teiru` | ている・てある | beginner | ている (action in progress, resulting state, habit, experience), てある (a state left by someone's action; transitive verbs only) |
| `teshimau` | てしまう・ておく | intermediate | てしまう (completion, regret; casual ちゃう/じゃう), ておく (doing in advance, leaving as is) |
| `temiru` | てみる・ながら | beginner | てみる (try doing), ながら (two things at once; the main action is the second) |
| `sugiru` | すぎる・やすい・にくい | intermediate | すぎる (too much), やすい (easy to), にくい (hard to) |

- **Attachment** is taught once per family. The て-form lessons attach to the て-form of
  every verb class (including the irregular して and きて, and the って / んで / いて / いで
  / して endings); the stem lessons attach to the ます-stem (たべ, のみ, し, き). Cards
  use `condition` where an ending is narrower (てある: transitive verbs; ている: the
  stative uses).
- **Contrasts** are the point and go in the Watch-out cards: ている as in progress vs.
  as a resulting state (結婚している, 知っている); ている vs. てある; てしまう (finished,
  or regret) vs. ておく (prepare); and the stem before すぎる / やすい / にくい with
  いい → よすぎる and ない → なさすぎる. 行く + ている ("has gone and is there") gets a
  Watch-out card of its own.
- **Cross-links**, all mutual: `teiru` ↔ `teshimau`, `teshimau` ↔ `temiru`,
  `temiru` ↔ `sugiru`, and `sugiru` ↔ `appearance` (すぎそう, "looks like too much").
  The `appearance` lesson therefore gains `sugiru` in its `related` list.
- **Furigana.** Every new kanji run gets a reading (the coverage check enforces it).
  Context-dependent readings (着, 出, 話, 行, 開 and so on) are checked against the
  matcher, and the tricky keys get pinned-reading tests.

## 2. Generated forms (script, model, data)

22 new optional fields per verb, snake_case, generated and never hand-written:

| group | fields | built from |
|---|---|---|
| ている, full grid (9) | `teiru`, `teiru_neg`, `teiru_past`, `teiru_past_neg`, `teiru_masu_pos`, `teiru_masu_neg`, `teiru_masu_past`, `teiru_masu_past_neg`, `teiru_te` | `te` + いる, いない, いた, いなかった, います, いません, いました, いませんでした, いて |
| て-form pairs (6) | `teshimau`, `teshimau_polite`, `teoku`, `teoku_polite`, `temiru`, `temiru_polite` | `te` + しまう / しまいます, おく / おきます, みる / みます |
| stem pairs (6) | `sugiru`, `sugiru_polite`, `yasui`, `yasui_polite`, `nikui`, `nikui_polite` | the ます-stem + すぎる / すぎます, やすい / やすいです, にくい / にくいです |
| stem single (1) | `nagara` | the stem + ながら |

- The ます-stem is `masu_pos` minus ます (たべ, のみ, し, き), so the irregular verbs need
  no special cases: する gives している and しすぎる; くる gives きている and きすぎる.
- **The script** gets one deterministic step, `apply_auxiliary_forms`, beside the `nd_*`
  and potential steps. It owns all 22 fields: it overwrites a hand-set value, is
  idempotent, and fails with a clear message (writing nothing) if a verb's `te` is
  missing or its `masu_pos` does not end in ます.
- **The one hand-kept list** is `NO_TE_AUXILIARIES = {"ある"}`: ある gets none of the
  て-form fields (the ている grid, てしまう, ておく, てみる), and stale ones are removed,
  but it keeps the stem-based forms. Extend it as verbs are added (for example いる).
  てある is not generated, because transitivity is not in the data.
- **The model.** `VerbForms` gains the 22 optional fields (CodingKeys, init parameters)
  and `hasAuxiliaryForms`. There are **no `FormKey` cases**, so none of this reaches the
  quiz, search or the Examples sheet.
- **Versions.** The script bumps `verbs.json`, `grammar.json` and `furigana.json` by a
  minor version. Older builds ignore the unknown fields, because they are optional and
  an older decoder skips unknown keys.

## 3. The app, testing and rollout

### The verb page

One new `AuxiliaryFormsSection`, collapsed by default, after んです and before the
Grammar section. It is hidden when the verb has no auxiliary forms, and its lesson links
are hidden until the lessons have synced (the Potential and んです pattern). Inside:

- the nine ている forms as glass tiles, with the labels the other form sections already
  use, then a **Learn about ている** link;
- a grid with a row per pair (てしまう, ておく, てみる, すぎる, やすい, にくい) and two
  columns, Plain and Polite, then a link to each lesson;
- ながら as a single tile.

For ある only the stem rows and ながら appear. The Grammar section already lists every
lesson attaching to verbs, so it picks up the four new lessons by itself. Forms are
kana, so they use `Text`; lesson titles use `JapaneseText`. Visual direction as before:
`.glassEffect` surfaces, `.glass` buttons, no accessibility-specific modifiers.

### Testing

- **Python:** the generator (each verb class, both irregulars, ある, idempotence, repair,
  both error cases).
- **Swift:** `VerbForms` decoding with and without the new fields and
  `hasAuxiliaryForms`; real-data tests that restate the formation rules independently
  and check all 25 verbs; lessons tests (four lessons exist, levels, word classes,
  mutual links); pinned-reading tests for the context-dependent furigana keys.
- **Simulator:** the section on たべる, する and ある; a link opening each lesson from a
  cold start; the longer lesson pages scrolling smoothly in light and dark.

### Risks

| Risk | Covered by |
|---|---|
| Wrong or unnatural Japanese in a lesson | Maintainer review, plus an independent Japanese-language review pass |
| A wrong reading in context | Matcher check before the plan, plus pinned tests |
| A generated form that is not really used (行く + ている as "has gone") | The Watch-out card; the section shows forms, not claims |
| A large `verbs.json` diff | Review by structure: only new keys, no existing field changed |

## Files this touches

- **New:** `App/AuxiliaryFormsSection.swift`, the generator step and its tests, four
  lessons, new tests.
- **Edited, patch-style on top of the latest `main`:** `VerbForms.swift`,
  `VerbDetailView.swift`, `update_data.py` and its tests, `grammar.json` (including the
  `appearance` lesson's `related` list), `furigana.json`, `verbs.json` and
  `manifest.json` (by the script).

## Not in this sub-project

- てある forms, ていく / てくる, the casual contractions (ちゃう, とく) as generated
  fields, auxiliaries in the quiz, per-verb example sentences.
