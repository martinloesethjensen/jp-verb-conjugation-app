# JLPT levels in the data

The JLPT publishes no official vocabulary lists since 2010, so the `jlpt` field on each verb is a
convention, not a fact. This project follows the **Tanos JLPT lists** (jlptstudy / tanos.co.uk
vocabulary lists) when a verb's level is in doubt.

- Where Tanos and other lists disagree, use Tanos and do not change it without a reason.
- A verb's level only decides which JLPT filter shows it; it never changes the forms.
- Example of a disagreement settled this way: 見せる and 死ぬ are N5 in Tanos (previously N4 here).

## Grammar

Grammar levels follow the same source: the **Tanos JLPT grammar lists** (tanos.co.uk, N5–N1). As with
verbs, the JLPT publishes no official grammar list, so a level is a convention, and Tanos settles a
doubt.

### Lesson and usage levels

A lesson in `data/grammar.json` often bundles patterns from more than one level (かもしれない and はず
are N4, わけ is N3). So the level lives in two places:

- `jlpt` on the lesson (required): the default level of every usage in it.
- `jlpt` on a usage (optional): that usage's own level, overriding the lesson's. Omit it when it
  would equal the lesson's level; `update_data.py --check` rejects an unknown level and a redundant
  one.

A usage's level is its own `jlpt`, or else the lesson's. From that:

- A lesson is visible when **any** of its usages is visible under the level filter.
- A lesson's level range runs from its easiest usage level to its hardest ("N4–N3"); a lesson
  whose usages share one level shows just that level.
- In a lesson, a usage whose level is hidden is hidden too.

The lesson's own `jlpt` still decides where the lesson sorts and is the level the app shows when
every usage shares it. Example: `certainty` is N4, and its two わけ usages carry `"jlpt": "N3"`, so
an N4-only learner sees the はず and かもしれない usages, and an N3-only learner sees the わけ ones.

### Reference list

The levels the data currently gives its lessons and the usages inside them. Tanos is the source to
check them against; a level that disagrees with Tanos is a data correction.

| Level | Patterns |
|---|---|
| N5 | ている, 〜たい, 〜ましょう・〜ましょうか, 〜ないで・〜なくて |
| N4 | んです, potential (可能形), はず, かもしれない, よう・みたい・そう・らしい, てある, てしまう・ておく, てみる・ながら, すぎる・やすい・にくい, 〜ので, 〜ほうがいい, 〜てもいい・〜てはいけない, 〜なければならない・〜なくてもいい, imperative (命令形・〜な・〜なさい), casual volitional and 〜(よ)うと思う |
| N3 | わけ (わけだ, わけがない, わけではない), べき・ものだ |
| N2 | っぽい |

The casual volitional usages are N4 inside the N5 `volitional` lesson; their headings still say
"(N4)" and they do not carry a usage level yet. Relabelling whole lessons (`certainty`,
`appearance`, `teiru`, `volitional`, `ppoi`) is a separate data correction.

Content ships unreviewed: these levels have not been checked by a teacher yet (a review site for
teachers and native speakers is planned).
