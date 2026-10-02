# Form-agnostic data model — Design

**Date:** 2026-10-02
**Status:** Draft for maintainer review (design only; no implementation code)
**Builds on:** [native rewrite](2026-09-23-native-apple-rewrite-design.md),
[quiz topics](2026-10-01-quiz-topics-design.md),
[verb auxiliaries](2026-10-01-verb-auxiliaries-design.md). Grammar already has
`WordClass` (`verb`, `i-adjective`, `na-adjective`, `noun`) in `attachment` rules; this
spec brings the conjugation data, the app models and the quiz to the same level.

## 1. Summary

Extend the app from verbs to **i-adjectives, na-adjectives and nouns (the copula)** without
a `Verb`/`Adjective` fork. Recommended model (option **d**, stored the way option **b**
stores things):

- A **form** is identified by a stable string `id` (the existing snake_case keys stay
  valid) and described by a **catalogue entry**: semantic facets (register, polarity,
  tense, role), a topic/family, the word classes it applies to, and the rule that
  generates it.
- A **word** is one concrete `Word` with a `wordClass` and
  `forms: [formID: surface]`. It never has a field per form.
- The **catalogue and rules live in `update_data.py`** (still the single source of
  derived forms). The script also emits `forms.json`, which the app bundles; labels,
  quiz topics, detail-page sections and search flags all come from it.
- `verbs.json` stays **byte-compatible**: its `forms` object already *is* an
  id→surface dictionary. Adjectives and nouns arrive as new files with the same
  envelope, each with an optional block in `manifest.json`.

Type safety is recovered by (1) static `FormID` constants for the few forms code names
directly, (2) the catalogue as the typed layer the UI and quiz iterate, never guess, and
(3) generator and Real-data tests that guarantee presence.

## 2. What the code does today (facts this design rests on)

- `verbs.json`: 25 verbs; `forms` is a flat object of snake_case keys; examples carry
  `"form": "masu_pos"`. Forms are **kana**; `dict` is the kana citation form and `kanji`
  the optional kanji spelling. `label` ("Ru-verb") is stored in data.
- `VerbForms` has 52 optional-or-required stored properties, a 52-argument `init`, a
  52-case `CodingKeys`, and three hand-listed `has*Forms` arrays. `QuizForm.all` repeats
  the same ids again with a closure each. `FormKey` (9 cases) drives search, examples and
  the Examples sheet. Several `VerbForms` fields (`volitional`, `passive`, `causative`,
  `conditional_*`, `imperative`, `tai`) exist in Swift but no verb in the data fills them.
- `update_data.py` derives nd, potential and auxiliary forms from base forms with
  per-feature tables (`ND_FIELDS`, `POTENTIAL_CONJUGATIONS`, `TEIRU_CONJUGATIONS`, ...) and
  exception sets (`IRREGULAR_POTENTIAL`, `NO_POTENTIAL`, `NO_TE_AUXILIARIES`). It owns
  `manifest.json`; `--check` fails when data is stale.
- `manifest.json` has verbs at the root (`version`, `sha256`) plus optional `grammar` and
  `furigana` blocks. Old apps ignore unknown keys (Codable default), which is what makes
  a new optional block safe.
- Persistence: `VerbEntity` (columns + `formsData` JSON), `GrammarEntity` and
  `FuriganaEntity` (payload `Data`). All of it is a re-fetchable cache of the JSON.
- Gotcha that shapes the Swift design: `Dictionary<K, V>` is only encoded as a JSON object
  when `K` is `String` or `Int`. A `RawRepresentable` `FormID` key would encode as a
  flat array. `Conjugations` therefore needs a hand-written `Codable`.

## 3. Options compared

