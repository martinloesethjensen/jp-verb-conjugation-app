# Kanji stroke order — design

Status: built in plan 3 of the paper-and-ink redesign (`docs/superpowers/specs/2026-11-06-paper-ink-redesign-design.md`).
Canvas boards: "Kanji stroke order", "trace", "opening it" and the Kanji section of "Verb page full length".

## What the user gets

A sheet for one kanji with two modes:

- **Watch**: the strokes drawn one at a time (current stroke in red, a red dot where it starts, numbers at
  each stroke's start), play/pause and step controls, a strip of frames, the readings and meanings, and up
  to five verbs in the app that use the kanji.
- **Trace**: a square to draw each stroke in order with a finger (or pointer). A faint guide can be hidden.
  A stroke drawn backwards or in the wrong place is shown in red with the expected stroke, and the user
  tries again; after the last stroke a red ring marks it finished.

It opens from the long-press text menu of any Japanese text ("Stroke order of 食", "Practise writing it";
a "Stroke order" submenu when the text has several kanji), from the Kanji section on a verb page, and from
the kanji chips on a Word Bank entry (which open Jisho for a kanji the data lacks).

## Data: `data/kanji.json`

A published, signed data file with its own manifest entry (`kanji`) and a bundled copy in the app, synced
like `forms.json` (`docs/security/data-signing.md`). Schema: `schema/kanji.schema.json`.

```json
{"schema": 1,
 "sources": {"kanjivg": "20260714", "kanjidic2": "2026-11-07"},
 "license": "Stroke paths: KanjiVG (c) Ulrich Apel, CC BY-SA 3.0. Readings and meanings: KANJIDIC2 (c) EDRDG, CC BY-SA 4.0.",
 "kanji": {
   "食": {"strokes": ["M52.75,10.5c0.11,0.98-0.19,2.67-0.97,3.93C45,25.34,31.75,41.19,14,51.5", "…"],
          "grade": 2, "on": ["ショク", "ジキ"], "kun": ["く.う", "く.らう", "た.べる"],
          "meanings": ["eat", "food"]}}}
```

- `schema` is the major format version. A client refuses a file with a newer `schema` and keeps what it has.
- `kanji` keys are single CJK unified ideographs (U+4E00–U+9FFF), in code-point order. `々` is never a key.
- `strokes`: one SVG path `d` per stroke, in stroke order, copied verbatim from KanjiVG. Coordinates are
  KanjiVG's 109 × 109 box with y pointing down. Paths use `M m C c S s` (absolute and relative); clients
  must accept packed numbers (`0.98-0.19`, `.5.5`).
- `grade`: KANJIDIC2's school grade, 1–6, or 8 for the jōyō kanji taught in secondary school; absent for
  anything else.
- `on`: katakana. `kun`: hiragana in KANJIDIC2 notation, `.` before the okurigana (`た.べる`, shown as
  `た(べる)`) and `-` for a prefix or suffix use (shown without it). KANJIDIC2's few katakana loan readings
  listed as kun (志 シリング) are dropped.
- `meanings`: KANJIDIC2's English meanings, at most three.

**Coverage**: every jōyō kanji (KANJIDIC2 grade 1–8, 2,136 kanji) plus every kanji in `data/verbs.json`,
`grammar.json`, `counters.json`, `words.json`, `furigana.json` and `forms.json`. `make data` fails when a
kanji in that data has no entry.

**Regenerating**: `make kanji KANJIVG=path/kanjivg-YYYYMMDD.xml.gz KANJIDIC=path/kanjidic2.xml.gz`
(`scripts/build_kanji.py`), then `make data`. The two source files are downloaded by hand and never
committed: KanjiVG's release `kanjivg-YYYYMMDD.xml.gz` from https://github.com/KanjiVG/kanjivg/releases and
`kanjidic2.xml.gz` from https://www.edrdg.org/kanjidic/kanjidic2.xml.gz.

**Licence**: the file is a derivative of KanjiVG (CC BY-SA 3.0) and KANJIDIC2 (CC BY-SA 4.0), so the file
is shared under CC BY-SA. That covers the data file only, not the app's code. The app credits both sources
in the sheet's footer and in Settings' data section.

## Tracing rules

All distances are in the 109-unit box. For a drawn stroke with first point `a` and last point `b`, against
the expected stroke's start `s` and end `e`:

1. Fewer than 3 points, or a drawn length under 6: ignored (a tap is not a mistake).
2. `d(a,e) + d(b,s) < d(a,s) + d(b,e)`: drawn the wrong way round.
3. `d(a,s) > 24` or `d(b,e) > 30`: not this stroke.
4. Otherwise accepted, and the next stroke is due.

A stroke's hint ("goes down to the left") comes from the direction of `e − s`, in eight 45° sectors.
Its number is drawn 6 units before its start, against the stroke's initial direction, kept inside 4…105.

## Motion and accessibility

- Watch draws each stroke over 0.6 s and steps every 0.7 s while playing. With Reduce Motion each stroke
  appears whole.
- The Watch drawing is one accessibility element ("食, stroke 4 of 9") that can be adjusted up and down
  by stroke. The Trace square has a label naming the stroke due and an action that shows it in Watch.
