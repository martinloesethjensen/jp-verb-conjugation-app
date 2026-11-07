# Transitive / intransitive verb pairs (自動詞・他動詞)

Status: in progress, content unreviewed. Issue #58.

## Problem

Choosing between 開ける and 開く, or 入れる and 入る, is one of the most common N4 mistakes. The two
verbs look alike and differ in the particle: ドアを開ける (someone opens the door) and ドアが開く
(the door opens). The app shows each verb alone, so a learner never sees the two halves together.

## Scope

1. **Data and the verb page (this spec):** a `pair` link on each half and a card on the verb page
   that shows both phrases side by side, with the partner one tap away.
2. **The lesson:** a grammar point `verb-pairs` (自動詞・他動詞, N4) on the patterns (を/が,
   〜す, 〜める/〜まる, the pairs where える is transitive, intransitive verbs for things that
   happened, てある/ている). Its examples mark を and が as `particle_blanks`, so the particle quiz
   already asks which particle each half takes. The pair card ends with a "Learn about" link to it.
3. Later, a separate pull request: a quiz kind that asks which half fits a sentence.

## Data contract (`data/verbs.json`)

Each verb may carry an optional `pair` object, after `collocations`:

```json
"pair": {
  "verb": "あく",
  "transitivity": "transitive",
  "jp": "ドアを開ける",
  "en": "open the door"
}
```

| Field | Rule |
|---|---|
| `pair` | Optional. Only verbs whose partner is also in the data have one. |
| `verb` | The partner's verb id (its explicit `id`, else `dict`, as in `つく:点く`). Ids never change, so links stay valid. |
| `transitivity` | This verb's half: `"transitive"` (takes を) or `"intransitive"` (takes が). |
| `jp` | A short phrase in the verb's **dictionary form**, ending with its `dict` or `kanji` spelling. It uses を for the transitive half and が for the intransitive half. Both halves should share a noun (ドアを開ける ↔ ドアが開く) so they read as a pair. Every kanji needs a reading in `furigana.json`. |
| `en` | A short English gloss, lower case, no final full stop. |

The link is symmetric: if A's pair names B, B's pair must name A with the other transitivity. No
other keys are allowed. `scripts/update_data.py` checks all of this (`check_verb_pairs`), and
`schema/verbs.schema.json` describes the shape.

The pair is authored content of the verb entry, so it has no stable id of its own: the review site
shows it on the verb's page and it is part of the entry's review hash. Changing a pair asks for the
verb to be reviewed again.

Clients that do not know `pair` ignore it. An Android client reads it the same way: look up the
partner by id and show both phrases.

## Pairs in the first batch

| Transitive (を) | Intransitive (が) |
|---|---|
| 開ける ドアを開ける | 開く ドアが開く |
| 閉める 窓を閉める | 閉まる 窓が閉まる |
| つける 電気をつける | つく (`つく:点く`) 電気がつく |
| 消す 電気を消す | 消える 電気が消える |
| 入れる 箱に本を入れる | 入る 箱に本が入る |
| 出す 声を出す | 出る 声が出る |
| 始める 会議を始める | 始まる 会議が始まる |

終わる/終える and 返す/返る wait until 終える and 返る are added as verbs.

## The verb page

A "Transitive pair" card after "Common phrases" shows two rows, this verb first:

- a small label, "Transitive · を" or "Intransitive · が";
- the phrase (furigana, speak button and text actions, as in Common phrases) and its gloss.

The partner's row opens the partner's verb page. The card draws nothing when the verb has no pair or
when the partner is not in the loaded data.