| | (a) Parallel `Verb` / `Adjective` | (b) One `Word` + `[String: String]` | (c) `Conjugatable` protocol + concrete types | (d) Form identity ≠ surface ≠ applicability (catalogue) |
|---|---|---|---|---|
| Duplication | High: forms struct, quiz, search, stores, entities ×N | None | Medium: concrete types still duplicated; protocol hides it from callers | None |
| Type safety | Best per type | Worst: stringly typed, UI/quiz guess | Good per type, weak through `any` | Good: catalogue is the typed layer; constants for named forms |
| SwiftData | Entity per type | One payload entity | Existentials don't persist; needs concrete entities anyway | One payload entity (matches `GrammarEntity`) |
| JSON layout | Natural | Natural | Natural | Natural; `verbs.json` unchanged |
| Backward compat | Verbs untouched | Verbs decode unchanged | Verbs untouched | Verbs decode unchanged |
| Quiz | Parallel generators | One generator, guesses applicability | Generic over protocol, awkward for distractors | One generator reading catalogue |
| Widgets | Untouched | Need accessors | Untouched | `forms[.masuPos]` |
| Testability | Per-type tests multiply | Weak guarantees | Mixed | Catalogue-invariant tests give strong guarantees |
| Adding a form | New field in N places | New key, no validation | New requirement | One catalogue entry + one rule |
| Adding a class | New models | New enum case | New type | Catalogue applicability + rules |

**Recommendation: (d), persisted as (b).** (a) and (c) pay the duplication cost the
problem statement rules out; (b) alone loses the guarantees. (d) keeps (b)'s one model
and adds exactly what (b) lacks: a validated vocabulary of forms. A protocol is still
useful in one narrow place (`Leveled` already exists); it is not the model.

## 4. Form taxonomy

### 4.1 Dimensions

A catalogue entry carries these facets (any may be absent: a て-form has no tense):

| Facet | Values | Notes |
|---|---|---|
| `role` | `finite`, `connective` (て/くて/で), `adverbial` (く/に), `attributive` (な/の), `derived` (potential, ている, すぎる, ...) | Replaces today's hack of putting "て-form" in the *register* slot of the quiz label. |
| `register` | `short`, `polite`, `casual`, `formal` | `casual` is the んだ family; `formal` is である. |
| `polarity` | `pos`, `neg` | |
| `tense` | `present`, `past` | |
| `family` | `basic`, `nd`, `potential`, `auxiliary`, `adjective`, `copula` | The quiz topic and detail-page section. A catalogue field, not an enum in Swift. |
| `grammar` | a `GrammarPoint.id` (`n-desu`, `potential`, `teiru`, `sugiru`, ...) or null | Links forms to lessons. |
| `concept` | e.g. `polite.pos.present` | Equates forms that mean the same across classes when the storage id differs (§4.3). |

Facets are **descriptive metadata**, not a generator. Not every combination exists
(no polite `te`), so the catalogue lists real forms; it does not take a product.
Labels such as "Polite · past" are computed from facets, with an optional `label`
override.

### 4.2 Shared and class-specific forms

`V` verb, `I` i-adjective, `Na` na-adjective, `N` noun.

| Form id(s) | Family | Applies to | Notes |
|---|---|---|---|
| `short_pos`, `short_neg`, `short_past`, `short_past_neg` | basic | V I Na N | Same ids as today; surfaces differ by class. |
| `masu_pos`, `masu_neg`, `masu_past`, `masu_past_neg` | basic | V | Legacy ids; concept `polite.*`. |
| `polite_pos`, `polite_neg`, `polite_past`, `polite_past_neg` | basic | I Na N | New ids; same concepts as `masu_*`. |
| `te` | basic | V I Na N | て / くて / で. |
| `nd_pos`…`nd_past_neg`, `nd_casual_pos`…`nd_casual_past_neg` | nd | V I Na N | Grammar `n-desu` already attaches to all four. Na/N present affirmative uses なんです / なんだ. |
| `potential`, `pot_*` (9) | potential | V | Unchanged. |
| `teiru*`, `teshimau*`, `teoku*`, `temiru*`, `yasui*`, `nikui*`, `nagara` (22) | auxiliary | V | Unchanged. |
| `sugiru`, `sugiru_polite` | auxiliary | V I Na | Same ids and same concept; grammar `sugiru` already attaches to all three. |
| `adverbial` | adjective / copula | I Na | たかく / しずかに. One id, class-specific surface. |
| `sou` | adjective | I Na | たかそう / しずかそう. Verb `sou` is a later additive entry. |
| `naru` | adjective | I | たかくなる. |
| `conditional_ba`, `conditional_tara` | adjective | I | たかければ / たかかったら. |
| `attributive` | copula | Na N | しずかな / がくせいの. |
| `formal_pos`, `formal_neg`, `formal_past`, `formal_past_neg` | copula | Na N | である family. |

