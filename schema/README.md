# Data schemas

One [JSON Schema](https://json-schema.org/draft/2020-12) per published file in `data/`:

| Schema | Describes |
|---|---|
| `verbs.schema.json` | `data/verbs.json` |
| `words.schema.json` | `data/words.json` |
| `counters.schema.json` | `data/counters.json` |
| `grammar.schema.json` | `data/grammar.json` |
| `furigana.schema.json` | `data/furigana.json` |
| `forms.schema.json` | `data/forms.json` |
| `kanji.schema.json` | `data/kanji.json` (built by `scripts/build_kanji.py`) |

They are the contract for every client that reads `data/`: the iOS app's `Codable` models, the review site's
Rust Worker (`review/api`), and an Android app later. `scripts/update_data.py` checks each file against its
schema as it will be written, so `make data` and `make data-check` fail, naming the file and the JSON path,
when data and schema disagree. A change to a data shape means changing the schema in the same PR.

## The subset

The schemas use only these keywords, so every client can implement them the same way
(`scripts/json_schema.py` is the reference; it rejects any other keyword):

`$schema`, `$id`, `$defs`, `$ref` (local `#/$defs/<name>` only), `title`, `description`, `type`, `enum`,
`const`, `pattern`, `minLength`, `minimum`, `required`, `properties`, `additionalProperties`,
`patternProperties`, `propertyNames`, `items`, `minItems`, `uniqueItems`.

Every pattern is anchored (`^…$`). Objects with fixed keys set `additionalProperties: false`; objects keyed
by data (forms, readings, overrides) use `propertyNames` and an `additionalProperties` schema for the values.

## Shared names

`$defs` that more than one schema has use the same names: `stableId` (the 6-character ids from
`scripts/stable_ids.py`), `jlpt`, `example` and `reviewStamp` (the `review` stamp from
`docs/superpowers/specs/2026-10-27-review-status-design.md`).

A `review` stamp may sit on a counter, a grammar point, a verb, a word and a verb example, and nowhere else:
grammar and counter examples are covered by their entry's stamp. A verb's stamp hashes the verb without its
`forms` and `examples` (each example has its own); a word's without its `forms`.

## Fixtures

`fixtures/invalid.json` is a list of small documents, each breaking exactly one rule:
`{"name", "dataset", "doc", "error"}`, where `error` is part of the expected message. `scripts/test_schemas.py`
checks the Python validator rejects each one for that reason; the review site's Rust tests use the same file.
