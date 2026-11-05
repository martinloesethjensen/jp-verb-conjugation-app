# Review site, plan 3: the read path

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The owner loads the published, signed data into the site with one button, and everyone signed in can browse every verb, word, counter and grammar lesson, with furigana, down to each example sentence.

**Architecture:** The Worker fetches `manifest.json` and `manifest.sig` from `main` on raw.githubusercontent.com, verifies the Ed25519 signature with the same public key the app embeds, fetches one data file at the ref its manifest entry names, checks its SHA-256, parses it with strict serde types mirrored from `schema/`, and replaces that dataset's rows in a D1 `items` table in one batch. Everything except the network call is a pure function tested natively against the real `data/` files; the network is a `Source` trait the tests fake. The pages read `/api/snapshot`, `/api/items`, `/api/item` and `/api/reference` and render ruby furigana with a TypeScript port of the app's `FuriganaDictionary` matching.

**Tech Stack:** as plan 2, plus `ed25519-dalek` 2 (default features off, `std`), `form_urlencoded` 1. SQLite JSON functions (`json_each`, `json_extract`), which D1 and bundled rusqlite both have.

**Spec:** `docs/superpowers/specs/2026-10-27-data-review-site-design.md` (Architecture: "Published data is read by the Worker…", D1 tables: `items`, Validation, The site → Screens: Browse). Plan 2: `2026-10-27-review-site-2-foundation.md` (merged, #190, plus #192 sign-out and #193 name changes).

## Roadmap (updated)

1. Stable ids (#181). 2. Schemas and skeleton (#190). **3. This plan: the read path.** 4. Review path: queues, approve, suggest change and delete, counter-suggestions, the admin inbox (plan 1's roadmap item 3). 5. Add path. 6. Export. 7. Stamps for verbs, words and examples.

## Global Constraints

- Plan 2's constraints hold: no auth bypass, every `/api/*` request verifies Access then D1, admin routes need the admin application and role, `Origin` on non-GET, no secrets or emails committed.
- The site never writes `data/` and never signs. It only reads published files.
- Manifest and signature always come from `main`: `https://raw.githubusercontent.com/martinloesethjensen/jp-verb-conjugation-app/main/data/`. A data file comes from `…/<ref>/data/<file>` when its entry has `ref`, else from `main`, exactly like `GitHubVerbFetcher.githubMain`.
- A `ref` must match the app's rule (`GitHubVerbFetcher.isValidRef`): 1–64 ASCII characters, letters, digits, `.`, `_`, `-`, starting with a letter or digit. Anything else is refused before any fetch.
- Trusted public keys: the base64 keys in `Packages/VerbKit/Sources/VerbKit/Data/ManifestSignatureVerifier.swift` (today one: `rratyJ5yBhlonBpzW/WGUSKL+nw4lHLn7iIcVl2RDH0=`). The signature is Ed25519 over the exact bytes of `manifest.json`, base64 in `manifest.sig`.
- A file is refused when its manifest version is older than the one already loaded (rollback), when its SHA-256 differs from its manifest entry, or when it doesn't parse into the strict types. A refused file leaves the previous rows untouched.
- Budget: Workers Free allows about 10 ms of CPU per request, so the import handles **one file per request**, and the page drives the six in turn. Each import request makes a handful of D1 queries: the item rows go in through one `INSERT … SELECT … FROM json_each(?)`.
- Files and their datasets: `verbs.json` → `verbs`, `words.json` → `words`, `counters.json` → `counters`, `grammar.json` → `grammar` (browsable), `furigana.json` and `forms.json` (reference only: stored whole, not as items). Import order on the page: furigana, forms, words, counters, grammar, verbs.
- Entry ids: verb `id` if present else `dict` (as `Verb.id`), word `"<class>:<dict>"` (as `Word.id`), counter `id`, grammar `id`. Sub-item ids: the stable ids from plan 1.
- Canonical JSON for `content_hash`: keys sorted, no whitespace, non-ASCII unescaped, the same bytes Python's `json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)` gives (as `update_data.review_hash`). Plan 4's `base_hash` and approvals compare these.
- Look and copy as plan 2. Japanese in Shippori Mincho with `<ruby>`; no inline styles (CSP).

## Review Focus

- The signed manifest names a file hash, but GitHub serves different bytes (a push landed between the two fetches, or a ref moved): that file is refused with "verbs.json doesn't match its signed manifest; try again in a minute", and the old rows stay. Test in Task 5.
- An older signed manifest is replayed (or `main` is reset): every file whose version is older than the loaded one is refused with "verbs.json 1.16.0 is older than the loaded 1.17.0". Test in Task 5.
- A manifest entry's `ref` is `../evil` or `main/../../x`: refused before any request is made. Test in Task 2.
- A sentence has a kanji with no reading, or a counter example carries its own `readings` (何か月): unknown kanji show plain, the example's readings win over the dictionary, nothing throws. Test in Task 6.
- The D1 write fails half-way: the dataset keeps its previous rows and version, because the delete, the insert and the version row are one batch. Test in Task 4.

---

### Task 1: Strict data types mirrored from the schemas (`review/api/src/data.rs`)

**Files:**
- Create: `review/api/src/data.rs`
- Modify: `review/api/src/lib.rs` (`pub mod data;`)
- Test: `review/api/tests/data.rs`

**Interfaces:**
- Produces:
  - `enum DataFile { Verbs, Words, Counters, Grammar, Furigana, Forms }` with `file_name() -> &'static str` (`"verbs.json"`…), `parse_name(&str) -> Option<DataFile>` (accepts `"verbs"`…), `ALL: [DataFile; 6]` in import order (Furigana, Forms, Words, Counters, Grammar, Verbs), and `is_browsable()` (the first four datasets).
  - One `#[serde(deny_unknown_fields)]` struct per object in each schema: `VerbsFile { version, description, verbs: Vec<Verb> }`, `Verb`, `VerbExample`, `WordsFile`, `Word`, `CountersFile`, `Counter`, `CounterThing`, `CounterExample`, `CounterPitfall`, `CounterQuestion`, `CounterGroup`, `CounterSection`, `GrammarFile`, `Book`, `GrammarPoint`, `Usage`, `GrammarExample`, `GrammarPitfall`, `Attachment`, `Conjugation`, `Contrast`, `TaughtIn`, `ReviewStamp`, `FuriganaFile { version, description, readings: BTreeMap<String, String> }`, `FormsFile`, `Form`, `Family`. Data-keyed maps are `BTreeMap<String, …>`. Enum-valued fields are Rust enums with `#[serde(rename = …)]` for the exact strings in the schema (`"irr."`, `"i-adjective"`, `"h-b"`…); `jlpt` is `enum Jlpt { N5, N4, N3, N2, N1 }`. Optional keys are `Option<…>` with `#[serde(default)]`. Verb `kanji` is `Option<String>` with `#[serde(default)]`, which accepts a string, `null` and a missing key, as the schema does.
  - `fn parse(file: DataFile, bytes: &[u8]) -> Result<Parsed, String>` where `enum Parsed { Verbs(VerbsFile), Words(WordsFile), Counters(CountersFile), Grammar(GrammarFile), Furigana(FuriganaFile), Forms(FormsFile) }`; the `String` is serde's message.
- The JSON Schemas stay the contract; these types are tested against them, not the other way round. Patterns (stable ids, kana, slugs) are enforced by `update_data.py` at publish time and are not re-checked here; enums, required keys and unknown keys are.

- [ ] **Step 1: Write the failing tests** (`tests/data.rs`):

```rust
const ROOT: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");

fn real(file: DataFile) -> Vec<u8> { std::fs::read(format!("{ROOT}/data/{}", file.file_name())).unwrap() }

#[test] fn every_published_file_parses() {
    for file in DataFile::ALL { assert!(parse(file, &real(file)).is_ok(), "{}", file.file_name()); }
}

#[test] fn the_shared_invalid_fixtures_are_rejected() {
    // schema/fixtures/invalid.json: [{name, dataset, doc, error}], each breaking one rule.
    // Patterns aren't mirrored, so the two pattern fixtures ("grammar usage with a malformed id"
    // and any other whose error contains "does not match") are skipped, by name, with a comment.
    for fixture in fixtures() {
        if PATTERN_ONLY.contains(&fixture.name.as_str()) { continue; }
        let file = DataFile::parse_name(&fixture.dataset).unwrap();
        assert!(parse(file, fixture.doc.to_string().as_bytes()).is_err(), "{}", fixture.name);
    }
}

#[test] fn names_and_order() {
    assert_eq!(DataFile::ALL.map(|f| f.file_name()),
        ["furigana.json", "forms.json", "words.json", "counters.json", "grammar.json", "verbs.json"]);
    assert_eq!(DataFile::parse_name("verbs"), Some(DataFile::Verbs));
    assert_eq!(DataFile::parse_name("../verbs"), None);
    assert!(DataFile::Counters.is_browsable() && !DataFile::Forms.is_browsable());
}

#[test] fn an_unknown_key_anywhere_is_rejected() {
    // Take the real counters file, add "romaji" to the first thing of the first counter.
    let mut doc: serde_json::Value = serde_json::from_slice(&real(DataFile::Counters)).unwrap();
    doc["counters"][0]["things"][0]["romaji"] = "x".into();
    assert!(parse(DataFile::Counters, doc.to_string().as_bytes()).is_err());
}
```

- [ ] **Step 2: Run to verify they fail** — `cd review/api && cargo test --test data`. Expected: compile errors, no `data` module.
- [ ] **Step 3: Write `data.rs`.** Read each `schema/*.schema.json` and mirror it field for field; the real data and the fixtures are the check.
- [ ] **Step 4: Run** — `cargo test --test data && cargo clippy --all-targets -- -D warnings`. Expected: 4 pass, clean. The real data failing to parse means a type is wrong; fix the type, never the data.
- [ ] **Step 5: Commit** — `git commit -m "review/api: strict types for every data file, checked against the real data and shared fixtures"`

---

### Task 2: The signed manifest (`review/api/src/manifest.rs`)

**Files:**
- Create: `review/api/src/manifest.rs`
- Modify: `review/api/Cargo.toml` (`ed25519-dalek = { version = "2", default-features = false, features = ["std"] }`), `review/api/src/lib.rs`
- Test: `review/api/tests/manifest.rs`

**Interfaces:**
- Consumes: `DataFile` (Task 1).
- Produces:
  - `pub const TRUSTED_KEYS: &[&str] = &["rratyJ5yBhlonBpzW/WGUSKL+nw4lHLn7iIcVl2RDH0="];`
  - `pub const RAW_ROOT: &str = "https://raw.githubusercontent.com/martinloesethjensen/jp-verb-conjugation-app/";`
  - `struct Entry { version: String, sha256: String, git_ref: Option<String> }`
  - `struct Manifest { … }` with `fn entry(&self, file: DataFile) -> Option<Entry>`: the verbs entry is the top-level `version`/`sha256`/`ref`; the others are the nested objects.
  - `fn verify(manifest: &[u8], signature_b64: &str, keys: &[&str]) -> Result<Manifest, ManifestError>`: signature checked over the exact bytes first, then parsed.
  - `fn is_valid_ref(r: &str) -> bool`, `fn manifest_url() -> String`, `fn signature_url() -> String`, `fn file_url(file: DataFile, entry: &Entry) -> Result<String, ManifestError>` (refuses an invalid ref).
  - `fn is_older(candidate: &str, current: &str) -> bool`: numeric `major.minor.patch` comparison like `DataVersion.isOlder`; an unparsable version counts as older (fail closed).
  - `fn sha256_hex(bytes: &[u8]) -> String`.
  - `enum ManifestError { BadSignature, Malformed, MissingEntry(DataFile), BadRef(String) }`.

- [ ] **Step 1: Write the failing tests:**

```rust
#[test] fn the_published_manifest_verifies_with_the_apps_key() {
    let m = verify(&real("manifest.json"), real_text("manifest.sig").trim(), TRUSTED_KEYS).unwrap();
    assert_eq!(m.entry(DataFile::Verbs).unwrap().sha256, sha256_hex(&real("verbs.json")));
    for file in DataFile::ALL { assert!(m.entry(file).is_some(), "{}", file.file_name()); }
}
#[test] fn one_changed_byte_breaks_it() { /* flip a byte in manifest.json → Err(BadSignature) */ }
#[test] fn a_signature_from_another_key_is_refused() { /* sign with a generated SigningKey → Err(BadSignature) */ }
#[test] fn the_trusted_keys_are_the_ones_the_app_embeds() {
    // Read ManifestSignatureVerifier.swift and collect every "<43 base64 chars>=" string literal
    // in the production list, as scripts/sign_manifest.py's trusted_keys() does.
    assert_eq!(swift_keys(), TRUSTED_KEYS);
}
#[test] fn refs_follow_the_apps_rule() {
    for ok in ["v1.2.0", "data-2026_11", "a"] { assert!(is_valid_ref(ok)); }
    for bad in ["", "../evil", "main/../../x", ".hidden", "-x", "a b", "é", &"a".repeat(65)] { assert!(!is_valid_ref(bad), "{bad}"); }
}
#[test] fn urls() {
    let e = |r: Option<&str>| Entry { version: "1.0.0".into(), sha256: "x".into(), git_ref: r.map(Into::into) };
    assert_eq!(file_url(DataFile::Words, &e(None)).unwrap(), format!("{RAW_ROOT}main/data/words.json"));
    assert_eq!(file_url(DataFile::Words, &e(Some("v2"))).unwrap(), format!("{RAW_ROOT}v2/data/words.json"));
    assert!(matches!(file_url(DataFile::Words, &e(Some("../x"))), Err(ManifestError::BadRef(_))));
    assert_eq!(manifest_url(), format!("{RAW_ROOT}main/data/manifest.json"));
}
#[test] fn versions_compare_numerically() {
    assert!(is_older("1.9.0", "1.10.0")); assert!(!is_older("1.10.0", "1.9.0"));
    assert!(!is_older("1.17.0", "1.17.0")); assert!(is_older("junk", "1.0.0"));
}
```

- [ ] **Step 2: Run to verify they fail** — `cargo test --test manifest`. Expected: compile errors.
- [ ] **Step 3: Implement `manifest.rs`.**
- [ ] **Step 4: Run** — `cargo test --test manifest && cargo clippy --all-targets -- -D warnings && cargo build --target wasm32-unknown-unknown --release`. Expected: pass, clean, builds.
- [ ] **Step 5: Commit** — `git commit -m "review/api: verify the signed manifest with the app's key"`

---

### Task 3: Items from a data file (`review/api/src/items.rs`)

**Files:**
- Create: `review/api/src/items.rs`
- Test: `review/api/tests/items.rs`

**Interfaces:**
- Consumes: `DataFile`, `parse`, `Parsed` (Task 1).
- Produces:
  - `#[derive(Serialize)] struct ItemRow { kind: Kind, item_id: String, parent_id: Option<String>, entry_id: String, position: u32, title: String, subtitle: String, jlpt: Option<String>, content_hash: String, json: String }`. `entry_id` is the entry the row belongs to (its own id for an entry). `json` is the item's own canonical JSON (for an entry: the whole entry, sub-items included). `position` is document order across the whole file, from 0.
  - `enum Kind { Entry, Example, Usage, Pitfall, Thing }` (serde lowercase).
  - `fn canonical_json(value: &serde_json::Value) -> String` and `fn content_hash(value: &serde_json::Value) -> String` (SHA-256 hex of the canonical bytes).
  - `fn extract(file: DataFile, bytes: &[u8]) -> Result<Vec<ItemRow>, String>`: parses with `parse` (so a file the types reject yields `Err`), then walks the *raw* `serde_json::Value` (so stored JSON is exactly the published content, not a re-serialisation) for browsable files; `Ok(vec![])` for furigana and forms.
  - Titles and subtitles:

    | Item | title | subtitle | jlpt |
    |---|---|---|---|
    | verb | `dict (kanji)` or `dict` | meaning | jlpt |
    | word | `dict (kanji)` or `dict` | meaning | jlpt |
    | counter | `counter (reading)` | meaning | jlpt |
    | grammar point | title | summary | jlpt |
    | example | jp | en | — |
    | usage | heading | explanation | usage `jlpt` if present |
    | pitfall | heading | explanation | — |
    | thing | word | meaning | — |

  - Parent of a sub-item: its entry's id, or the usage/pitfall/contrast it sits in (a contrast has no stable id, so its examples' parent is the grammar point). Sub-item rows exist for exactly the objects `scripts/stable_ids.py`'s `id_slots` returns.

- [ ] **Step 1: Write the failing tests:**

```rust
#[test] fn every_entry_and_stable_id_slot_becomes_a_row() {
    // Counts from the real files: entries per dataset, and sub-items equal to the number of
    // objects with a stable id (count with a small recursive walk over the raw JSON: any object
    // with "id" matching ^[a-km-np-z2-9]{6}$ inside an entry).
    for (file, entries) in [(DataFile::Verbs, 84), (DataFile::Words, 32), (DataFile::Counters, 30), (DataFile::Grammar, 18)] {
        let rows = extract(file, &real(file)).unwrap();
        assert_eq!(rows.iter().filter(|r| r.kind == Kind::Entry).count(), entries);
        assert_eq!(rows.iter().filter(|r| r.kind != Kind::Entry).count(), stable_id_objects(&real(file)));
    }
}
// The entry counts are today's; read them from the file in the test instead if they change often.
#[test] fn ids_follow_the_app() {
    // verbs: "きる:切る" (explicit id) and "たべる" both present; words: "i-adjective:いい"
}
#[test] fn titles() {
    // たべる → title "たべる (食べる)", subtitle "to eat"; counter hon → "本 (ほん)";
    // the first example of たべる: title its jp, subtitle its en, parent "たべる", kind Example.
}
#[test] fn ids_are_unique_per_kind_within_a_dataset() { /* (kind, item_id) pairs have no duplicates */ }
#[test] fn the_canonical_hash_matches_pythons() {
    // Python: hashlib.sha256(json.dumps({"b": "食べる", "a": [1, {"d": None, "c": True}]},
    //   sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
    let v = json!({"b": "食べる", "a": [1, {"d": null, "c": true}]});
    assert_eq!(canonical_json(&v), r#"{"a":[1,{"c":true,"d":null}],"b":"食べる"}"#);
    assert_eq!(content_hash(&v), PYTHON_HASH); // paste the value computed with the line above
}
#[test] fn reference_files_have_no_rows_and_bad_files_fail() {
    assert!(extract(DataFile::Furigana, &real(DataFile::Furigana)).unwrap().is_empty());
    assert!(extract(DataFile::Verbs, b"{}").is_err());
}
```

- [ ] **Step 2: Run to verify they fail** — `cargo test --test items`.
- [ ] **Step 3: Implement `items.rs`.** `serde_json`'s default `Map` is a `BTreeMap`, so `to_string` already sorts keys and writes compact UTF-8; check it against the Python value rather than assuming.
- [ ] **Step 4: Run** — `cargo test --test items && cargo clippy --all-targets -- -D warnings`.
- [ ] **Step 5: Commit** — `git commit -m "review/api: turn a data file into browsable item rows"`

---

### Task 4: Snapshot storage (migration 0002, `store.rs`)

**Files:**
- Create: `review/api/migrations/0002_snapshot.sql`
- Modify: `review/api/src/store.rs`, `review/api/src/d1.rs`, `review/api/tests/support/sqlite.rs`
- Test: `review/api/tests/snapshot_store.rs`

**Interfaces:**
- Consumes: `ItemRow`, `Kind` (Task 3).
- Produces:
  - Migration: `snapshot_files(name TEXT PRIMARY KEY, version TEXT NOT NULL, sha256 TEXT NOT NULL, git_ref TEXT, item_count INTEGER NOT NULL, imported_at TEXT NOT NULL, imported_by TEXT NOT NULL, json TEXT)` (`json` only for furigana and forms) and `items(dataset TEXT NOT NULL, kind TEXT NOT NULL, item_id TEXT NOT NULL, parent_id TEXT, entry_id TEXT NOT NULL, position INTEGER NOT NULL, title TEXT NOT NULL, subtitle TEXT NOT NULL, jlpt TEXT, content_hash TEXT NOT NULL, json TEXT NOT NULL, PRIMARY KEY (dataset, kind, item_id))` with `CREATE INDEX items_by_entry ON items (dataset, entry_id)`.
  - `struct SnapshotFile { name: String, version: String, sha256: String, git_ref: Option<String>, item_count: u32, imported_at: String, imported_by: String }` (serde) and `struct ItemSummary { item_id, title, subtitle, jlpt: Option<String>, parts: u32 }`, where `parts` counts the dataset's non-entry rows with `entry_id = item_id`.
  - Store trait additions:

    ```rust
    async fn replace_snapshot(&self, file: &SnapshotFile, json: Option<&str>, rows: &[ItemRow], actor: &str, now: &str) -> Result<(), StoreError>;
    async fn snapshot_files(&self) -> Result<Vec<SnapshotFile>, StoreError>;
    async fn snapshot_file(&self, name: &str) -> Result<Option<SnapshotFile>, StoreError>;
    async fn snapshot_json(&self, name: &str) -> Result<Option<String>, StoreError>;
    async fn entries(&self, dataset: &str) -> Result<Vec<ItemSummary>, StoreError>;  // in position order
    async fn entry(&self, dataset: &str, item_id: &str) -> Result<Option<(String, String)>, StoreError>; // (json, content_hash)
    ```
  - `replace_snapshot` is one batch: `DELETE FROM items WHERE dataset = ?`, one `INSERT INTO items (…) SELECT … FROM json_each(?)` taking all rows as a JSON array, `INSERT OR REPLACE INTO snapshot_files …`, and the audit row (`snapshot.import`, target the file name, detail `version=<v>`). SQL constants in `store.rs` as before.

- [ ] **Step 1: Write the failing tests** (SQLite store, real files through `extract`):

```rust
#[tokio::test] async fn a_snapshot_round_trips() {
    // replace_snapshot(words, rows from extract) → snapshot_file("words").version == manifest version,
    // entries("words").len() == 32 in file order, entry("words", "i-adjective:いい") JSON == the published entry.
}
#[tokio::test] async fn replacing_drops_items_that_disappeared() { /* import, then import a copy with one word removed → 31 */ }
#[tokio::test] async fn parts_count_every_sub_item_of_an_entry() { /* たべる's parts == its examples count; a grammar point's == usages + their examples + pitfalls + theirs + contrast examples */ }
#[tokio::test] async fn a_failed_write_keeps_the_old_snapshot() {
    // Import words; then call replace_snapshot with two rows sharing (kind, item_id) → Err;
    // the old 32 rows and old version are still there.
}
#[tokio::test] async fn reference_files_keep_their_json() { /* furigana: snapshot_json("furigana") == file text */ }
#[tokio::test] async fn imports_are_audited() { /* audit row snapshot.import, target "words.json", detail "version=1.0.0" */ }
```

- [ ] **Step 2: Run to verify they fail** — `cargo test --test snapshot_store`.
- [ ] **Step 3: Write the migration, the SQL, the SQLite and D1 implementations.** In D1, `batch` is a transaction; in SQLite use one transaction.
- [ ] **Step 4: Run** — `cargo test && cargo clippy --all-targets -- -D warnings && cargo clippy --target wasm32-unknown-unknown -- -D warnings`.
- [ ] **Step 5: Commit** — `git commit -m "review/api: store a snapshot of each data file and its items"`

---

### Task 5: The read and import API (`app.rs`, `source.rs`)

**Files:**
- Create: `review/api/src/source.rs`
- Modify: `review/api/src/app.rs`, `review/api/Cargo.toml` (`form_urlencoded = "1"`)
- Test: `review/api/tests/read_api.rs`, `review/api/tests/support/source.rs` (a `FakeSource` serving files from a map)

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces:
  - `source.rs`: `#[allow(async_fn_in_trait)] pub trait Source { async fn get(&self, url: &str) -> Result<Vec<u8>, String>; }` (a non-200 is an `Err`).
  - `ApiRequest` gains `query: String` (the raw query string, without `?`); `handle` gains a `source: &impl Source` parameter after `store`.
  - `pub async fn import_file<S: Store, R: Source>(file: DataFile, store: &S, source: &R, actor: &str, now: &str) -> Result<SnapshotFile, String>`: fetch manifest + signature → `verify` → entry → `file_url` → fetch → hash → `is_older` against the loaded version → `extract` → `replace_snapshot`. Error strings are the user-facing messages below.
  - Routes (added to `ROUTES`; query parameters decoded with `form_urlencoded`):

    | Method, path | Need | Success |
    |---|---|---|
    | `GET /api/snapshot` | Reviewer | 200 `{"files":[SnapshotFile…]}` in import order; files never loaded are absent |
    | `GET /api/items?dataset=verbs` | Reviewer | 200 `{"dataset","version","items":[ItemSummary…]}`; 400 for a non-browsable or unknown dataset; 404 `"Martin hasn't loaded this data yet."` when not loaded |
    | `GET /api/item?dataset=verbs&id=たべる` | Reviewer | 200 `{"dataset","version","id","content_hash","item": <entry JSON>}`; 404 when unknown |
    | `GET /api/reference` | Reviewer | 200 `{"readings":{…},"forms":{"<id>":"<label>"}}` from the stored furigana and forms files; empty objects when not loaded |
    | `POST /api/admin/snapshot` body `{"file":"verbs"}` | Admin | 200 the new `SnapshotFile`; 400 unknown file; 502 with the message when an import is refused |

  - Messages (exact): `"couldn't fetch the published data; try again in a minute"` (any fetch error), `"the published manifest isn't signed by Martin's key"`, `"<file> doesn't match its signed manifest; try again in a minute"`, `"<file> <v> is older than the loaded <loaded>"`, `"<file> doesn't fit the data schema: <serde message>"`, `"the manifest has an invalid ref for <file>"`.

- [ ] **Step 1: Write the failing tests** (`FakeSource` serves `RAW_ROOT + "main/data/<name>"` from the repo's real `data/`; tests mutate its map):

```rust
#[tokio::test] async fn the_owner_loads_every_file_and_reviewers_browse() {
    // POST /api/admin/snapshot for each of DataFile::ALL (admin token, site origin) → 200 each;
    // GET /api/snapshot as aiko lists six files with the manifest's versions;
    // GET /api/items?dataset=verbs → 84 items, first title "する"; GET /api/item?dataset=verbs&id=%E3%81%9F%E3%81%B9%E3%82%8B → たべる;
    // GET /api/item?dataset=verbs&id=%E3%81%8D%E3%82%8B%3A%E5%88%87%E3%82%8B → the explicit-id verb;
    // GET /api/reference → readings equals furigana.json's "readings" object; forms["masu_pos"] == "Polite".
}
#[tokio::test] async fn reviewers_cannot_load_data() { /* aiko POST /api/admin/snapshot → 403 */ }
#[tokio::test] async fn a_tampered_file_is_refused_and_the_old_rows_stay() {
    // load words; change one byte of words.json in the source; POST again → 502
    // "words.json doesn't match its signed manifest; try again in a minute"; items still 32, version unchanged.
}
#[tokio::test] async fn a_bad_signature_is_refused() { /* replace manifest.sig with another key's signature → 502, message as above */ }
#[tokio::test] async fn an_older_manifest_is_refused() {
    // seed snapshot_files with words version "9.0.0" (a direct INSERT in the SQLite store) → POST
    // {"file":"words"} → 502 "words.json 1.0.0 is older than the loaded 9.0.0"; the seeded row is unchanged.
}
#[tokio::test] async fn a_fetch_failure_is_a_clear_502() { /* remove words.json from the source → 502 "couldn't fetch the published data; try again in a minute" */ }
#[tokio::test] async fn queries_are_validated() {
    // /api/items?dataset=forms → 400; ?dataset=nope → 400; no dataset → 400; before loading → 404 with the message;
    // /api/item?dataset=verbs&id=nobody → 404; POST snapshot {"file":"../verbs"} → 400.
}
```

To test the signature paths without the real private key, `import_file` takes `keys: &[&str]` internally (`import_file_with_keys`) and `import_file` passes `TRUSTED_KEYS`; tests that need a different signer sign with a generated `ed25519_dalek::SigningKey` and pass its public key.

- [ ] **Step 2: Run to verify they fail** — `cargo test --test read_api`.
- [ ] **Step 3: Implement `source.rs` and the routes.** Update `tests/app.rs` callers for the new `handle` signature (pass a `FakeSource` with no files).
- [ ] **Step 4: Run** — `cargo test && cargo clippy --all-targets -- -D warnings`.
- [ ] **Step 5: Commit** — `git commit -m "review/api: load signed data files and serve them to reviewers"`

---

### Task 6: The Worker's fetch source and the page helpers

**Files:**
- Modify: `review/api/src/worker_glue.rs` (a `FetchSource` implementing `Source` with `worker::Fetch`, `User-Agent: kotobatable-review`; pass `req.url()?.query()` into `ApiRequest.query`)
- Modify: `review/web/src/lib/api.ts`, `review/web/src/lib/api.test.ts`
- Create: `review/web/src/lib/ruby.ts`, `review/web/src/lib/ruby.test.ts`
- Modify: `review/web/src/dev/mock-api.ts` (serve the new routes from the repo's `data/` files, read at dev-server start)

**Interfaces:**
- Produces (TypeScript):
  - `api.ts`: types `SnapshotFile`, `ItemSummary`, `ItemResponse = { dataset: string; version: string; id: string; content_hash: string; item: Record<string, unknown> }`, `Reference = { readings: Record<string, string>; forms: Record<string, string> }`; functions `getSnapshot()`, `listItems(dataset)`, `getItem(dataset, id)` (encodes with `URLSearchParams`), `getReference()`, `loadFile(file)` (POST `/api/admin/snapshot`). `DATASETS = ['verbs', 'words', 'counters', 'grammar'] as const`, `FILES` in import order.
  - `ruby.ts`: `type Segment = { text: string; reading?: string }`; `segments(text: string, readings: Record<string, string>, extra?: Record<string, string>): Segment[]`, a port of `FuriganaDictionary.units(for:)`'s matching only (no line-break chunking, which the browser does): scan left to right; at a kanji (CJK ideographs and 々) take the longest key in `extra` then in `readings` whose kanji part is a prefix of the kanji run here, optionally followed by up to 3 hiragana that must also match the text; emit the kanji part with the reading and continue right after the kanji part; an unknown kanji run is plain; `extra` keys may contain kana inside (何か月) and are matched as whole strings first. Adjacent plain characters merge into one segment.

- [ ] **Step 1: Write the failing tests** (`ruby.test.ts`; cases taken from `Packages/VerbKit/Tests/VerbKitTests/FuriganaDictionaryTests.swift`, ported, plus):

```ts
const R = { 食: 'た', 毎日: 'まいにち', 学校: 'がっこう', 来ら: 'こ', 来: 'く', 何: 'なに' };
test('a run splits into the longest known keys', () =>
  expect(segments('毎日学校', R)).toEqual([{ text: '毎日', reading: 'まいにち' }, { text: '学校', reading: 'がっこう' }]));
test('okurigana stay plain', () =>
  expect(segments('食べる', R)).toEqual([{ text: '食', reading: 'た' }, { text: 'べる' }]));
test('kana after the kanji choose the reading', () =>
  expect(segments('来られる', R)[0]).toEqual({ text: '来', reading: 'こ' }));
test('unknown kanji stay plain', () => expect(segments('猫が来る', R)[0]).toEqual({ text: '猫が' }));
test("an example's own readings win, whole words included", () =>
  expect(segments('何か月ですか', R, { 何か月: 'なんかげつ' })[0]).toEqual({ text: '何か月', reading: 'なんかげつ' }));
test('no kanji, one segment', () => expect(segments('ですか。', R)).toEqual([{ text: 'ですか。' }]));
```

and in `api.test.ts`: `getItem('verbs', 'きる:切る')` fetches `/api/item?dataset=verbs&id=%E3%81%8D%E3%82%8B%3A%E5%88%87%E3%82%8B`; `loadFile('verbs')` POSTs `{"file":"verbs"}`.

- [ ] **Step 2: Run to verify they fail** — `cd review/web && npx vitest run src/lib`.
- [ ] **Step 3: Implement `ruby.ts`, the `api.ts` additions, the mock routes, and the Worker's `FetchSource`.**
- [ ] **Step 4: Run** — `npx vitest run src/lib && npm run check`, and `cd ../api && cargo clippy --target wasm32-unknown-unknown -- -D warnings && worker-build --release`.
- [ ] **Step 5: Commit** — `git commit -m "review: fetch published data in the Worker; page helpers for data and furigana"`

---

### Task 7: Browse and item pages, and loading data (`review/web`)

**Files:**
- Create: `review/web/src/lib/Japanese.svelte` (renders `segments` as `<ruby>`/text, `lang="ja"`), `review/web/src/lib/Sentence.svelte` (jp on a faint genkō grid line, en below, optional form label), `review/web/src/routes/browse/[dataset]/+page.svelte`, `review/web/src/routes/browse/[dataset]/+page.ts` (`entries()` returns the four datasets), `review/web/src/routes/item/+page.svelte`, `review/web/src/lib/reference.svelte.ts` (loads `/api/reference` once per page load and shares it)
- Modify: `review/web/src/routes/+page.svelte` (home), `review/web/src/routes/admin/+page.svelte` (a "Published data" section), `review/web/src/csp.test.ts` (new pages)

**Interfaces:**
- Consumes: Task 6's `api.ts` and `ruby.ts`.
- Pages and copy:
  - **Home:** "Waiting for you" keeps its current text ("Nothing is waiting for you yet."); below it, **Browse** with one card per dataset ("Verbs", "Words", "Counters", "Grammar"), each showing its loaded version from `/api/snapshot` ("Version 1.17.0") or "Not loaded yet", and linking to `/browse/<dataset>`.
  - **Browse** (`/browse/verbs`): a search box ("Search" placeholder; filters title and subtitle, case-insensitive, also matching kana typed against titles) and a JLPT select ("All levels", N5…N1); rows show title (Japanese in `Japanese`), subtitle, the JLPT pill and "3 parts" (`parts`); each row links to `/item?dataset=verbs&id=…` (built with `URLSearchParams`). Empty: "No matches." Not loaded: the API's 404 message.
  - **Item** (`/item?dataset=…&id=…`, read in `onMount` from `page.url.searchParams`, since prerendering can't see the query): the title, JLPT pill and subtitle, then the entry's authored fields by dataset:
    - verb: type label, description, notes, examples (`Sentence` with the form label from `reference.forms`);
    - word: class, meaning;
    - counter: things (word, kana, meaning, fit), examples (with their own `readings` as `extra`), pitfalls (heading, explanation, wrong, examples), questions;
    - grammar: summary, usages (heading, explanation, JLPT pill, examples), pitfalls, contrasts (pattern, explanation, examples).
    Generated fields (verb and word `forms`, counter `readings`, `changed`, `distractors`) are not shown. Each sub-item carries `id={stable id}` on its element, for plan 4's links.
  - **Admin → Published data:** a table of the six files (name, loaded version or "Not loaded", loaded when and by whom) and a **Load published data** button that calls `loadFile` for each of `FILES` in order, showing "Loading verbs.json…" and then per file the version or the error message; it stops at the first error.
- Layout: browse list one column; item page reading width 42rem; on laptops the browse list and item stay separate pages (the two-pane layout comes with queues in plan 4).

- [ ] **Step 1: Add the new pages to `csp.test.ts`** (`browse/verbs.html`, `browse/words.html`, `browse/counters.html`, `browse/grammar.html`, `item.html`) and run it after a build to see it fail: `npm run build && npm run test:csp`. Expected: FAIL, the files don't exist.
- [ ] **Step 2: Build the components and pages.** Svelte 5 runes; run `svelte-autofixer` on each `.svelte` file until it reports nothing; classes only, no `style=`.
- [ ] **Step 3: Run every web check** — `npm run check && npm test -- --exclude src/csp.test.ts && npm run build && npm run test:csp`. Expected: clean, all pass.
- [ ] **Step 4: Look at it** with the `review-web-build` preview (the mock serves the real data): load data from Admin, browse each dataset, open たべる, a counter with pitfalls (本), a grammar lesson with contrasts (ので), and check the ruby, the form labels, search and the JLPT filter, at desktop and 375 px.
- [ ] **Step 5: Commit** — `git commit -m "review/web: browse and item pages with furigana; load published data from Admin"`

---

### Task 8: Docs and a real load

**Files:**
- Modify: `review/README.md` (deploys are automatic: Pages on `review/web/*`, Workers Builds on `review/api/*`; migrations stay manual; a new "Loading data" section: after a data PR merges, Admin → Load published data), `.github/workflows/review.yml` (header comment: deploys happen in Cloudflare, not here), `AGENTS.md` if a command changed.

- [ ] **Step 1: Update the docs.**
- [ ] **Step 2: Run** — `make review-test && make test-py && make check-project`. Expected: pass.
- [ ] **Step 3: Commit** — `git commit -m "review: docs for automatic deploys and loading data"`
- [ ] **Step 4: After merge (owner):** run `npm run migrate` in `review/api` (migration 0002), wait for Workers Builds and Pages, then Admin → **Load published data**, and browse.