New forms are catalogue entries. Reserved-but-unfilled ids (today's `volitional`,
`passive`, ...) become catalogue entries with a `status: "planned"` flag instead of dead
Swift properties.

### 4.3 Shared concepts with different ids

Verbs keep `masu_*` (backward compatibility); other classes use `polite_*`. The catalogue
gives both the same `concept` (`polite.pos.present`, ...), so "the polite negative of
this word" is `catalogue.form(concept:for:)` regardless of class. All other shared
forms (`short_*`, `te`, `nd_*`, `sugiru`, `adverbial`) share a single id.

### 4.4 Irregulars and missing forms

Three distinct situations, kept distinct:

1. **Not applicable to the class**: catalogue only (no `potential` for an i-adjective).
   Never stored, never required.
2. **Applicable but lexically absent**: the key is **missing** from `forms`, and a
   generator-side table says why (`NO_POTENTIAL = {ある}` today). The validator requires
   every applicable form unless the lemma is in that table. UI and quiz already treat
   "no key" as "skip".
3. **Irregular surface** (する, 来る, ある, いい→よくない, だ→である): the surface is
   **generated and stored**, so the app never conjugates. Exceptions live in generator
   tables keyed by lemma or suffix (`いい` suffix → stem `よ`, which also covers
   かっこいい). The copula (だ→である, じゃない/ではない) is irregular by *class*, not by
   lemma, so it is simply the na/noun rule set. Authors never mark irregularity in data;
   `notes` carries the explanation shown to learners.

**Alternate surfaces** (polite negative `しずかじゃないです` / `しずかではありません`): the
canonical string goes in `forms`; extras go in an optional `alt` object
(`"alt": {"polite_neg": ["しずかではありません"]}`). Quiz answers accept alts, and
distractors must never equal one.

## 5. JSON

### 5.1 Envelope (shared by all word files)

Same as `verbs.json`: `version`, `description`, an array. New: `word_class` on each
entry (optional in `verbs.json`, where the file implies `verb`) and `schema` at the top
(optional, additive in `verbs.json`). Do **not** store `label` in new files; derive it.

### 5.2 Verb: unchanged (excerpt)

```json
{
  "type": "ru",
  "label": "Ru-verb",
  "dict": "たべる",
  "kanji": "食べる",
  "meaning": "to eat",
  "description": "A fundamental ru-verb. Drop the final る and add your ending.",
  "notes": "て-form たべて is used in sequences like たべてから (after eating).",
  "jlpt": "N5",
  "forms": { "masu_pos": "たべます", "te": "たべて", "short_pos": "たべる", "short_neg": "たべない", "...": "unchanged" },
  "examples": [{ "form": "masu_pos", "jp": "あさごはんをたべます。", "en": "I eat breakfast." }]
}
```

Only the optional `"word_class": "verb"` could be added later, additively.

### 5.3 i-adjective (`adjectives.json`)

```json
{
  "word_class": "i-adjective",
  "dict": "たかい",
  "kanji": "高い",
  "meaning": "expensive, tall",
  "description": "Drop the final い and add your ending.",
  "notes": null,
  "jlpt": "N5",
  "forms": {
    "short_pos": "たかい",       "short_neg": "たかくない",
    "short_past": "たかかった",   "short_past_neg": "たかくなかった",
    "polite_pos": "たかいです",   "polite_neg": "たかくないです",
    "polite_past": "たかかったです", "polite_past_neg": "たかくなかったです",
    "te": "たかくて",
    "adverbial": "たかく", "naru": "たかくなる", "sou": "たかそう",
    "sugiru": "たかすぎる", "sugiru_polite": "たかすぎます",
    "conditional_ba": "たかければ", "conditional_tara": "たかかったら",
    "nd_pos": "たかいんです", "nd_neg": "たかくないんです",
    "nd_past": "たかかったんです", "nd_past_neg": "たかくなかったんです",
    "nd_casual_pos": "たかいんだ", "nd_casual_neg": "たかくないんだ",
    "nd_casual_past": "たかかったんだ", "nd_casual_past_neg": "たかくなかったんだ"
  },
  "alt": {
    "polite_neg": ["たかくありません"],
    "polite_past_neg": ["たかくありませんでした"]
  },
  "examples": [{ "form": "short_past_neg", "jp": "ほんはたかくなかった。", "en": "The book wasn't expensive." }]
}
```

