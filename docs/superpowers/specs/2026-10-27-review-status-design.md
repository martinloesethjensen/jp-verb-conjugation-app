# Marking content that has not been reviewed

Status: approved and built, 2026-10-27 (the owner chose all four recommendations below). The owner asked for a pill or info marker for data they
have not reviewed yet, and asked me to propose the design and the approach. The choices are mine and marked.

## Problem

Most of the counters content (things, example sentences, pitfalls, 何 questions) was written by the assistant
without a native speaker, and the owner has not reviewed all the data. The app presents every entry the same
way, so a learner cannot tell a checked entry from an unchecked one, and the owner cannot see what is left to
review. The readings are validated by the pipeline; the prose is not.

## Goals

- A learner sees, on an entry, that it has not been reviewed, and what that means.
- The owner can see how much is reviewed, and mark an entry reviewed with one small, signed data change.
- An entry that was reviewed and then edited goes back to unreviewed by itself, so "reviewed" always means this
  exact text.

## Non-goals

- Grading quality, or a workflow with several reviewers. One status, one date, one reviewer name.
- Marking individual verbs, furigana and words. Verbs are generated forms, furigana and words are keys; the
  prose that needs review is in counters and grammar.
- Blocking or hiding unreviewed content.

## Anti-goals

- A pill on every row of every list, which would be noise while most of the data is unreviewed and would train
  people to ignore it.
- A status that can be set by hand and then forgotten after the text changes.

## Approach

### Data: a per-item review stamp, checked by the pipeline

An entry (a counter, a grammar point) may carry:

```json
"review": { "by": "teacher", "on": "2026-10-24", "sha256": "…" }
```

No `review` means unreviewed, so new content is honest by default. `sha256` is the hash of the entry's own
content with its generated fields (`readings`, `changed`, `distractors`) and the stamp removed. The pipeline:

- computes the hash and **fails with a clear message when a stamp no longer matches** ("hon was edited after
  review on 2026-10-24: re-review it, or run `scripts/mark_reviewed.py` again");
- validates the shape (`by` is `owner` or `teacher`, `on` is a date);
- never writes a stamp itself.

`scripts/mark_reviewed.py <counters|grammar> <id>… --by teacher --on 2026-10-24` adds or refreshes stamps, so
reviewing is: read the entries, run the script, sign. Old builds ignore the field.

### App: quiet by default, explicit where it matters

- **Entry page (counter, grammar point):** a capsule beside the JLPT level, **"Not yet reviewed"** (outlined,
  amber) or **"Reviewed"** (a small check, only for a stamped entry). Tapping it opens a short sheet: what the
  pipeline checks automatically (readings, sound changes) and what no one has checked yet (the examples,
  pitfalls, things and questions), who reviewed it and when if stamped, and a **Report a problem** button (the
  app already has one).
- **Lists and home:** no per-row pill. One quiet line under the list, "12 of 30 counters reviewed", which
  grows as review proceeds. In search results a small icon on unreviewed entries is optional.
- **Settings > Data:** a "Content review" row per type with the counts and the latest review date, and a
  switch **Show review status** (on by default) for the owner who wants the pages clean.
- **Quiz:** no marker on questions; an unreviewed counter's questions are the same as today.

### Delivery

1. Pipeline: the stamp shape, the hash, the stale-stamp check, `mark_reviewed.py`, tests (a stamp survives a
   regeneration, an edit invalidates it).
2. Models and decoding in VerbKit, an `isReviewed` property, tests against the real data.
3. The capsule and the sheet on the counter and grammar pages, the list line, the Settings rows.
4. The owner's first review pass, using the script on the entries they have read.

## Constraints

- Every `data/` change, including stamps, is re-signed by the owner.
- Old app builds and old caches keep working: the field is optional.
- The pipeline's hash must not depend on field order or on generated fields, or regenerating would
  invalidate every stamp.

## Decisions for the owner

1. **Scope:** counters and grammar points first (my recommendation); verbs only if a per-verb note ever needs
   review.
2. **A hash in the stamp** (my recommendation: an edit un-reviews the entry) or a plain date, which is simpler
   but can say "reviewed" about text that changed afterwards.
3. **Wording:** "Not yet reviewed" and "Reviewed", or "Unchecked" and "Checked by a teacher".
4. **Where reviewers come from:** `owner` and `teacher` as the only two names, or free text.

## Decisions (owner, 2026-10-27)

1. **Scope:** counters and grammar points.
2. **Stamp:** a hash, a date and a reviewer, so an edit un-reviews an entry.
3. **Wording:** "Not yet reviewed" and "Reviewed".
4. **Reviewers:** `owner` and `teacher` only.

## As built

Plan: `docs/superpowers/plans/2026-10-27-review-status.md`.

- **Pipeline.** `update_data.py` validates every `review` stamp (reviewer, ISO date, hash) and fails with
  "<id> was edited after review on <date>: re-review it, or run scripts/mark_reviewed.py again" when the entry's
  hash no longer matches. The hash is SHA-256 of the entry's canonical JSON without `review` and, for a counter,
  without the generated `readings`, `changed` and `distractors`, so `make data` never invalidates a stamp.
  `scripts/mark_reviewed.py counters hon --by teacher --on 2026-10-24` (or `grammar n-desu --by owner`) writes
  or refreshes stamps; the hand-formatted `grammar.json` is edited in place, one line per entry.
- **App.** A capsule beside the JLPT level on counter and grammar pages ("Not yet reviewed" in amber, "Reviewed"
  with a check) opens a sheet that says what the pipeline checks automatically, what no person has checked yet
  and, when stamped, who reviewed it and when, with Report a problem. One quiet line under the Counters
  directory and the Grammar list ("No counters reviewed yet", then "12 of 30 counters reviewed"), counting only
  entries visible under the level settings. Settings > Content review shows the counts, the latest date and a
  Show review status switch (on by default); off hides the capsule and the lines.
- **Unchanged.** The "unreviewed" label on numbers above 10 stays: it is about generated number readings, not an
  entry's prose. No entry carries a stamp yet.

**To review entries:** read them, run `mark_reviewed.py`, then `make data` and `make sign-commit`. The stamp is
part of `data/`, so it is re-signed like any data change.

**Checked on screen** (iPhone 17 simulator): the capsule and its sheet on 年間 and the "No counters reviewed yet"
line under the Counters list. **Not checked on screen:** the grammar page and list, Settings > Content review and
the switch (the views are small and share the same components), a stamped entry ("Reviewed"), largest Dynamic
Type, dark mode.
