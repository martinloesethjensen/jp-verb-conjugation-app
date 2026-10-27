# Review site, plan 2: schemas and the signed-in skeleton

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One JSON Schema per published data file, enforced by `update_data.py`, and a deployable review site skeleton: a Rust Worker that verifies Cloudflare Access on every request and knows who is an admin or a reviewer, a D1 database for users and the audit log, a Svelte shell where the owner manages reviewers, CI, and the owner's Cloudflare setup guide.

**Architecture:** `schema/*.schema.json` (JSON Schema 2020-12, a small subset) describe `data/` and are checked by a stdlib validator in `scripts/`. `review/api` is one Rust crate: pure modules (`access`, `auth`, `store`, `app`) that build and test natively, and a thin `wasm32`-only layer (`worker_glue`, `d1`) that wires them to workers-rs, D1 and `fetch`. `review/web` is SvelteKit with the static adapter, served by Cloudflare Pages on the same hostname; the Worker is routed at `/api/*`.

**Tech Stack:** Python 3 stdlib; Rust stable with `worker` 0.8.7, `rsa` 0.9, `sha2` 0.10, `base64` 0.22, `serde`/`serde_json` 1, dev-only `rusqlite` 0.41 (bundled) and `rand` 0.8; `worker-build` 0.8.7; Svelte 5.57, SvelteKit 3.1, `@sveltejs/adapter-static` 4.0, Vitest 5, `wrangler` 4.154.0; Cloudflare Access, Pages, Workers, D1.

**Spec:** `docs/superpowers/specs/2026-10-27-data-review-site-design.md` (Architecture, Authentication and authorisation 1–8, D1 tables, The site → Look). Plan 1 (`2026-10-27-review-site-1-stable-ids.md`) is merged.

## Roadmap (updated)

Plan 1's roadmap put the skeleton and the read path in one plan. This plan splits them (*ruling*: each half is a reviewable, deployable step, and the read path needs the schema's serde mirror, which is easier to test once the schemas exist):