`いい` has `dict: "いい"`; the generator maps its stem to `よ` (よくない, よかった).

### 5.4 na-adjective

```json
{
  "word_class": "na-adjective",
  "dict": "しずか",
  "kanji": "静か",
  "meaning": "quiet",
  "description": "Use the stem with the copula: だ / です / じゃない / だった.",
  "jlpt": "N5",
  "forms": {
    "short_pos": "しずかだ", "short_neg": "しずかじゃない",
    "short_past": "しずかだった", "short_past_neg": "しずかじゃなかった",
    "polite_pos": "しずかです", "polite_neg": "しずかじゃないです",
    "polite_past": "しずかでした", "polite_past_neg": "しずかじゃなかったです",
    "te": "しずかで", "attributive": "しずかな", "adverbial": "しずかに",
    "formal_pos": "しずかである", "formal_neg": "しずかではない",
    "formal_past": "しずかであった", "formal_past_neg": "しずかではなかった",
    "sou": "しずかそう", "sugiru": "しずかすぎる", "sugiru_polite": "しずかすぎます",
    "nd_pos": "しずかなんです", "nd_neg": "しずかじゃないんです",
    "nd_past": "しずかだったんです", "nd_past_neg": "しずかじゃなかったんです",
    "nd_casual_pos": "しずかなんだ", "nd_casual_neg": "しずかじゃないんだ",
    "nd_casual_past": "しずかだったんだ", "nd_casual_past_neg": "しずかじゃなかったんだ"
  },
  "alt": {
    "polite_neg": ["しずかではありません"],
    "polite_past_neg": ["しずかではありませんでした"]
  }
}
```

### 5.5 Noun

```json
{
  "word_class": "noun",
  "dict": "がくせい",
  "kanji": "学生",
  "meaning": "student",
  "jlpt": "N5",
  "forms": {
    "short_pos": "がくせいだ", "short_neg": "がくせいじゃない",
    "short_past": "がくせいだった", "short_past_neg": "がくせいじゃなかった",
    "polite_pos": "がくせいです", "polite_neg": "がくせいじゃないです",
    "polite_past": "がくせいでした", "polite_past_neg": "がくせいじゃなかったです",
    "te": "がくせいで", "attributive": "がくせいの",
    "formal_pos": "がくせいである", "formal_neg": "がくせいではない",
    "formal_past": "がくせいであった", "formal_past_neg": "がくせいではなかった",
    "nd_pos": "がくせいなんです", "...": "nd_* as for na-adjectives"
  }
}
```

`adverbial`, `sou`, `sugiru*` are absent because the catalogue does not apply them to
nouns, not because they are missing.

## 6. Generator and files

- **`update_data.py` stays the only place forms are derived.** Internally it becomes a
  small engine plus a registry: each catalogue entry names, per applicable class, the
  rule that produces it and the forms it depends on (nd from `short_*`, auxiliaries
  from `te` and the stem). The engine resolves dependencies, applies the lemma-keyed
  exception tables, writes `forms` in catalogue order, and fails when a required form
  has no rule.
- **The catalogue is generated output.** `scripts/form_catalogue.py` declares the forms;
  the script writes `forms.json` (catalogue only, no data) into the VerbKit package
  (`Sources/VerbKit/Resources/forms.json`, bundled, not synced and not in `data/`), so
  Python is the single source and Swift never re-declares ids. `--check` covers it like
  `verbs.json` and the manifest.
- **Files.** Recommended: `adjectives.json` (i + na) and `nouns.json`, one schema, one
  optional manifest block each. They share generator rules (na and noun share the
  copula) but not a file, so the name is honest and each ships independently. Merging
  them later is only a data move. (Open question 1.)
