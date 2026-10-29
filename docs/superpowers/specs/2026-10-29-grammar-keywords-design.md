# Grammar search by English intent (#101)

Learners look grammar up by what they want to *say* ("because", "had better"), not by the
Japanese name. This adds English keywords to each lesson and widens and ranks grammar search.
This file is the contract an Android client follows.

## Data: `keywords` in `grammar.json`

Each object in `grammar` may carry:

```json
"keywords": ["because", "since", "so", "the reason"]
```

- Optional. A missing key means no keywords (decode as an empty list).
- When present: a non-empty list of non-empty strings, no duplicates (compared trimmed and
  case-insensitively). `scripts/update_data.py` rejects anything else, including a non-string
  keyword.
- English intents and common glosses, lower case except where English needs capitals ("I").
- Every published lesson has at least two keywords (checked by `RealGrammarDataTests`).
- Keywords ship unreviewed, like the rest of the lesson text, until a teacher reviews them.

## Search

A query (trimmed; empty matches every lesson in list order) is compared with each lesson and
gets the best of these ranks, best first:

| Rank | Matches |
|---|---|
| `exact` | the whole title or a whole keyword, case- and width-insensitive |
| `titleOrKeyword` | part of the title or of a keyword |
| `summary` | part of the summary, case-insensitive |
| `heading` | part of a usage `heading` |
| `example` | part of a usage example's `jp`, its kana reading (with furigana), or its `en` |

Romaji queries are also converted to hiragana (`Romaji.toHiragana`, spaces removed) and tried
against the title, keywords, headings, example `jp` and example readings.

Results are sorted by rank; lessons with the same rank keep the list's order (by JLPT level, as
published). The whole-keyword rank exists so "must" puts the must lesson
(〜なければならない) ahead of the lesson whose keyword is "must not" (〜てはいけない).

VerbKit: `grammarSearchRank(_:query:furigana:)`, `matchesGrammarSearch`, and
`Sequence<GrammarPoint>.searched(for:furigana:)`. The Grammar tab's "By level" list shows
matches in this order; "By lesson" keeps the course's lesson order. Spotlight indexes the title
and keywords.