1. Stable ids (merged, #181).
2. **This plan:** schemas, auth, roles, D1 users and audit log, Svelte shell, reviewer management, CI, Cloudflare setup.
3. Read path: serde types mirrored from the schemas (tested against them and the shared fixtures), snapshot import with Ed25519 manifest check, `items` table, browse and item pages with furigana.
4. Review path. 5. Add path. 6. Export. 7. Stamps for verbs, words and examples.

## Global Constraints

- The repo is public. No secrets, account ids, AUD tags, team domains or reviewer emails in committed files. Worker settings that identify the account are `wrangler secret put` values; the D1 `database_id` in `wrangler.toml` is allowed (Cloudflare documents it as non-secret).
- Nothing in this plan changes `data/`. No signing; agents never run `make sign-commit`.
- The Worker has **no** authentication bypass of any kind, including for local development. Local UI work uses the Vite dev mock (Task 7); Worker logic is tested natively.
- Every `/api/*` request: verify the Access JWT (RS256, `kid` from the team certs, `aud` contains the expected tag, `iss` = `https://<team domain>`, `exp` in the future, `nbf`/`iat` not more than 60 s in the future), then look up the lowercased `email` claim in D1 `users` with `active = 1`. Never read `Cf-Access-Authenticated-User-Email` or any other identity header.
- `/api/admin/*` additionally requires the token's `aud` to contain the **admin** application's tag (`ACCESS_ADMIN_AUD`) and the D1 role `admin`. Every other `/api/*` route accepts the reviewer application's tag (`ACCESS_AUD`) or the admin one.
- A token without a non-empty `email` claim (an Access service token) is 403 on every route in this plan.
- Status codes: no or invalid token 401; valid token but unknown, inactive or wrong role 403; failed `Origin` check 403; unknown path 404 (only after authentication); wrong method 405; bad body 400; conflict 409.
- Any request whose method is not `GET` or `HEAD` must carry `Origin` exactly equal to `SITE_ORIGIN` (`https://review.martinloeseth.dev`).
- Roles in D1: `admin`, `reviewer`. The API can only create `reviewer` rows; the single admin row is inserted by the owner from the command line (Task 8).
- Look: paper `#F6F7F4`, card `#FFFFFF`, ink `#1E2633`, muted `#7C8390`, genkō grid `#B9CBB8`, rule `#DCE0D8`, red `#C2372B` (red only where a reviewer has acted; unused in this plan). Shippori Mincho for Japanese, Zen Kaku Gothic New for everything else. Sentence case, no all-caps labels. Responsive: one column under 720 px.
- No third-party scripts. Fonts from Google Fonts only.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

- A token signed with `alg: "none"` or `HS256` (using the public key bytes as the secret): rejected with 401 before any key lookup. Test in Task 3.
- The owner opens `/api/admin/users` with a **reviewer**-application token (email PIN path, not GitHub): 403 even though the D1 role is admin, so the passkey policy can't be skipped. Test in Task 6.
- Email case: Access sends `Martin@Example.com`, the row was added as `martin@example.com` (or the other way round): same user. Test in Task 4.
- Access rotates its signing key: a token with an unknown `kid` triggers one certs refetch; a flood of unknown `kid`s refetches at most once per 60 s. Test in Task 3.
- `update_data.py` adds a generated field the schema doesn't list: `make data` fails naming the file and JSON path, instead of the site later rejecting real data. Test in Task 2.

---

### Task 1: A small JSON Schema validator (`scripts/json_schema.py`)

**Files:**
- Create: `scripts/json_schema.py`
- Test: `scripts/test_json_schema.py`

**Interfaces:**
- Produces:
  - `SUPPORTED: frozenset[str]`: the keywords below.
  - `check_schema(schema: dict) -> list[str]`: problems with the schema itself; any keyword outside `SUPPORTED` (at any depth, including inside `$defs`, `properties` values, `items`, `additionalProperties`, `patternProperties` values, `propertyNames`) is reported as `"<schema path>: unsupported keyword '<k>'"`.
  - `validate(instance, schema: dict) -> list[str]`: problems, each `"<json path>: <message>"`, path rooted at `$` (`$.verbs[3].examples[0].id`). Never raises for bad instances.

Supported keywords: `$schema`, `$id`, `$defs`, `$ref` (local `#/$defs/<name>` only), `title`, `description`, `type` (string or list of `string`, `integer`, `number`, `boolean`, `object`, `array`, `null`), `enum`, `const`, `pattern`, `minLength`, `minimum`, `required`, `properties`, `additionalProperties` (bool or schema), `patternProperties`, `propertyNames`, `items`, `minItems`, `uniqueItems`.

Messages (exact): `missing required property 'jp'`, `unexpected property 'foo'`, `expected string, got integer` (type names as in JSON Schema; with a list, `expected string or null, got integer`), `'N6' is not one of ['N5', 'N4', 'N3', 'N2', 'N1']`, `'ABC' does not match ^[a-km-np-z2-9]{6}$`, `property name 'x y' does not match ^[a-z_]+$`, `expected at least 1 item(s)`, `items are not unique`, `shorter than 1 character(s)`, `less than 0`.

- [ ] **Step 1: Write the failing tests** in `scripts/test_json_schema.py` (`unittest`, like the other script tests):

```python
SCHEMA = {
    "$defs": {"id": {"type": "string", "pattern": "^[a-km-np-z2-9]{6}$"}},
    "type": "object", "required": ["items"], "additionalProperties": False,
    "properties": {
        "level": {"enum": ["N5", "N4", "N3", "N2", "N1"]},
        "kanji": {"type": ["string", "null"]},
        "count": {"type": "integer", "minimum": 0},
        "forms": {"type": "object", "propertyNames": {"pattern": "^[a-z_]+$"},
                  "additionalProperties": {"type": "string", "minLength": 1}},
        "items": {"type": "array", "minItems": 1, "uniqueItems": True,
                  "items": {"type": "object", "required": ["id", "jp"], "additionalProperties": False,
                            "properties": {"id": {"$ref": "#/$defs/id"}, "jp": {"type": "string"}}}},
    },
}

def test_a_valid_instance_has_no_problems(self):
    doc = {"level": "N5", "kanji": None, "count": 0, "forms": {"te": "して"}, "items": [{"id": "abcdef", "jp": "a"}]}
    self.assertEqual(json_schema.validate(doc, SCHEMA), [])

def test_problems_name_the_json_path(self):
    doc = {"level": "N6", "items": [{"id": "ABC"}, {"id": "abcdef", "jp": "b", "x": 1}], "extra": True}
    self.assertEqual(sorted(json_schema.validate(doc, SCHEMA)), sorted([
        "$.level: 'N6' is not one of ['N5', 'N4', 'N3', 'N2', 'N1']",
        "$.items[0].id: 'ABC' does not match ^[a-km-np-z2-9]{6}$",
        "$.items[0]: missing required property 'jp'",
        "$.items[1]: unexpected property 'x'",
        "$: unexpected property 'extra'",
    ]))

def test_a_boolean_is_not_an_integer(self):
    self.assertEqual(json_schema.validate({"count": True, "items": [{"id": "abcdef", "jp": "a"}]}, SCHEMA),
                     ["$.count: expected integer, got boolean"])

def test_type_lists_name_every_type(self):
    self.assertIn("$.kanji: expected string or null, got integer",
                  json_schema.validate({"kanji": 3, "items": [{"id": "abcdef", "jp": "a"}]}, SCHEMA))

def test_map_keys_and_values_are_checked(self):
    problems = json_schema.validate({"forms": {"x y": ""}, "items": [{"id": "abcdef", "jp": "a"}]}, SCHEMA)
    self.assertIn("$.forms: property name 'x y' does not match ^[a-z_]+$", problems)
    self.assertIn("$.forms['x y']: shorter than 1 character(s)", problems)

def test_array_rules(self):
    self.assertIn("$.items: expected at least 1 item(s)", json_schema.validate({"items": []}, SCHEMA))
    dup = {"id": "abcdef", "jp": "a"}
    self.assertIn("$.items: items are not unique", json_schema.validate({"items": [dup, dup]}, SCHEMA))

def test_unsupported_keywords_are_reported_at_any_depth(self):
    self.assertEqual(json_schema.check_schema({"properties": {"a": {"oneOf": []}}, "$defs": {"b": {"format": "date"}}}),
                     ["$.properties.a: unsupported keyword 'oneOf'", "$.$defs.b: unsupported keyword 'format'"])
    self.assertEqual(json_schema.check_schema(SCHEMA), [])

def test_only_local_refs_are_allowed(self):
    self.assertEqual(json_schema.check_schema({"$ref": "https://example.com/x.json"}),
                     ["$: only '#/$defs/<name>' refs are supported"])
```

Paths: object members as `.name` when the name matches `^[A-Za-z_][A-Za-z0-9_]*$`, otherwise `['name']` (`$.forms['x y']`, `$.readings['一日']`).

- [ ] **Step 2: Run to verify they fail**

Run: `python3 -m unittest scripts/test_json_schema.py -v` (from the repo root; the other script tests use `discover -s scripts`, so also fine: `python3 -m unittest discover -s scripts -p 'test_json_schema.py' -v`)
Expected: FAIL / ERROR, `No module named 'json_schema'`.

- [ ] **Step 3: Implement `scripts/json_schema.py`** with the three names above. Module docstring says why it exists: `update_data.py` stays stdlib-only, and the schemas use only this subset so every client (Rust now, Kotlin later) can rely on the same small set. `pattern` uses `re.search` (JSON Schema semantics: patterns are not anchored unless they say so; every pattern in `schema/` is written anchored).

- [ ] **Step 4: Run to verify they pass**

Run: `python3 -m unittest discover -s scripts -p 'test_json_schema.py' -v`
Expected: 8 tests, OK.

- [ ] **Step 5: Commit**

```bash
git add scripts/json_schema.py scripts/test_json_schema.py
git commit -m "scripts: a stdlib validator for the JSON Schema subset the data schemas use"
```

---

### Task 2: A schema per data file, checked by `update_data.py`

**Files:**
- Create: `schema/verbs.schema.json`, `schema/words.schema.json`, `schema/counters.schema.json`, `schema/grammar.schema.json`, `schema/furigana.schema.json`, `schema/forms.schema.json`, `schema/README.md`
- Create: `schema/fixtures/invalid.json`
- Modify: `scripts/update_data.py` (in `run()`, after the stable-id checks)
- Modify: `.github/workflows/data.yml` (add `"schema/**"` to both `paths` lists)
- Test: `scripts/test_schemas.py`; extend `scripts/test_update_data.py`

**Interfaces:**
- Consumes: `json_schema.validate`, `json_schema.check_schema` (Task 1); `stable_ids.ID_PATTERN`, `stable_ids.id_slots`, `stable_ids.loads` (plan 1); `update_data.REVIEWERS`.
- Produces:
  - `schema/<name>.schema.json` for `name` in `verbs, words, counters, grammar, furigana, forms`. Each has `"$schema": "https://json-schema.org/draft/2020-12/schema"`, `"$id": "https://raw.githubusercontent.com/martinloesethjensen/jp-verb-conjugation-app/main/schema/<name>.schema.json"`, a `title`, and `$defs` for every reused shape. The same `$defs` names in every file that has them: `stableId`, `jlpt`, `example`, `reviewStamp`.
  - `schema/fixtures/invalid.json`: a list of `{"name": str, "dataset": str, "doc": <whole small document>, "error": str}`; `error` is a substring of the expected message. Plan 3's Rust tests read the same file.
  - `update_data.SCHEMA_DIR: Path` and `update_data.check_schemas(docs: dict[str, dict]) -> list[str]`, problems as `"<name>.json: <json path>: <message>"`.

**How to write the schemas.** Each schema describes exactly what is in `data/` today after `make data`, and is no looser than that:
- `additionalProperties: false` on every object with fixed keys. Objects keyed by data (verb and word `forms`, counter `overrides`, `readings`, `distractors`, `compound`, example `readings`, furigana `readings`) use `propertyNames` with a pattern taken from the current keys plus an `additionalProperties` schema for the values.
- `required` lists every key present on every instance today; keys present on only some instances are optional.
- `enum`s (the values seen today, plus the full JLPT range): `jlpt` `["N5","N4","N3","N2","N1"]`; verb `type` `["ru","u","irr."]`, `label` `["Ru-verb","U-verb","Irregular"]`, `teGroup` `["ide","ite","nde","shite","tte"]`; word `class` `["i-adjective","na-adjective","noun"]`; counter `sound` `["h-b","h-p","irregular","k","plain","s"]`, thing `fit` `["primary","casual","acceptable"]`; grammar attachment `word_class` and forms `applies_to` items `["verb","i-adjective","na-adjective","noun"]`, conjugation `register` `["casual","formal","polite"]`; forms `role` `["connective","derived","finite"]`, `source` `["authored","derived"]`, `register` `["casual","polite","short"]`, `polarity` `["neg","pos"]`, `tense` `["past","present"]`.
- `stableId`: `{"type": "string", "pattern": "^[a-km-np-z2-9]{6}$"}`, and `"id": {"$ref": "#/$defs/stableId"}` is required on every object `stable_ids.id_slots` returns.
- `reviewStamp` (counters and grammar points, optional `review` key): object, `required: ["by","on","sha256"]`, `by` enum equal to `update_data.REVIEWERS`, `on` pattern `^\d{4}-\d{2}-\d{2}$`, `sha256` pattern `^[0-9a-f]{64}$`, no other keys.
- To see what is there, print the key inventory (not committed):
  `python3 -c "import json,collections,sys; …"` walking each file and printing every path, its JSON types, how many instances have it, and the distinct values when there are 8 or fewer.

- [ ] **Step 1: Write the failing tests** in `scripts/test_schemas.py`:

```python
NAMES = ("verbs", "words", "counters", "grammar", "furigana", "forms")

def test_every_schema_uses_only_the_supported_subset(self):
    for name in NAMES:
        with self.subTest(name):
            self.assertEqual(json_schema.check_schema(load_schema(name)), [])

def test_the_published_data_matches_its_schema(self):
    for name in NAMES:
        with self.subTest(name):
            self.assertEqual(json_schema.validate(load_data(name), load_schema(name)), [])

def test_the_stable_id_pattern_is_the_one_the_pipeline_uses(self):
    for name in ("verbs", "counters", "grammar"):
        self.assertEqual(load_schema(name)["$defs"]["stableId"]["pattern"], stable_ids.ID_PATTERN.pattern)

def test_review_stamp_reviewers_match_the_pipeline(self):
    for name in ("counters", "grammar"):
        self.assertEqual(load_schema(name)["$defs"]["reviewStamp"]["properties"]["by"]["enum"],
                         list(update_data.REVIEWERS))

def test_every_kind_of_stable_id_slot_is_required_by_the_schema(self):
    # For the first slot of each kind ("example", "thing", "usage", "pitfall", "pitfall … example",
    # "contrast … example", …), removing its id from a copy of the real data makes the schema fail.
    for name in ("verbs", "counters", "grammar"):
        doc = load_data(name)
        for kind, label in first_slot_of_each_kind(name, doc):
            with self.subTest(name=name, slot=label):
                broken = copy.deepcopy(doc)
                dict(stable_ids.id_slots(name, broken))[label].pop("id")
                self.assertTrue(any("missing required property 'id'" in p
                                    for p in json_schema.validate(broken, load_schema(name))))

def test_the_shared_invalid_fixtures_are_rejected_for_the_stated_reason(self):
    fixtures = json.loads((SCHEMA_DIR / "fixtures" / "invalid.json").read_text(encoding="utf-8"))
    self.assertGreaterEqual(len(fixtures), 10)
    for fixture in fixtures:
        with self.subTest(fixture["name"]):
            problems = json_schema.validate(fixture["doc"], load_schema(fixture["dataset"]))
            self.assertTrue(any(fixture["error"] in p for p in problems), problems)
```

`first_slot_of_each_kind` groups `id_slots` labels by the label with its numbers and the parent id removed (`"たべる example 1"` → `"example"`, `"n-desu usage 1 example 2"` → `"usage example"`) and returns the first of each. `load_data` uses `stable_ids.loads`.

The fixtures (`schema/fixtures/invalid.json`), each a minimal otherwise-valid document: a verb example without `id`; a verb with an unknown property `"romaji"`; a verb with `"jlpt": "N6"`; a verb with `"kanji": 3`; a word with `"class": "adverb"`; a counter thing with `"fit": "maybe"`; a counter with a `review` stamp whose `by` is `"friend"`; a grammar usage with `"id": "ABC"`; a grammar contrast example without `id`; a furigana reading whose value is a number; a forms entry with `"role": "other"`. Write each document's other fields by copying a real entry and trimming it to one item.

Extend `scripts/test_update_data.py`:

```python
def test_run_fails_when_data_does_not_match_its_schema(self):
    # Same harness as the existing run() failure tests: a temp data dir from the real files,
    # then one verb gets an unknown key.
    ...
    self.assertIn("verbs.json does not match schema/verbs.schema.json:", output)
    self.assertIn("$.verbs[0]: unexpected property 'romaji'", output)

def test_check_schemas_reports_every_file(self):
    docs = {name: load_real(name) for name in NAMES}
    docs["words"]["words"][0]["class"] = "adverb"
    self.assertEqual(update_data.check_schemas(docs),
                     ["words.json: $.words[0].class: 'adverb' is not one of ['i-adjective', 'na-adjective', 'noun']"])
```

- [ ] **Step 2: Run to verify they fail**

Run: `python3 -m unittest discover -s scripts -p 'test_schemas.py' -v; python3 -m unittest discover -s scripts -p 'test_update_data.py' -k schema -v`
Expected: FAIL / ERROR on missing schema files and missing `check_schemas`.

- [ ] **Step 3: Write the six schemas and the fixtures** following "How to write the schemas".

- [ ] **Step 4: Run `test_schemas.py`**

Run: `python3 -m unittest discover -s scripts -p 'test_schemas.py' -v`
Expected: 6 tests, OK. A failure on the real data means the schema is wrong, not the data: fix the schema.

- [ ] **Step 5: Add `SCHEMA_DIR` and `check_schemas` to `update_data.py`** and call it in `run()` on the documents as they will be written (after generation), for both normal runs and `--check`, failing with the heading `"<name>.json does not match schema/<name>.schema.json:"` followed by its problems, the same way the stable-id failure is printed. `SCHEMA_DIR` is `ROOT / "schema"`, overridable the same way the data dir is in tests.

- [ ] **Step 6: Write `schema/README.md`**: what the files are, that `update_data.py` enforces them, that they use only the subset in `scripts/json_schema.py` (list it), that clients (the review site now, Android later) treat them as the contract, and that a data shape change means editing the schema in the same PR. Add `"schema/**"` to both `paths` lists in `.github/workflows/data.yml`.

- [ ] **Step 7: Run the whole Python suite and the data check**

Run: `make test-py && make data-check`
Expected: all tests OK; `data-check` passes with no data changes (`git status --short data/` empty).

- [ ] **Step 8: Commit**

```bash
git add schema scripts/update_data.py scripts/test_schemas.py scripts/test_update_data.py .github/workflows/data.yml
git commit -m "schema: a JSON Schema per data file, enforced by update_data.py"
```

---

### Task 3: Access JWT verification (`review/api/src/access.rs`)

**Files:**
- Create: `review/api/Cargo.toml`, `review/api/src/lib.rs`, `review/api/src/access.rs`, `review/api/.gitignore` (`target/`, `build/`, `node_modules/`, `.wrangler/`, `.dev.vars`)
- Test: `review/api/tests/access.rs`, `review/api/tests/support/mod.rs`

**Interfaces:**
- Produces (all `pub`, native and wasm):
  - `struct AccessConfig { team_domain: String, aud: String, admin_aud: String }`; `issuer()` returns `format!("https://{team_domain}")`; `certs_url()` returns `format!("https://{team_domain}/cdn-cgi/access/certs")`.
  - `struct Jwk { kid: String, n: String, e: String }` (base64url fields, as in the certs response `keys` array) and `parse_certs(body: &str) -> Result<Vec<Jwk>, AccessError>`.
  - `struct Claims { email: Option<String>, aud: Vec<String>, iss: String, exp: i64, nbf: Option<i64>, iat: Option<i64> }` (`aud` accepts a string or an array).
  - `enum Audience { Reviewer, Admin }`; `Claims::audience(&self, cfg: &AccessConfig) -> Option<Audience>`: `Admin` when `aud` contains `admin_aud`, else `Reviewer` when it contains `aud`, else `None`.
  - `fn token_kid(token: &str) -> Result<String, AccessError>`: the header's `kid`, after checking `alg == "RS256"` and `typ`, if present, is `"JWT"`.
  - `fn verify(token: &str, keys: &[Jwk], cfg: &AccessConfig, now: i64) -> Result<(Claims, Audience), AccessError>`.
  - `enum AccessError { Malformed, Algorithm, UnknownKey, Signature, Expired, NotYetValid, Issuer, Audience }` (derive `Debug, PartialEq`).
  - `struct KeyCache { keys: Vec<Jwk>, fetched_at: Option<i64> }` with `fn needs_fetch(&self, kid: &str, now: i64) -> bool`: true when never fetched, older than 3600 s, or `kid` is unknown and the last fetch is at least 60 s old; and `fn store(&mut self, keys: Vec<Jwk>, now: i64)`.
- Crate setup: `[lib] crate-type = ["cdylib", "rlib"]`; dependencies `serde` (derive), `serde_json`, `base64 = "0.22"`, `rsa = "0.9"`, `sha2 = "0.10"`; `[target.'cfg(target_arch = "wasm32")'.dependencies] worker = { version = "0.8.7", features = ["d1"] }`; dev-dependencies `rsa` with its default features, `rand = "0.8"`, `rusqlite = { version = "0.41", features = ["bundled"] }`, `tokio = { version = "1", features = ["macros", "rt"] }`. `[profile.dev.package.num-bigint-dig] opt-level = 3` so test key generation is fast. Commit `Cargo.lock`.

- [ ] **Step 1: Write the test support and failing tests.** `tests/support/mod.rs` generates one 2048-bit RSA key per test binary (`OnceLock`), exposes it as a `Jwk` with `kid "k1"`, a `cfg()` with `team_domain "team.cloudflareaccess.com"`, `aud "reviewer-aud"`, `admin_aud "admin-aud"`, and `fn token(header: serde_json::Value, claims: serde_json::Value) -> String` that signs RS256 (PKCS#1 v1.5, SHA-256) with that key, plus `fn token_with_alg(alg, claims)` that produces an unsigned (`none`) or HS256 (HMAC with the public key's DER bytes as secret) token. `NOW = 1_800_000_000`.

`tests/access.rs`:

```rust
fn good_claims() -> Value { json!({"email": "a@example.com", "aud": ["reviewer-aud"],
    "iss": "https://team.cloudflareaccess.com", "exp": NOW + 600, "iat": NOW - 5, "nbf": NOW - 5}) }

#[test] fn a_good_reviewer_token_verifies() {
    let (claims, aud) = verify(&token(rs_header(), good_claims()), &[jwk()], &cfg(), NOW).unwrap();
    assert_eq!(claims.email.as_deref(), Some("a@example.com"));
    assert_eq!(aud, Audience::Reviewer);
}
#[test] fn an_admin_token_has_the_admin_audience() { /* aud: "admin-aud" as a plain string */ assert_eq!(aud, Audience::Admin); }
#[test] fn none_and_hs256_are_rejected() {
    assert_eq!(verify(&token_with_alg("none", good_claims()), &[jwk()], &cfg(), NOW), Err(AccessError::Algorithm));
    assert_eq!(verify(&token_with_alg("HS256", good_claims()), &[jwk()], &cfg(), NOW), Err(AccessError::Algorithm));
}
#[test] fn a_tampered_payload_fails_the_signature() { /* swap the payload segment for one with another email */ Err(AccessError::Signature) }
#[test] fn an_unknown_kid_is_unknown_key() { /* header kid "k2" */ Err(AccessError::UnknownKey) }
#[test] fn expired_tokens_are_rejected() { /* exp: NOW - 1 */ Err(AccessError::Expired) }
#[test] fn future_tokens_beyond_60s_are_rejected() { /* nbf: NOW + 61 → NotYetValid; nbf: NOW + 60 → Ok */ }
#[test] fn wrong_issuer_is_rejected() { /* iss "https://evil.cloudflareaccess.com" */ Err(AccessError::Issuer) }
#[test] fn wrong_audience_is_rejected() { /* aud ["other"] */ Err(AccessError::Audience) }
#[test] fn garbage_is_malformed() { for t in ["", "a.b", "a.b.c", "!!.!!.!!"] { assert_eq!(verify(t, ...), Err(AccessError::Malformed)) } }
#[test] fn a_service_token_verifies_without_an_email() { /* claims without email, with common_name */ assert_eq!(claims.email, None); }
#[test] fn certs_are_parsed() { /* parse_certs on {"keys":[{"kid":"k1","kty":"RSA","alg":"RS256","use":"sig","e":"AQAB","n":"…"}],"public_cert":{…},"public_certs":[…]} */ }
#[test] fn the_key_cache_refetches_sparingly() {
    let mut cache = KeyCache::default();
    assert!(cache.needs_fetch("k1", NOW));
    cache.store(vec![jwk()], NOW);
    assert!(!cache.needs_fetch("k1", NOW + 10));
    assert!(!cache.needs_fetch("k9", NOW + 59));   // unknown kid, but fetched under 60 s ago
    assert!(cache.needs_fetch("k9", NOW + 60));
    assert!(cache.needs_fetch("k1", NOW + 3600));  // stale
}
```

Checks run in this order, so the error names the first problem: shape → algorithm → key → signature → `exp` → `nbf`/`iat` → issuer → audience.

- [ ] **Step 2: Run to verify they fail**

Run: `cd review/api && cargo test --test access`
Expected: compile errors for the missing `access` items.

- [ ] **Step 3: Implement `access.rs`** with `rsa::pkcs1v15::VerifyingKey<Sha256>` over the ASCII bytes `header.payload`, base64url without padding (`URL_SAFE_NO_PAD`). `lib.rs` declares `pub mod access;` (the wasm-only modules come in Task 6).

- [ ] **Step 4: Run to verify they pass**

Run: `cd review/api && cargo test --test access && cargo clippy --all-targets -- -D warnings && cargo fmt --check`
Expected: 13 tests pass, no clippy warnings, formatting clean.

- [ ] **Step 5: Commit**

```bash
git add review/api
git commit -m "review/api: verify Cloudflare Access tokens"
```

---

### Task 4: Users, roles and the audit log (`auth.rs`, `store.rs`, migration 0001)

**Files:**
- Create: `review/api/migrations/0001_users_and_audit.sql`, `review/api/src/auth.rs`, `review/api/src/store.rs`
- Test: `review/api/tests/store.rs`, `review/api/tests/support/sqlite.rs` (a `SqliteStore` used by Tasks 4 and 5)

**Interfaces:**
- Consumes: `Claims`, `Audience` (Task 3).
- Produces:
  - Migration `0001_users_and_audit.sql`:
    - `users(email TEXT PRIMARY KEY CHECK (email = lower(email)), display_name TEXT NOT NULL, role TEXT NOT NULL CHECK (role IN ('admin','reviewer')), active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0,1)), created_at TEXT NOT NULL)`
    - `audit_log(id INTEGER PRIMARY KEY AUTOINCREMENT, at TEXT NOT NULL, actor TEXT NOT NULL, action TEXT NOT NULL, target TEXT NOT NULL, detail TEXT NOT NULL DEFAULT '')`, plus triggers `audit_log_no_update` and `audit_log_no_delete` that `RAISE(ABORT, 'audit_log is insert-only')`.
  - `store.rs`: `enum Role { Admin, Reviewer }` (serde lowercase), `struct User { email: String, display_name: String, role: Role, active: bool }` (serde), `struct NewUser { email, display_name, role }`, `enum StoreError { Conflict, NotFound, Backend(String) }`, and

    ```rust
    #[allow(async_fn_in_trait)]
    pub trait Store {
        async fn user(&self, email: &str) -> Result<Option<User>, StoreError>;
        async fn users(&self) -> Result<Vec<User>, StoreError>;          // ordered by display_name, then email
        async fn add_user(&self, user: &NewUser, actor: &str, now: &str) -> Result<(), StoreError>;
        async fn set_active(&self, email: &str, active: bool, actor: &str, now: &str) -> Result<(), StoreError>;
    }
    ```
    The SQL lives once, as `pub const` strings in `store.rs` (`SELECT_USER`, `SELECT_USERS`, `INSERT_USER`, `UPDATE_ACTIVE`, `INSERT_AUDIT`), used by both the D1 and the SQLite implementation. `add_user` and `set_active` write their audit row (`user.add` / `user.active`, target the email, detail `role=reviewer` / `active=0|1`) in the same batch as the change.
  - `auth.rs`: `pub fn normalize_email(raw: &str) -> Option<String>` (trim, lowercase; `None` unless exactly one `@` with text on both sides, no whitespace, at most 254 chars); `enum Need { Reviewer, Admin }`; `struct Principal { email: String, display_name: String, role: Role }`; `enum Denied { Unauthenticated, Forbidden }`; and

    ```rust
    pub async fn authorize<S: Store>(claims: &Claims, audience: Audience, need: Need, store: &S)
        -> Result<Principal, Denied>
    ```
    Forbidden when: no email (service token), unknown or inactive user, `Need::Admin` with `audience != Audience::Admin`, `Need::Admin` with a role other than `Admin`. A store error is `Forbidden` too (fail closed).

- [ ] **Step 1: Write the failing tests** (`tests/store.rs`, async with `#[tokio::test(flavor = "current_thread")]`; `SqliteStore::new()` opens an in-memory DB and runs every file in `migrations/` in name order):

```rust
#[tokio::test] async fn users_round_trip_and_emails_are_lowercased_by_the_caller() {
    let s = SqliteStore::new();
    s.add_user(&new("aiko@example.com", "Aiko"), "owner@example.com", T0).await.unwrap();
    assert_eq!(s.user("aiko@example.com").await.unwrap().unwrap().display_name, "Aiko");
    assert_eq!(normalize_email("  Aiko@Example.COM "), Some("aiko@example.com".into()));
}
#[tokio::test] async fn the_database_refuses_mixed_case_emails() { /* raw INSERT with "A@x.com" fails the CHECK */ }
#[tokio::test] async fn adding_twice_is_a_conflict() { Err(StoreError::Conflict) }
#[tokio::test] async fn set_active_on_an_unknown_user_is_not_found() { Err(StoreError::NotFound) }
#[tokio::test] async fn changes_write_audit_rows() { /* after add + set_active(false): two rows, actions user.add and user.active, detail "active=0" */ }
#[tokio::test] async fn the_audit_log_is_insert_only() { /* raw UPDATE and DELETE both fail with "audit_log is insert-only" */ }
#[test] fn bad_emails_are_rejected() { for e in ["", "a", "a@", "@b", "a@b@c", "a b@c", &"x".repeat(250) + "@b.c"] { assert_eq!(normalize_email(e), None) } }

// authorize, with an admin row "owner@example.com", an active reviewer "aiko@example.com",
// an inactive reviewer "ken@example.com":
#[tokio::test] async fn a_reviewer_may_use_reviewer_routes() { Ok(Principal { role: Role::Reviewer, .. }) }
#[tokio::test] async fn the_email_claim_is_matched_case_insensitively() { /* claims.email "Aiko@Example.com" → Ok */ }
#[tokio::test] async fn unknown_and_inactive_users_are_forbidden() { Err(Denied::Forbidden) ×2 }
#[tokio::test] async fn a_service_token_is_forbidden() { /* email None */ Err(Denied::Forbidden) }
#[tokio::test] async fn admin_routes_need_the_admin_audience_and_role() {
    // owner + Audience::Admin + Need::Admin → Ok
    // owner + Audience::Reviewer + Need::Admin → Forbidden   (email PIN can't reach admin)
    // aiko + Audience::Admin + Need::Admin → Forbidden        (role)
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd review/api && cargo test --test store`
Expected: compile errors for missing `store`/`auth` items.

- [ ] **Step 3: Write the migration, `store.rs`, `auth.rs`, and `tests/support/sqlite.rs`** (`SqliteStore` wraps a `rusqlite::Connection` in a `RefCell`, maps a primary-key violation to `Conflict` and zero changed rows in `UPDATE_ACTIVE` to `NotFound`; it runs the change and its audit row in one transaction).

- [ ] **Step 4: Run to verify they pass**

Run: `cd review/api && cargo test && cargo clippy --all-targets -- -D warnings && cargo fmt --check`
Expected: all tests pass (access and store), clean.

- [ ] **Step 5: Commit**

```bash
git add review/api
git commit -m "review/api: users, roles and an insert-only audit log"
```

---

### Task 5: The API (`app.rs`)

**Files:**
- Create: `review/api/src/app.rs`
- Test: `review/api/tests/app.rs`

**Interfaces:**
- Consumes: `AccessConfig`, `verify`, `Jwk`, `Audience` (Task 3); `authorize`, `Need`, `normalize_email`, `Store`, `NewUser`, `Role`, `StoreError` (Task 4).
- Produces:
  - `struct ApiRequest { method: String, path: String, origin: Option<String>, jwt: Option<String>, body: Vec<u8> }` and `struct ApiResponse { status: u16, body: serde_json::Value }`. Every response body is JSON; errors are `{"error": "<message>"}`.
  - `struct AppConfig { access: AccessConfig, site_origin: String }`.
  - `pub async fn handle<S: Store>(req: ApiRequest, cfg: &AppConfig, keys: &[Jwk], store: &S, now: i64, today: &str) -> ApiResponse` (`now` epoch seconds for the JWT, `today` an RFC 3339 timestamp for rows).
  - Routes (the table is the single place a route's `Need` is declared; anything not in it is 404 after authentication):

    | Method, path | Need | Success |
    |---|---|---|
    | `GET /api/me` | Reviewer | 200 `{"email","display_name","role"}` |
    | `GET /api/admin/users` | Admin | 200 `{"users":[{"email","display_name","role","active"}]}` |
    | `POST /api/admin/users` body `{"email","display_name"}` | Admin | 201 the new user; role is always `reviewer` |
    | `POST /api/admin/users/active` body `{"email","active"}` | Admin | 200 the updated user |

    Order of checks: JWT (401 on any `AccessError`, including a missing token) → route lookup by path (404) → method (405) → `authorize` (403) → `Origin` for non-GET/HEAD (403, message `"cross-site request refused"`) → body (400) → handler. Bodies are parsed with `#[serde(deny_unknown_fields)]`; `display_name` is trimmed, 1–40 characters; `email` goes through `normalize_email`. Adding an existing email is 409 `"that email is already a reviewer"`. Setting `active` on the caller's own email is 400 `"you can't deactivate yourself"`; an unknown email is 404.

- [ ] **Step 1: Write the failing tests** (`tests/app.rs`; reuse `support` for tokens and `SqliteStore`; seed the owner as admin and Aiko as reviewer; helper `req(method, path, token, origin, body)`):

```rust
#[tokio::test] async fn no_token_is_401() { assert_eq!(handle(req("GET", "/api/me", None, None, "")).status, 401); }
#[tokio::test] async fn a_forged_token_is_401() { /* signed by a second generated key with the same kid */ 401 }
#[tokio::test] async fn me_returns_the_signed_in_user() { /* aiko, reviewer aud → 200 {"email":"aiko@example.com","display_name":"Aiko","role":"reviewer"} */ }
#[tokio::test] async fn a_reviewer_gets_403_on_every_admin_route() { for (m, p) in ADMIN_ROUTES { assert_eq!(…status, 403) } }
#[tokio::test] async fn the_owner_needs_the_admin_application_for_admin_routes() {
    // owner with reviewer-aud token → 403 on GET /api/admin/users; with admin-aud token → 200
}
#[tokio::test] async fn a_service_token_is_403_everywhere() { for every route in the table → 403 }
#[tokio::test] async fn unknown_paths_are_404_only_after_sign_in() { /* /api/nope: no token → 401; aiko → 404 */ }
#[tokio::test] async fn wrong_method_is_405() { /* DELETE /api/me → 405 */ }
#[tokio::test] async fn posts_need_the_site_origin() {
    // owner admin token, POST /api/admin/users: origin None → 403, "https://evil.example" → 403,
    // "https://review.martinloeseth.dev" → 201
}
#[tokio::test] async fn adding_a_reviewer() {
    // body {"email":" Ken@Example.com ","display_name":" Ken "} → 201 {"email":"ken@example.com","display_name":"Ken","role":"reviewer","active":true}
    // again → 409; {"email":"ken@example.com","display_name":"Ken","role":"admin"} → 400 (unknown field)
    // display_name "" or 41 chars → 400; email "nope" → 400; body "not json" → 400
}
#[tokio::test] async fn deactivating_and_reactivating() {
    // aiko → active false → 200; aiko's own GET /api/me → 403; active true → aiko 200 again
    // owner deactivating owner → 400; unknown email → 404
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd review/api && cargo test --test app`
Expected: compile errors for missing `app` items.

- [ ] **Step 3: Implement `app.rs`** and add `pub mod app;` to `lib.rs`.

- [ ] **Step 4: Run to verify they pass**

Run: `cd review/api && cargo test && cargo clippy --all-targets -- -D warnings && cargo fmt --check`
Expected: all tests pass, clean.

- [ ] **Step 5: Commit**

```bash
git add review/api
git commit -m "review/api: me and reviewer management endpoints, default deny"
```

---

### Task 6: The Worker (`worker_glue.rs`, `d1.rs`, `wrangler.toml`)

**Files:**
- Create: `review/api/src/worker_glue.rs`, `review/api/src/d1.rs`, `review/api/wrangler.toml`, `review/api/package.json` (devDependency `wrangler` `4.154.0`, scripts `deploy`, `migrate`, `migrate:local`), `review/api/package-lock.json`
- Modify: `review/api/src/lib.rs` (`#[cfg(target_arch = "wasm32")] mod worker_glue; #[cfg(target_arch = "wasm32")] mod d1;`)

**Interfaces:**
- Consumes: `handle`, `ApiRequest`, `ApiResponse`, `AppConfig` (Task 5); `KeyCache`, `parse_certs`, `token_kid` (Task 3); the SQL constants and `Store` (Task 4).
- Produces:
  - `#[event(fetch)] async fn fetch(req, env, ctx)` in `worker_glue.rs`: builds `AppConfig` from secrets `ACCESS_TEAM_DOMAIN`, `ACCESS_AUD`, `ACCESS_ADMIN_AUD` and var `SITE_ORIGIN`; a missing secret is a 500 `{"error":"the site is not configured"}` (never a pass). Reads the token only from the `Cf-Access-Jwt-Assertion` header. Keeps a `thread_local!` `KeyCache`; when `needs_fetch(kid, now)` is true it fetches `certs_url()` once and stores the result; a failed fetch keeps the old keys. Sets `Cache-Control: no-store`, `Content-Type: application/json; charset=utf-8`, `X-Content-Type-Options: nosniff` on every response.
  - `D1Store` in `d1.rs` implementing `Store` with the Task 4 SQL constants, `batch` for change + audit row, mapping a `UNIQUE`/`PRIMARY KEY` failure to `Conflict`.
  - `wrangler.toml`: `name = "verbtable-review-api"`, `main = "build/worker/shim.mjs"`, `compatibility_date = "2026-10-01"`, `[build] command = "cargo install -q worker-build@0.8.7 --locked && worker-build --release"`, `workers_dev = false`, `preview_urls = false`, `routes = [{ pattern = "review.martinloeseth.dev/api/*", zone_name = "martinloeseth.dev" }]`, `[vars] SITE_ORIGIN = "https://review.martinloeseth.dev"`, `[[d1_databases]] binding = "DB"`, `database_name = "verbtable-review"`, `database_id` left as the placeholder `"set-by-owner"` with a comment pointing to the README step (the owner fills it in and commits it, which is allowed), `migrations_dir = "migrations"`.

This task has no native tests: the glue is a translation layer, and everything it calls is tested. Its gate is that it compiles for `wasm32` and the native suite still passes.

- [ ] **Step 1: Write `d1.rs`, `worker_glue.rs`, `wrangler.toml` and `package.json`**; run `npm install` in `review/api` to produce the lockfile.

- [ ] **Step 2: Build for wasm**

Run: `cd review/api && cargo build --target wasm32-unknown-unknown --release && cargo clippy --target wasm32-unknown-unknown -- -D warnings`
Expected: builds, no warnings.

- [ ] **Step 3: Build the Worker bundle**

Run: `cd review/api && cargo install -q worker-build@0.8.7 --locked && worker-build --release && ls build/worker/shim.mjs`
Expected: the shim exists.

- [ ] **Step 4: Apply the migration locally**

Run: `cd review/api && npx wrangler d1 migrations apply verbtable-review --local`
Expected: `0001_users_and_audit.sql` applied. (Local D1 needs no account. If wrangler refuses because of the placeholder `database_id`, note it as a ruling and skip; the native tests already run the migration.)

- [ ] **Step 5: Run the native suite again**

Run: `cd review/api && cargo test && cargo fmt --check`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add review/api
git commit -m "review/api: the Worker entry point and D1 store"
```

---

### Task 7: The Svelte shell (`review/web`)

**Files:**
- Create: `review/web/` (SvelteKit, TypeScript, created with `npx sv create web --template minimal --types ts --no-add-ons --install npm` inside `review/`, or the current `sv create` equivalent if those flags have changed, then trimmed), notably:
  - `svelte.config.js` (adapter-static, `pages: 'build'`, `assets: 'build'`, `fallback: undefined`, `strict: true`; `kit.csp` below)
  - `src/app.html`, `src/app.css` (tokens), `src/routes/+layout.ts` (`export const prerender = true; export const ssr = false;`), `src/routes/+layout.svelte`, `src/routes/+page.svelte`, `src/routes/admin/+page.svelte`
  - `src/lib/api.ts`, `src/lib/api.test.ts`
  - `src/dev/mock-api.ts` (Vite plugin, dev server only)
  - `static/_headers`
  - `src/csp.test.ts`

**Interfaces:**
- Consumes: the Task 5 routes and JSON shapes.
- Produces:
  - `src/lib/api.ts`: `type Role = 'admin' | 'reviewer'`; `type Me = { email: string; display_name: string; role: Role }`; `type User = Me & { active: boolean }`; `class ApiError extends Error { status: number }`; `getMe(): Promise<Me>`, `listUsers(): Promise<User[]>`, `addUser(email: string, displayName: string): Promise<User>`, `setActive(email: string, active: boolean): Promise<User>`. Requests use `credentials: 'same-origin'`; POST bodies are JSON. Error copy (`ApiError.message`), by status: 401 `"Your sign-in has expired. Reload the page to sign in again."`; 403 `"This account can't do that. Ask Martin if you think it should."`; other statuses use the server's `error` text, or `"Something went wrong. Try again in a minute."` when there is none.
  - Pages:
    - Layout: a quiet header with the site name 添削 *Verb Table review* (the name in Zen Kaku Gothic New, 添削 in Shippori Mincho) and, on the right, the signed-in display name; for an admin, a link "Reviewers" to `/admin`. Loading shows nothing for 300 ms, then "Loading…". A failed `getMe` shows the `ApiError` message in place of the page.
    - Home (`/`): "Nothing is waiting for you yet. Martin will add things to review here." Plan 3 replaces it.
    - Admin (`/admin`): the reviewers list (display name, email, Active/Inactive, a "Deactivate"/"Reactivate" button; no button on the owner's own row) and an "Add a reviewer" form (email, display name, "Add reviewer" button). After adding: "Added Ken. Also add ken@example.com to the Access allow-list in Cloudflare, or they can't sign in." Non-admins who reach the page see the 403 message.
  - `kit.csp`: `mode: 'hash'`, directives `default-src 'self'`, `script-src 'self'`, `style-src 'self' https://fonts.googleapis.com`, `font-src https://fonts.gstatic.com`, `img-src 'self' data:`, `connect-src 'self'`, `base-uri 'none'`, `form-action 'self'`, `object-src 'none'`.
  - `static/_headers` for `/*`: `X-Frame-Options: DENY`, `Content-Security-Policy: frame-ancestors 'none'`, `Referrer-Policy: same-origin`, `X-Content-Type-Options: nosniff`, `Permissions-Policy: camera=(), microphone=(), geolocation=()`.
  - `package.json` scripts: `dev`, `build`, `check` (`svelte-kit sync && svelte-check --fail-on-warnings`), `test` (`vitest run`), `test:csp` (`vitest run src/csp.test.ts`, after `build`).
  - Dev mock: when `vite dev` runs, `/api/me` returns the owner as admin and the `/api/admin/users*` routes work against an in-memory list; `MOCK_ROLE=reviewer npm run dev` makes `/api/me` a reviewer and admin routes 403. It is registered only in `configureServer`, so it can't be in the build.

Use the Svelte MCP tools (`svelte-autofixer`) on every `.svelte` file, and the `svelte:svelte-code-writer` / `svelte-core-bestpractices` skills: Svelte 5 runes (`$state`, `$derived`, `$props`), no legacy `export let`.

- [ ] **Step 1: Scaffold** with the `sv create` command above, add `@sveltejs/adapter-static@4.0.0` and `vitest@5`, remove the template's demo content.

- [ ] **Step 2: Write the failing tests**

`src/lib/api.test.ts` (stub `globalThis.fetch` with `vi.fn`):

```ts
test('getMe returns the user', async () => { /* 200 {"email":"a@x.com","display_name":"A","role":"reviewer"} */ });
test('a 401 becomes the sign-in message', async () => {
  await expect(getMe()).rejects.toMatchObject({ status: 401, message: 'Your sign-in has expired. Reload the page to sign in again.' });
});
test('a 403 becomes the no-access message', …);
test('other errors use the server text', async () => { /* 409 {"error":"that email is already a reviewer"} */ });
test('an error without a body uses the fallback', …);
test('addUser posts JSON to /api/admin/users', async () => {
  // fetch called with '/api/admin/users', method 'POST', header content-type application/json,
  // body '{"email":"ken@example.com","display_name":"Ken"}', credentials 'same-origin'
});
test('setActive posts to /api/admin/users/active', …);
```

`src/csp.test.ts` (reads `build/index.html` and `build/admin.html`):

```ts
test('every page carries a hash-based CSP and no inline-script escape hatch', () => {
  for (const page of ['index.html', 'admin.html']) {
    const html = readFileSync(`build/${page}`, 'utf8');
    const csp = html.match(/<meta http-equiv="content-security-policy" content="([^"]+)"/i)?.[1];
    expect(csp).toContain("script-src 'self' 'sha256-");
    expect(csp).not.toContain('unsafe-inline');
    expect(csp).toContain("connect-src 'self'");
  }
});
test('_headers forbids framing', () => { expect(readFileSync('build/_headers', 'utf8')).toContain("frame-ancestors 'none'"); });
```

- [ ] **Step 3: Run to verify they fail**

Run: `cd review/web && npx vitest run src/lib/api.test.ts`
Expected: FAIL, `api.ts` has no such exports.

- [ ] **Step 4: Implement `api.ts`, the tokens in `app.css`, the layout and two pages, the dev mock, `_headers` and the CSP config.** Fonts: one `<link>` to Google Fonts in `app.html` for `Shippori+Mincho:wght@500;700` and `Zen+Kaku+Gothic+New:wght@400;500;700` with `display=swap`, plus the two `preconnect` links. Tokens as CSS custom properties on `:root` named after the spec (`--paper`, `--card`, `--ink`, `--muted`, `--grid`, `--rule`, `--red`). Focus rings visible (2 px `--ink` outline). Base font size 17 px, line height 1.6.

- [ ] **Step 5: Run every web check**

Run: `cd review/web && npm run check && npm test -- --exclude src/csp.test.ts && npm run build && npm run test:csp`
Expected: `svelte-check` 0 errors 0 warnings; api tests pass; build writes `build/index.html` and `build/admin.html`; CSP tests pass.

- [ ] **Step 6: Look at it.** Start the dev server through the preview tools (add a `review-web` entry to `.claude/launch.json`: `npm run dev --prefix review/web`, port 5173), screenshot `/` and `/admin` at desktop and at 375 px, add a reviewer, deactivate them, and check the layout matches the tokens and stays one column on the phone. Fix what looks wrong.

- [ ] **Step 7: Commit**

```bash
git add review/web .claude/launch.json
git commit -m "review/web: the signed-in shell and reviewer management"
```

---

### Task 8: CI, make targets and the owner's setup guide

**Files:**
- Create: `.github/workflows/review.yml`, `review/README.md`
- Modify: `Makefile` (targets `review-test`, `review-build`), `AGENTS.md` (repository map row for `review/` and `schema/`)

**Interfaces:**
- Consumes: the commands from Tasks 3–7.
- Produces:
  - `review.yml`: `on` push to `main` and pull requests, `paths: ["review/**", "schema/**", ".github/workflows/review.yml"]`; `permissions: contents: read`; `concurrency` like `swift.yml`. Two jobs on `ubuntu-latest`:
    - `api`: checkout (same pinned SHA as `data.yml`), `rustup target add wasm32-unknown-unknown`, cache `~/.cargo` and `review/api/target` keyed on `Cargo.lock`, then in `review/api`: `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`, `cargo test`, `cargo clippy --target wasm32-unknown-unknown -- -D warnings`, `cargo install worker-build@0.8.7 --locked`, `worker-build --release`.
    - `web`: checkout, `actions/setup-node` pinned to a full commit SHA with its version as a comment (look it up with `gh api repos/actions/setup-node/releases/latest`), `node-version: 24`, `cache: npm`, `cache-dependency-path: review/web/package-lock.json`, then in `review/web`: `npm ci`, `npm run check`, `npm test -- --exclude src/csp.test.ts`, `npm run build`, `npm run test:csp`.
  - `make review-test` runs the native Rust tests and the web checks and tests; `make review-build` runs `worker-build --release` and the web build. Both appear in `make help`.
  - `review/README.md`, the owner's checklist, in this order, each step with what to click or run and what to see:
    1. Create the D1 database: `npx wrangler d1 create verbtable-review`; paste its `database_id` into `review/api/wrangler.toml` and commit; `npm run migrate` in `review/api`.
    2. Zero Trust → Settings → Authentication: add the "One-time PIN" login method; add GitHub as a login method (create a GitHub OAuth app at github.com/settings/developers with the callback URL Zero Trust shows; the client secret goes only into Cloudflare). Make sure your GitHub account uses a passkey.
    3. Access application **Verb Table review**: self-hosted, `review.martinloeseth.dev`, session 24 h, login methods One-time PIN and GitHub, policy "Reviewers" = Allow, Include emails (your email and each reviewer's). Copy its AUD tag.
    4. Access application **Verb Table review admin**: self-hosted, paths `review.martinloeseth.dev/admin` and `review.martinloeseth.dev/api/admin`, session 24 h, login method GitHub only, policy "Owner" = Allow, Include email (the email on your GitHub account), Require login method GitHub. Copy its AUD tag. Check that the more specific paths take precedence (Access matches the most specific path).
    5. Worker secrets in `review/api`: `npx wrangler secret put ACCESS_TEAM_DOMAIN` (e.g. `yourteam.cloudflareaccess.com`), `ACCESS_AUD`, `ACCESS_ADMIN_AUD`. Then `npm run deploy`. Confirm `workers.dev` and preview URLs are off for the Worker in the dashboard.
    6. Pages: create project `verbtable-review` (direct upload), `npx wrangler pages deploy ../web/build --project-name verbtable-review` after `npm run build` in `review/web`; add the custom domain `review.martinloeseth.dev`; turn preview deployments off (or protect `*.verbtable-review.pages.dev` with an Access application that allows only you).
    7. Make yourself the admin: `npx wrangler d1 execute verbtable-review --remote --command "INSERT INTO users (email, display_name, role, active, created_at) VALUES ('<your email in lowercase>', 'Martin', 'admin', 1, datetime('now'))"`. Your email is typed here, not committed.
    8. Smoke test: open `https://review.martinloeseth.dev` in a private window, sign in with the email PIN, see "Nothing is waiting for you yet"; open `/admin`, sign in with GitHub (passkey), see yourself in the reviewers list; `curl -i https://review.martinloeseth.dev/api/me` without a session redirects to Access or returns 401/403, never 200.
    9. Adding a reviewer: add their email to the "Reviewers" policy, then add them on `/admin`. Removing one: deactivate on `/admin`, remove from the policy, and revoke their session under Zero Trust → Users.
  - The README also says what never to do: no Cloudflare API token in the Worker, no identity header trusted, no auth bypass for local dev (use `npm run dev` in `review/web` with the mock).

- [ ] **Step 1: Write `review.yml`, the Makefile targets, `review/README.md` and the `AGENTS.md` rows.**

- [ ] **Step 2: Run the local equivalents**

Run: `make review-test && make review-build && make test-py && make check-project`
Expected: everything passes; `make help` lists `review-test` and `review-build`.

- [ ] **Step 3: Validate the workflow file**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/review.yml'))" 2>/dev/null || ruby -ryaml -e "YAML.load_file('.github/workflows/review.yml')"`
Expected: no error. (CI itself runs when the branch is pushed; the PR's checks are the real gate.)

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/review.yml Makefile review/README.md AGENTS.md
git commit -m "review: CI, make targets and the Cloudflare setup guide"
```
