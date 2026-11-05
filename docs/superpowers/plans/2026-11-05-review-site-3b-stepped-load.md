# Review site, plan 3b: loading data in steps (Workers Free)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** "Load published data" works on Cloudflare Workers Free (about 10 ms of CPU per request), with room for the data to grow, without weakening any check.

**Why:** the owner stays on the free plan (decided 2026-11-05). Plan 3 loaded a whole file per request; verbs.json (≈ 370 KB) costs ≈ 10 ms natively and more in wasm. Measured breakdown (native, release): file SHA-256 2.6 ms, parsing 2.6 ms, canonical JSON and row hashes the rest. Time waiting on GitHub or D1 isn't CPU time.

**Design (approved in chat by the owner, "do your recommendations"):**
- The file's SHA-256 moves to Web Crypto (`crypto.subtle.digest`) in the Worker, which runs natively. The `Source` trait gains `sha256(bytes)`; the default (tests) uses `sha2`.
- A load becomes three kinds of request, driven by the Admin page:
  1. `POST /api/admin/snapshot/begin {file}`: verify the manifest signature, ref, hash and version (as today), check the file's top level against the strict types, split its entries into **slices** of at most `SLICE_BYTES` (48 000) bytes of published JSON each (an entry bigger than that is a slice on its own), record a load, and answer `{load_id, file, version, slices}`.
  2. `POST /api/admin/snapshot/slice {load_id, slice}`: re-fetch and re-verify (manifest signature, same version and hash as the load, file hash), parse only that slice's entries with the strict types, and write their rows to a staging table.
  3. `POST /api/admin/snapshot/finish {load_id}`: re-verify the same way, require every slice to be present, then in one D1 batch replace the dataset's items with the staged rows, update `snapshot_files` (with the file's text for furigana and forms), write the audit row and clear the staging rows.
- Reviewers never see a half-loaded dataset; any failure leaves the previous version. Starting a new load of a file discards that file's unfinished loads.
- Slicing uses `serde_json::value::RawValue` to find entry boundaries without building values for the whole file. Slices are a pure function of the file bytes, so every request agrees on them.
- Row `position` becomes `entry_index * 10 000 + row_within_entry`, so slices can be written independently and still sort in document order.
- The single-request `POST /api/admin/snapshot` is removed; furigana and forms simply have zero slices.

## Global constraints
Plan 3's. Every request still verifies Access, the admin application and role, `Origin`, the manifest signature, the ref, the file hash and the version.

## Review focus
- The manifest or file changes between begin and finish (a new data PR lands mid-load): a slice or finish whose re-verified version or hash differs from the load's is refused with "the published data changed while loading; start again", and nothing is replaced.
- finish with a slice missing (the page was closed mid-load): refused, nothing replaced.
- A slice sent twice (a retry): idempotent, no duplicate rows.
- Two loads of the same file: the second begin discards the first's staging rows; the first's later slices are refused as unknown.

---

### Task 1: Web Crypto hashing and slices (pure)
- `source.rs`: `Source::sha256(&self, bytes: &[u8]) -> String` with a default using `manifest::sha256_hex`.
- `items.rs`: `pub const SLICE_BYTES: usize = 48_000;` `pub fn slices(file: DataFile, bytes: &[u8]) -> Result<Vec<Range<usize>>, String>` (entry index ranges; empty for furigana and forms; checks the top level strictly with the entries left raw); `pub fn extract_slice(file, bytes, range) -> Result<Vec<ItemRow>, String>` (strict-parses only those entries); `extract` stays (now the concatenation of every slice) for tests and positions use the new scheme.
- Tests: slices cover every entry exactly once, in order; every multi-entry slice's raw JSON is ≤ `SLICE_BYTES`; concatenated `extract_slice` rows equal `extract`; positions strictly increase; a bad entry in one slice fails that slice; a bad top level fails `slices`.

### Task 2: Staging and the three endpoints
- Migration `0003_snapshot_loads.sql`: `snapshot_loads(load_id PRIMARY KEY, name, version, sha256, git_ref, slices, started_by, started_at)`, `snapshot_load_slices(load_id, slice, PRIMARY KEY(load_id, slice))`, `items_staging` (the `items` columns plus `load_id`, primary key `(load_id, kind, item_id)`).
- Store: `begin_load`, `stage_slice` (idempotent: deletes that slice's earlier rows first, keyed by entry range), `finish_load`, `load`.
- `app.rs`: the three routes; `import_file` is replaced by `begin_load`/`load_slice`/`finish_load` functions with the messages above.
- Tests (fake GitHub): a full stepped load of every file; reviewer 403 on all three; tamper, bad signature, older version and bad ref refused at begin; a mid-load change refused at slice and finish; a missing slice refused at finish; a repeated slice is idempotent; a second begin cancels the first.

### Task 3: The Worker and the Admin page
- `worker_glue.rs`: `FetchSource::sha256` with `crypto.subtle.digest("SHA-256", …)`.
- Admin page: for each file, begin → each slice → finish, showing "Loading verbs.json: 3 of 9"; stops at the first error.
- Dev mock: the same three routes.
- Measure: a throwaway bench of the costliest slice (native, release) under 3 ms.