- **Checks generalize.** Furigana coverage scans all files; the "kanji spells the kana
  `dict`" check handles okurigana (i) and none (na, noun); class-specific lemma checks
  (an i-adjective `dict` ends in い; a na-adjective such as きれい is allowed to, which
  is why the class is authored, never inferred).
- **Manifest.** Add optional `adjectives` and `nouns` blocks. Swift replaces the three
  identical manifest structs with one `FileManifest` and decodes extra blocks
  generically, so a further data file costs no new type. Each file syncs independently,
  as grammar and furigana do today.

## 7. Swift model (shape only)

- **`WordClass`**: the existing enum, promoted from `GrammarPoint.swift`; add
  `CaseIterable`.
- **`FormID`**: a `RawRepresentable` string struct (an open set, so an id from newer
  data decodes instead of failing), with static constants for the forms code names
  directly (`.shortPos`, `.masuPos`, `.te`, ...).
- **`Conjugations`**: wraps `[String: String]` with a hand-written `Codable` (see the
  gotcha in §2) and `subscript(FormID) -> String?`. Order always comes from the
  catalogue, never from the file.
- **`FormCatalogue` / `FormSpec`**: loaded from the bundled `forms.json`. `FormSpec` has
  id, facets, family, grammar link, applicable classes, `search` flag, label.
- **`Word`**: one concrete struct: `wordClass`, `dict`, `kanji`, `meaning`,
  `description`, `notes`, `jlpt`, `forms: Conjugations`, `alt`, `examples`, plus an
  optional verb-only block (`type`, `teGroup`). `Leveled` already works on it.
  `Word(verb:)` is the bridge during migration.
- **Base form** for stem/ending highlighting (`FormSplit`) is `forms[.shortPos]` for every
  class (the old `dict` coincides with it for verbs).
- **Identity** is `(wordClass, dict)`. Verb routes, widget intents and deep links keep
  the legacy `dict`-only form (open question 5).
- **Persistence**: one payload-backed `WordEntity(wordClass, id, sortOrder, payload)`,
  the `GrammarEntity` pattern. `VerbEntity` coexists for one release, then goes; the
  data is a re-fetchable cache so the "migration" is a re-sync.
- **Catalogue delivery**: bundled with the app, generated by the script into the package
  (open question 4). An unknown id in newer data is stored and ignored.

## 8. Quiz, search, widgets, detail page (data touchpoints only)

- **`QuizForm`** is built from the catalogue rows instead of `QuizForm.all` closures:
  `available(for word:, topics:)` reads `word.forms[spec.id]` for specs applicable to
  its class. `QuizTopic` becomes the catalogue's `family` (an open string with display
  titles from the catalogue); `choices(for:)` is unchanged in spirit.
- **`QuizQuestion.verb` → `word`**; `correct`, `choices` and the two kinds do not change.
  Distractors for *conjugate* come from the same form of other words **of the same
  class**; for *identify* from other forms **applicable to that class**.
- **`VerbExample.form: FormKey` → `FormID`** (JSON unchanged). The validator checks
  every example's form exists and applies to the word's class. This also lets examples
  attach to potential, んです and auxiliary forms.
