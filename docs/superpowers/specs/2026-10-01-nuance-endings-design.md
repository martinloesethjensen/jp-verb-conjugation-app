# Nuance Endings — Design

**Date:** 2026-10-01
**Status:** Approved in brainstorming, pending written-spec review
**Builds on:** [2026-09-29-grammar-foundation-nd-desu-design.md](2026-09-29-grammar-foundation-nd-desu-design.md)
(sub-project 1, whose lesson model, sync and routing this reuses),
[2026-09-30-potential-form-design.md](2026-09-30-potential-form-design.md)
(sub-project 2), [2026-09-30-furigana-design.md](2026-09-30-furigana-design.md)
(sub-project 5, whose coverage check governs the new kanji) and the
[native rewrite spec](2026-09-23-native-apple-rewrite-design.md) (section 10, the
visual design direction). This is **sub-project 3** of the grammar work.

## Summary

Add four intermediate lessons on the nuance endings, and a **Grammar** section on
every verb page that links to every lesson attaching to verbs.

- **Content:** four lessons in `data/grammar.json`, in the existing lesson shape. No
  model change.
- **Readings:** every new kanji run gets an entry in `data/furigana.json`; the
  existing coverage check enforces it.
- **App:** a `VerbGrammarSection` on the verb detail page, filled from the lesson data.

## 1. The lessons (`data/grammar.json`)

All four are `level: intermediate`, written independently (not copied from Yokubi),
mostly hiragana with kanji where natural, and reviewed by the maintainer.

| id | title | covers | the core contrast |
|---|---|---|---|
| `certainty` | はず・かもしれない・わけ | はず (expectation), かもしれない (possibility), わけ (it follows that; わけがない, わけではない) | how sure the speaker is; わけ explains rather than predicts |
| `obligation` | べき・ものだ | べき (should, advice; すべき vs するべき), ものだ (general truth, nostalgia) | personal advice vs. a general statement |
| `appearance` | よう・みたい・そう・らしい | ようだ/みたいだ (resembles, seems), そうだ (looks like vs. I hear), らしい (hearsay, typical of) | the two そう, and evidence vs. hearsay |
| `ppoi` | っぽい | -ish / tends to (子供っぽい, 忘れっぽい, 白っぽい) | attaches to nouns, verb stems and い-adjective stems |

- **Structure.** Each lesson has "How it attaches" cards, one per word class, using
  `AttachmentRule.condition` for the awkward cases (はず takes plain forms, な after
  na-adjectives and の after nouns; そう has separate stem-based and plain-form cards
  for its two meanings); usages with examples; the ending's own forms where they
  matter; "Watch out" cards; and `related` links.
- **Cross-links.** Sibling lessons relate to each other (`certainty` ↔ `appearance`);
  `obligation` and `certainty` also link to んです and 可能形 where a real contrast
  exists. Links between sibling lessons must go both ways.
- **No model change.** `attachment`, `conjugations`, `pitfalls` and `related` already
  fit these endings.

## 2. The verb-page Grammar section (app code)

- **`GrammarPoint.attachesToVerbs`** (VerbKit, pure): true when any attachment rule has
  `wordClass == .verb`. Unit-tested, including a lesson with no verb rule.
- **`VerbGrammarSection`** (app), last on every verb's detail page, collapsed by default
  and styled like the other sections. Its rows are `VerbStore.grammarPoints` filtered
  through `attachesToVerbs`, in the Grammar tab's existing order: today んです, 可能形
  and the four new lessons; sub-project 4's lessons join automatically.
- **Rows** show the title (through `JapaneseText`, so it gets furigana) and the summary
  on one line. Tapping one calls `openRoute(.grammar(id))`, the path the んです and
  Potential links use, so it switches to the Grammar tab and lands on the lesson even
  on a fresh install.
- **Hidden until useful.** With no lessons synced there is nothing to list, so the
  section does not appear.
- **Unchanged.** The んです and Potential sections keep their own contextual links.
  The list is the same on every verb: no per-verb ordering.
- Visual direction as before: `.glassEffect` for custom surfaces, `.glass` buttons, no
  accessibility-specific modifiers.

## 3. Data, testing and rollout

### Data and guards

`grammar.json` and `furigana.json` each go up a minor version, both through
`scripts/update_data.py`; `verbs.json` does not change. The existing guards apply: the
grammar validator (levels, word classes, registers, `related` ids that exist) and the
furigana coverage check, which fails and names any kanji run in the new lessons without
a reading. One new guard: `related` links between sibling lessons must point both ways.

### Testing

- **Real-data Swift tests:** the four lessons exist with the expected ids and
  `intermediate` level, each has attachment rules for the word classes it should, and
  the existing coverage tests still resolve every kanji run.
- **`attachesToVerbs`** and the section's list logic (filter and order), without UI,
  including "no grammar synced means no section".
- **Script (Python):** the two-way `related` guard fails with a clear message.
- **Simulator:** the section is collapsed on every verb; a row opens the right lesson
  from a cold start; the longer lesson pages scroll smoothly and look right in light
  and dark.

### Rollout

Old builds keep working: the lessons are plain data in the existing shape and appear
in their Grammar tab as normal lessons; they lack only the verb-page section. Pushing to
GitHub `main` publishes the data and needs the user's go-ahead.

### Risks

| Risk | Covered by |
|---|---|
| Wrong or unnatural Japanese in a lesson | Maintainer review of the draft; only constructions I am sure of |
| A reading missing for new kanji | The coverage check |
| Attachment rules wrong for an ending (the most error-prone part) | One card per word class with example lines, called out for review |
| A long lesson page scrolls badly | Simulator check |

## Files this touches

- **Edited:** `data/grammar.json`, `data/furigana.json`, `data/manifest.json` (by the
  script), `scripts/update_data.py` and its tests, `GrammarPoint.swift` (the helper),
  `VerbDetailView.swift`, real-data tests.
- **New:** `App/VerbGrammarSection.swift`, tests for the helper.

## Not in this sub-project

- Per-verb ordering, search or filtering in the new section.
- The verb auxiliaries (sub-project 4).
