# Verb collocations ("Common phrases")

Status: shipped, content unreviewed. Issue #107.

## Problem

Learners know 浴びる means "to bathe" but not that it really only goes with シャワーを. They produce
×薬を食べる, ×風邪をとる, ×ズボンを着る. Natural production is mostly chunks, and the app teaches single
verbs.

## Data contract (`data/verbs.json`)

Each verb may carry an optional `collocations` list, after `examples`:

```json
"collocations": [
  { "id": "k3m9tq", "jp": "シャワーを浴びる", "en": "take a shower" },
  { "id": "w7xb2d", "jp": "日光を浴びる", "en": "get some sun" }
]
```

| Field | Rule |
|---|---|
| `collocations` | Optional. Leave it out when a verb has none; an empty list is rejected. |
| `id` | Stable review id: 6 characters from the stable-id alphabet, unique within verbs.json (shared with example ids). `scripts/assign_ids.py` fills it; it never changes once published. Clients ignore it except to address an item (the review site). |
| `jp` | The chunk in the verb's **dictionary form**, no final 。. It must end with the verb's `dict` or `kanji` spelling (`ネクタイをする`, `日本語がわかる`, `シャワーを浴びる`). Every kanji needs a reading in `furigana.json`, like any other string. |
| `en` | A short English gloss, lower case, no final full stop. It is searchable. |

No other keys are allowed, and a verb may not list the same `jp` twice. `scripts/update_data.py`
checks all of this (`check_verb_collocations`, `stable_ids` slot `"<verb id> collocation <n>"`).
Data published before this field existed has none, and clients must decode it as an empty list.

## Client behaviour

- The verb page shows a "Common phrases" card (Japanese with furigana, English, speak button,
  lookup/copy/translate) when the list is non-empty, and nothing otherwise.
- Verb search matches a query against each collocation's `en` (case-insensitive substring) and `jp`
  (substring), so "take a shower" finds 浴びる.
- Later: collocations are fill-in material for a quiz (not built yet).

An Android client follows the same rules: optional list, default empty, ignore unknown `id` semantics
beyond addressing.

## Content

2–3 conservative textbook chunks for every N5 verb, plus a small wearing set across the wearing verbs
that exist today: 着る (服/シャツ/コート), する (ネクタイ/時計), つける (ネックレス) and their opposite
脱ぐ (靴/服/コート). はく, かぶる and かける are not in verbs.json yet (#4); add their wearing chunks
when they land. Kanji follows the verb's examples (わかる and できる stay in kana, 家 is read いえ).

The content was written by the assistant and ships unreviewed, like the other assistant-written
data; the review site addresses each chunk by its `id`.