- **Search** iterates catalogue specs with `search: true` (today's nine core forms),
  across all word classes.
- **Detail page** iterates `catalogue.specs(for: word.wordClass)` grouped by `family`,
  skipping forms the word lacks; the three section-specific `has*Forms` helpers go away.
- **Widgets** keep reading `forms[.masuPos]` etc.; the verb widget stays verbs-only.

## 9. Migration plan (no flag day; each step ships alone)

1. **Generator refactor, zero output change.** Introduce the catalogue and rule registry
   in `update_data.py` and make it reproduce today's `verbs.json` and `manifest.json`
   *byte for byte* (golden test: regenerate and diff is empty). Emit `forms.json`
   (unreferenced by the app). Python tests only.
2. **Swift foundations, no behaviour change.** Add `FormID`, `Conjugations`,
   `FormCatalogue`, shared `WordClass`, `Word` and `Word(verb:)`. Parity tests: for
   all verbs, every `VerbForms` field equals the catalogue lookup; the catalogue ids
   equal `QuizForm.all` ids equal `VerbForms.CodingKeys`.
3. **Quiz on the catalogue.** Replace `QuizForm.all` and `QuizTopic` internals; existing
   quiz tests must pass unchanged.
4. **Consumers.** Examples (`FormID`), search, detail-page sections. `VerbForms` stays
   only for widgets.
5. **Persistence and sync.** `FileManifest`, generic payload entity, verbs moved onto it.
6. **Adjective data, class by class.** i-adjective rules + `adjectives.json` first
   (smallest new rule set), then na-adjective and noun (copula rules + `nouns.json`).
   Each is data + generator + tests; the app needs no change per class because it
   iterates the catalogue.
7. **Grammar links.** Attachment rules reference form ids via `grammar` in the
   catalogue, so a lesson can show real conjugations for any word class.
8. **Cleanup.** Delete `VerbForms`' per-form properties, `FormKey`, and `VerbEntity`
   once nothing reads them. App-code removal only; no JSON change.

Compatibility both ways: **new app, old data**: `verbs.json` is untouched and absent
manifest blocks mean "no adjectives yet". **Old app, new data**: unknown manifest blocks
and files are ignored; `verbs.json` changes are additive only.

## 10. Testing

- Catalogue invariants: unique ids; every (class, form) pair has a rule; rule
  dependencies are acyclic; every `grammar` link exists in `grammar.json`.
- Per-class golden tables for the generator (regular, irregular, defective) and the
  byte-for-byte regeneration check from step 1.
- `Real*DataTests` per file: every applicable form present unless the lemma is in the
  defective table; no empty strings; `alt` never equals the canonical form; every
  example's form applies to its class.
- Swift parity tests in step 2 and a `Conjugations` Codable round-trip.

## 11. Risks

- **Generator complexity**: three rule sets in one script. Mitigate with the golden test
  in step 1 and per-class tables before any data is added.
- **Stringly typing**: mitigated by the catalogue and tests, not by the compiler. Keep
  `FormID` constants few and parity-tested.
- **Polite negative variants** can confuse quiz scoring unless alts are handled in one
  place.
- **Nouns are unbounded**: without an inclusion rule the file becomes a dictionary.
- **Word-class mistakes** (きれい, ゆうめい are na-adjectives that look like i or noun):
  a wrong class generates wrong forms silently; the review process must cover it.

## 12. Open questions for the maintainer

1. **File layout:** `adjectives.json` + `nouns.json` (recommended), one file with an
   honest name (`words.json`), or `adjectives.json` holding all three as originally
   planned?
2. **Polite ids:** `masu_*` for verbs and `polite_*` for the rest, tied by `concept`
   (recommended; keeps `verbs.json` untouched), or add `polite_*` aliases to verbs?
3. **Alternates:** is `じゃないです` or `ではありません` canonical for the polite negative?
   Is an `alt` object acceptable, or should the quiz accept only one string?
4. **Catalogue delivery:** bundled with the app (recommended: forms need app code to be
   useful) or synced like data?
5. **Identity:** keep verb deep links and widget intents on `dict`, adding a class segment
   only for new classes (recommended), or one compound id everywhere?
6. **Scope of copula forms:** are `attributive` (な/の), `adverbial` (に) and the
   `formal_*` (である) family in scope as "conjugations", or only the です/だ table?
7. **Noun inclusion rule:** which nouns qualify (JLPT-listed? only copula-practice
   nouns)?
8. **Which stored `label`:** new files derive it; should verbs stop storing it too
   (later, additively)?
9. **Dead reserved verb forms:** drop them from the Swift model now (recommended) or
   keep them as planned catalogue entries?
10. **Quiz mixing:** one quiz over mixed word classes, or a class picker before the
    topic sheet?
11. **Constraint check:** this spec assumes `verbs.json` stays additive-only and that old
    app builds must keep working. Earlier discussion assumed no users; if that is still
    true, step 5 can drop the coexistence release and re-sync directly.
