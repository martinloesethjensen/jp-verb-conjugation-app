# Kanji Stroke Order Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Watch/Trace stroke-order sheet for every jōyō kanji and every kanji in the app's data, opened from text menus, a Kanji section on the verb page and the Word Bank kanji chips, with its data published as a seventh signed `data/` file.

**Architecture:** A hand-run script turns KanjiVG (stroke paths) and KANJIDIC2 (readings, meanings, grade) into `data/kanji.json`; `make data` validates it, checks coverage, and gives it a manifest entry and a bundled copy like `forms.json`. VerbKit gets a seventh concrete sync service, a blob-persisted `KanjiStore`, and pure stroke geometry plus a trace matcher; App draws the strokes with the 2c SVG path parser and hosts the sheet.

**Tech Stack:** Python 3 (stdlib `xml.etree`, `gzip`, `unittest`), Swift 6 / SwiftUI (iOS 26, macOS 26), SwiftData, XCTest.

**Spec:** `docs/superpowers/specs/2026-11-06-paper-ink-redesign-design.md` (row 3), the canvas boards "Kanji stroke order" (`project/KanjiStrokes.dc.html`), "trace" (`project/KanjiTrace.dc.html`), "opening it" (`project/KanjiEntry.dc.html`) and the Kanji section of "Verb page full length" (`project/VerbFull.dc.html`) at https://claude.ai/artifact/7eCLPFjJnWRoGB2n85ocr2. Task 1 writes the data contract spec `docs/superpowers/specs/2026-11-07-kanji-stroke-order-design.md`.

## Global Constraints

- Coverage: every kanji with KANJIDIC2 `grade` 1–8 (jōyō, 2,136) plus every kanji in `data/{verbs,grammar,counters,words,furigana,forms}.json`; `々` is never an entry.
- Sources are generation-time inputs only, never committed: KanjiVG `kanjivg-20260714.xml.gz` (release r20260714) and KANJIDIC2 `kanjidic2.xml.gz`, both in the session scratchpad `kanji-src/`.
- Licences: stroke paths KanjiVG © Ulrich Apel, CC BY-SA 3.0; readings/meanings KANJIDIC2 © EDRDG, CC BY-SA 4.0. Both credited in the file's `license` field, the sheet footer and Settings.
- Coordinates are KanjiVG's 109 × 109 box, y down; path `d` strings are copied verbatim.
- VerbKit stays Foundation/SwiftData only; wording lives in App. Never edit `.xcodeproj`; never run `make data-release` or `make sign-commit`; `data/manifest.sig` is not touched.
- Furigana on every kanji when on: Japanese text with kanji goes through `JapaneseText`; readings are kana.
- Liquid Glass on chrome only; the sheet content sits on `palette.paper` with `paperCard` surfaces; red (`palette.mark`) only for the current stroke, the start dot, a missed trace and the finished ring.
- Watch timing: 0.6 s draw per stroke, 0.7 s between strokes; Reduce Motion shows each stroke whole with no draw animation.
- Trace thresholds (109-unit box): fewer than 3 points or drawn length < 6 → ignored; reversed when `d(a,end)+d(b,start) < d(a,start)+d(b,end)`; start farther than 24 or end farther than 30 → wrong place.

## Review Focus

1. A KanjiVG `d` with packed numbers (`.5.5`, `0.98-0.19`, `1e-3`) or a lone `m` after `z` — every stroke in the bundled file must parse into a path that stays inside the box (Task 3, `testEveryBundledStrokeParsesInsideTheBox`).
2. Text with kanji the data lacks (`々`, a rare Word Bank kanji) — no stroke-order item, and the chip falls back to Jisho (Task 3, `testKanjiInTextSkipsUnknownAndRepeats`).
3. A tap with no drag in Trace — ignored, never shown as a miss (Task 4, `testATapIsTooShortNotAMiss`).
4. A synced `kanji.json` with a newer major `schema` — refused, the current data kept (Task 3, `testANewerMajorSchemaIsRefusedAndNotRecorded`).
5. A narrow window or AX5 text — the trace box shrinks to the width, the frame strip wraps, nothing clips (Task 6, simulator check at AX5 and on the smallest iPhone).

---

### Task 1: Kanji data builder, schema and data contract

**Files:**
- Create: `scripts/build_kanji.py`, `scripts/test_build_kanji.py`, `schema/kanji.schema.json`, `docs/superpowers/specs/2026-11-07-kanji-stroke-order-design.md`, `data/kanji.json` (generated)
- Modify: `scripts/test_schemas.py` (`NAMES` gains `"kanji"`), `schema/fixtures/invalid.json` (one kanji case), `schema/README.md` (table row), `Makefile` (a `kanji` target)

**Interfaces:**
- Produces: `data/kanji.json`:
  ```json
  {"schema": 1,
   "sources": {"kanjivg": "20260714", "kanjidic2": "<date_of_creation>"},
   "license": "Stroke paths: KanjiVG (c) Ulrich Apel, CC BY-SA 3.0. Readings and meanings: KANJIDIC2 (c) EDRDG, CC BY-SA 4.0.",
   "kanji": {"食": {"strokes": ["M52.75,10.5c…", "…"], "grade": 2,
                    "on": ["ショク", "ジキ"], "kun": ["く.う", "く.らう", "た.べる"], "meanings": ["eat", "food"]}}}
  ```
  Keys in code-point order; `grade` omitted when KANJIDIC2 has none or 9/10; `meanings` are the English `<meaning>`s (no `m_lang`), first 3; `on`/`kun` in file order, may be empty; `strokes` non-empty.
- Produces: `build_kanji.py` functions `read_kanjivg(path) -> dict[str, list[str]]`, `read_kanjidic(path) -> tuple[str, dict[str, dict]]` (creation date, entries), `app_kanji(data_dir) -> set[str]`, `build(kanjivg, kanjidic, data_dir) -> dict`, CLI `--kanjivg PATH --kanjidic PATH [--data-dir data]`.

- [ ] **Step 1: Write the failing tests** in `scripts/test_build_kanji.py` with tiny inline XML fixtures (gzip and plain):
  - `test_reads_only_base_kanji_ids`: `kvg:kanji_098df` kept with its 9 `d`s in stroke order (`-s1`…`-s9`, nested `<g>` flattened); `kvg:kanji_098df-Kaisho` skipped.
  - `test_kanjidic_entry_fields`: grade 2, on `["ショク","ジキ"]`, kun order kept, meanings English only and capped at 3; grade 9 → no `grade` key.
  - `test_selection_is_joyo_plus_app_kanji_without_repeat_mark`: data dir with `"人々が走る"` and a grade-9 kanji in app data → app kanji included, `々` absent, a grade-9 kanji not in app data absent.
  - `test_missing_source_entry_fails_naming_kanji`: app kanji absent from KanjiVG → `SystemExit` whose message contains the kanji.
  - `test_output_is_code_point_ordered_and_deterministic`: two builds → identical `json.dumps`.
- [ ] **Step 2:** `python3 -m unittest scripts.test_build_kanji -v` → FAIL (module missing).
- [ ] **Step 3: Implement `scripts/build_kanji.py`** with stdlib `xml.etree.ElementTree.iterparse` (KANJIDIC2 is 15 MB; clear elements as you go). Write with `json.dumps(doc, ensure_ascii=False, indent=1) + "\n"`; strokes stay one string each.
- [ ] **Step 4:** tests PASS.
- [ ] **Step 5: Schema** `schema/kanji.schema.json` in the README's keyword subset: `kanji` uses `propertyNames` `{"pattern": "^[一-鿿]$"}`; entry `additionalProperties: false`, `strokes` `minItems 1` of `^M[-0-9.,MmCcSsLlHhVvZz ]+$`, `grade` `enum [1,2,3,4,5,6,8]`, `on` items `^[ァ-ヺー]+$`, `kun` items `^-?[ぁ-ゖ]+(\.[ぁ-ゖ]+)?-?$`, `meanings` `minItems 0` strings `minLength 1`. Add `"kanji"` to `test_schemas.NAMES` and a fixture `{"name": "kanji stroke not a path", "dataset": "kanji", …}`; schema README row.
- [ ] **Step 6:** `make kanji KANJIVG=<scratchpad>/kanji-src/kanjivg-20260714.xml.gz KANJIDIC=<scratchpad>/kanji-src/kanjidic2.xml.gz` writes `data/kanji.json`. Expected: about 2,140 entries, under 3.5 MB; print the count and size into the ledger. `python3 -m unittest scripts.test_schemas` → PASS.
- [ ] **Step 7: Data contract spec** `2026-11-07-kanji-stroke-order-design.md`: file shape above, coordinate box, licence and share-alike note (the file is CC BY-SA; app code is not), coverage rule, how to regenerate (`make kanji`), reading notation (`.` marks okurigana, `-` affix), trace thresholds from Global Constraints, the sheet and its entry points.
- [ ] **Step 8: Commit** `scripts/build_kanji.py scripts/test_build_kanji.py schema/ scripts/test_schemas.py Makefile data/kanji.json docs/superpowers/specs/2026-11-07-kanji-stroke-order-design.md` — "Kanji data: build data/kanji.json from KanjiVG and KANJIDIC2".

### Task 2: Publish kanji.json through make data

**Files:**
- Modify: `scripts/update_data.py`, `scripts/test_update_data.py`, `scripts/data_merge.py` (`BUNDLED_NAMES` gains `"kanji"`), `scripts/test_data_merge.py` if it asserts the set, `Packages/VerbKit/Package.swift` (copy `Resources/kanji.json`, `Resources/kanji.manifest.json`), `docs/security/data-signing.md`, `README.md` data list if it lists files
- Generated: `data/manifest.json` (`kanji` entry), `Packages/VerbKit/Sources/VerbKit/Resources/kanji.json` and `kanji.manifest.json`

**Interfaces:**
- Consumes: `data/kanji.json` (Task 1).
- Produces: manifest entry `"kanji": {"version": "1.0.0", "sha256": …}` via the existing `optional_entry(existing, "kanji", kanji_bytes, …)`; the bundled pair written by the existing `bundled_data_dir` loop.

- [ ] **Step 1: Failing tests** in `test_update_data.py`:
  - `test_kanji_gets_a_manifest_entry_and_bundled_copy`: temp data dir with a minimal valid `kanji.json` → manifest `kanji.version == "1.0.0"`, bundled `kanji.json` byte-identical, sidecar has the hash.
  - `test_kanji_version_bumps_only_when_content_changes`.
  - `test_kanji_missing_a_kanji_used_in_data_fails`: a verb kanji absent from `kanji.json` → error naming it.
  - `test_kanji_schema_violation_fails` (stroke `"x"`).
- [ ] **Step 2:** `python3 -m unittest scripts.test_update_data -v` → the four FAIL.
- [ ] **Step 3: Implement**: read `data/kanji.json` as an input (never rewritten by `update_data.py`), validate with `json_schema` against `schema/kanji.schema.json`, check coverage with the same kanji test as `build_kanji.app_kanji` (import it), add the manifest entry and bundled pair; `--check` reports the same problems without writing.
- [ ] **Step 4:** tests PASS; `make test-py` all PASS.
- [ ] **Step 5:** `make data` then `make data-check` → clean; `git status` shows only manifest, bundled pair and code (no `manifest.sig`).
- [ ] **Step 6:** data-signing doc lists `kanji`; Package.swift resources. Commit — "Publish kanji.json as signed data with a bundled copy".

### Task 3: VerbKit kanji model, seventh sync service and store

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Kanji/KanjiEntry.swift`, `Kanji/KanjiDataFile.swift`, `Data/KanjiManifest.swift`, `Data/KanjiSyncService.swift`, `Persistence/KanjiDataEntity.swift`, `Persistence/KanjiPersisting.swift`, `Persistence/SwiftDataKanjiPersisting.swift`, `Store/KanjiStore.swift`, `Tests/VerbKitTests/KanjiSyncTests.swift`
- Modify: `Data/VerbDataFetching.swift`, `Data/GitHubVerbFetcher.swift` (`kanji` entry + ref), `Data/SyncStateStoring.swift`, `Data/UserDefaultsSyncStateStore.swift`, `Data/DataSyncStatus.swift` (`DataFile.kanji`, `"Kanji"`), `Persistence/VerbModelContainer.swift` (`KanjiDataEntity.self` in `verbModels`), test doubles (`MockVerbDataFetcher`, `InMemorySyncStateStore`), `RealDataFileTests.swift`, `GitHubVerbFetcherTests.swift`

**Interfaces:**
- Produces:
  - `public struct KanjiEntry: Equatable, Sendable { character: Character; strokes: [String]; grade: Int?; on: [String]; kun: [String]; meanings: [String] }`
  - `public struct KanjiDataFile: Sendable { static let supportedSchema = 1; entries: [Character: KanjiEntry]; static func decode(_ data: Data) throws(KanjiDataFile.LoadError) -> KanjiDataFile }`, `enum LoadError: Error, Equatable { case malformed, unsupportedSchema(Int) }` (minor bumps are not expressible — `schema` is an Int major).
  - `public struct KanjiManifest: Codable, Equatable, Sendable { version, sha256 }`
  - `public enum KanjiSyncResult { case upToDate, updated(manifest: KanjiManifest, data: Data) }`, `public struct KanjiSyncService { init(fetcher:syncState:); func sync() async throws -> KanjiSyncResult; func confirmSynced(_:); func acceptedVersion() -> String? }` — `unsupportedSchema` surfaces as the same "needs a newer app" error the forms catalogue uses (`FormCatalogue.LoadError.unsupportedSchema` → reuse the `DataSyncProblem` mapping); `malformed` → `VerbSyncError.malformedData`.
  - `public struct SyncedKanjiData { manifest: KanjiManifest; data: Data }`, `@MainActor protocol KanjiPersisting { func loadKanji() throws -> SyncedKanjiData?; func replaceKanji(with: SyncedKanjiData) throws }`
  - `@MainActor @Observable public final class KanjiStore { init(syncService:persisting:syncStatus:bundled: BundledKanji?); func start() async; func refresh() async; func entry(for: Character) -> KanjiEntry?; func kanji(in texts: [String]) -> [Character] }` — `kanji(in:)` is `KanjiExtraction.kanji(in:)` filtered to known entries. The cache holds raw bytes; decoding runs off the main actor, then the dictionary is assigned. A cached copy that fails its hash or decode falls back to the bundled one (same as `FormCatalogueStore`). `BundledKanji` = the bundled bytes + sidecar via `BundledData`'s loader generalised to raw data (add `BundledData.loadRaw(named:) -> (data, version, sha256)?` rather than decoding the whole file twice).

- [ ] **Step 1: Failing tests** in `KanjiSyncTests` (inline two-kanji JSON):
  - `testDecodesEntriesKeyedByCharacter` (grade nil when absent, empty kun allowed)
  - `testANewerMajorSchemaIsRefused` (`schema: 2` → `.unsupportedSchema(2)`), `testGarbageIsMalformed`
  - `testSyncVerifiesTheHashAndDecodesButDoesNotConfirm`, `testNoKanjiEntryIsUpToDate`, `testAHashMismatchIsMalformed`, `testAnOlderVersionThanOneAcceptedIsRefused`, `testANewerMajorSchemaIsRefusedAndNotRecorded`
  - `testOfflineFirstLaunchUsesTheBundledCopy`, `testAFailedSaveKeepsTheDataAndRetriesNextTime`, `testABadCachedCopyFallsBackToTheBundledOne`, `testSwiftDataRoundTripsTheSyncedData`
  - `testKanjiInTextSkipsUnknownAndRepeats`: store with 食 and 人; `kanji(in: ["人々が食べる", "食"])` → `["人", "食"]`.
  - In `RealDataFileTests`: `testBundledKanjiCoversEveryVerbKanji` (every kanji in bundled `verbs.json` has an entry) and `testEveryBundledStrokeParsesInsideTheBox` (each `d` → `SVGPathData.parse` non-empty, first element `.move`, every point within −5…114).
- [ ] **Step 2:** `cd Packages/VerbKit && swift test --filter 'KanjiSyncTests|RealDataFileTests'` → FAIL to compile.
- [ ] **Step 3: Implement** the types above, following `FormsSyncService` / `FormCatalogueStore` / `FormCatalogueEntity` exactly (persist first, then `confirmSynced`; `DataFileSync` where it fits). `DataFile.kanji` makes Settings show a Kanji row automatically.
- [ ] **Step 4:** filtered tests PASS; `make test-swift` all PASS (record the count).
- [ ] **Step 5: AGENTS.md**: "Six concrete sync services" → seven (add `Kanji`, kept concrete by the U12 decision); symbols table rows for `KanjiStore`, `KanjiEntry`. Commit — "VerbKit: kanji data, a seventh sync service and KanjiStore".

### Task 4: Stroke geometry, trace matcher and reading notation (VerbKit)

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Kanji/KanjiStroke.swift`, `Kanji/StrokeMatcher.swift`, `Kanji/KanjiTraceSession.swift`, `Kanji/KanjiReading.swift`, `Tests/VerbKitTests/KanjiStrokeTests.swift`

**Interfaces:**
- Consumes: `SVGPathData.parse`, `SVGPoint` (2c), `KanjiEntry` (Task 3).
- Produces:
  - `public struct KanjiStroke: Equatable, Sendable { init(d: String); elements: [SVGPathElement]; start: SVGPoint; end: SVGPoint; direction: StrokeDirection; labelPoint: SVGPoint }` — `start` = first move point, `end` = last element's end point; `labelPoint` = `start` moved 6 units against the initial tangent (start → first element's first control or end point), clamped to 4…105 on both axes.
  - `public enum StrokeDirection: Sendable { case right, downRight, down, downLeft, left, upLeft, up, upRight }` — 8 sectors of 45° around `end − start` (y down; `right` covers −22.5°…22.5°).
  - `extension KanjiEntry { var parsedStrokes: [KanjiStroke] }`
  - `public enum TraceVerdict: Equatable, Sendable { case accepted, tooShort, reversed, wrongPlace }`; `public enum StrokeMatcher { static func judge(_ drawn: [SVGPoint], against: KanjiStroke) -> TraceVerdict }` with the Global Constraints thresholds, checked in this order: tooShort, reversed, wrongPlace.
  - `public struct KanjiTraceSession: Equatable, Sendable { init(strokeCount: Int); private(set) step: Int; private(set) lastVerdict: TraceVerdict?; var isFinished: Bool; mutating func submit(_ verdict: TraceVerdict); mutating func reset() }` — `accepted` advances; `tooShort` leaves `lastVerdict` unchanged; others set it.
  - `public enum KanjiReading { static func display(_ kun: String) -> String }` — `"た.べる"` → `"た(べる)"`, `"-かた"` → `"かた"`, `"ひと-"` → `"ひと"`; on readings pass through.

- [ ] **Step 1: Failing tests** in `KanjiStrokeTests` using 食's real strokes 1, 4 and 9 (from Task 1's data):
  - `testStartEndAndDirection`: stroke 1 start (52.75, 10.5), end (14, 51.5), `.downLeft`; stroke 9 `.downRight`.
  - `testLabelPointStaysInTheBox`: a stroke starting at (2, 2) → label within 4…105.
  - `testAcceptsATraceNearTheStroke`, `testATapIsTooShortNotAMiss` (one point, and three points within 2 units), `testReversedTraceIsReversed`, `testFarStartIsWrongPlace` (start 30 away), `testShortTickAtTheStartIsWrongPlace` (end 35 from the expected end).
  - `testSessionAdvancesOnlyOnAccepted`, `testSessionFinishesAfterTheLastStroke`, `testResetStartsOver`.
  - `testKunNotation` (the three cases above).
- [ ] **Step 2:** `swift test --filter KanjiStrokeTests` → FAIL to compile.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** PASS; `make test-swift` all PASS.
- [ ] **Step 5:** AGENTS.md rows for `KanjiStroke`, `StrokeMatcher`, `KanjiTraceSession`, `KanjiReading`. Commit — "VerbKit: stroke geometry, trace matcher and kun notation".

### Task 5: Stroke drawing views (App)

**Files:**
- Create: `App/UI/SVGPath.swift`, `App/Kanji/KanjiStrokeCanvas.swift`
- Modify: `App/Launch/SealView.swift` (use the shared conversion)

**Interfaces:**
- Consumes: `KanjiStroke` (Task 4).
- Produces:
  - `extension Path { init(svg elements: [SVGPathElement]) }` — moved out of `SealView`'s private helper, unchanged behaviour.
  - `struct KanjiStrokeShape: Shape` — one stroke scaled from the 109 box into `rect` (uniform scale, centred).
  - `struct KanjiStrokeCanvas: View { strokes: [KanjiStroke]; shown: Int; highlightsCurrent: Bool; showsNumbers: Bool; showsStartDot: Bool; lineWidth: CGFloat (in box units, default 4); animatesCurrent: Bool }` — draws the dashed centre guides in `palette.rule`, strokes before `shown − 1` in `palette.ink`, the current one in `palette.mark` drawn with `.trim(from: 0, to: progress)` animated 0.6 s ease-out when `animatesCurrent` and Reduce Motion is off, the rest in a faint `palette.rule`; numbers 1…`shown` at `labelPoint` (current in mark, others muted, 7 box units); start dot r 2.6 at the current stroke's `start`.

- [ ] **Step 1:** Move the conversion; build iOS (`xcodebuild -scheme JPVerbConjugation_iOS -destination 'generic/platform=iOS Simulator' build -quiet`) → succeeds; the launch hand-off still looks the same on the simulator (screenshot against 2c's).
- [ ] **Step 2:** Write `KanjiStrokeShape` and `KanjiStrokeCanvas` with a `#Preview` of 食 at `shown: 4`.
- [ ] **Step 3:** iOS and macOS builds succeed. Commit — "Kanji stroke canvas, sharing the seal's SVG path conversion".

### Task 6: The Watch/Trace sheet (App)

**Files:**
- Create: `App/Kanji/KanjiSheet.swift`, `App/Kanji/KanjiWatchView.swift`, `App/Kanji/KanjiTraceView.swift`, `App/Kanji/KanjiDisplay.swift`

**Interfaces:**
- Consumes: `KanjiStore`, `KanjiEntry`, `KanjiStroke`, `StrokeMatcher`, `KanjiTraceSession`, `KanjiReading` (Tasks 3–4), `KanjiStrokeCanvas` (Task 5), `VerbStore`, `openRoute`, `dismissOnLink`, `PaperButtonStyle`, `paperCard`, `Font.headword`.
- Produces:
  - `struct KanjiSheetRequest: Identifiable, Hashable { character: Character; mode: KanjiSheetMode }`, `enum KanjiSheetMode { case watch, trace }`
  - `extension View { func kanjiSheet(_ request: Binding<KanjiSheetRequest?>) -> some View }`
  - `KanjiDisplay`: `strokeSummary(_ entry:) -> String` ("9 strokes · Grade 2"; grade 8 → "Secondary school"; nil → strokes only), `directionPhrase(_ :StrokeDirection) -> String` ("goes down to the left", …), the trace messages, the credit line.

Copy (exact): segmented "Watch" / "Trace"; "Stroke 4 of 9"; "Red dot marks where it starts"; trace headline "Stroke 1 of 9" / "Well done"; sub "Start at the red dot. This stroke goes down to the left." / "All 9 strokes in order."; reversed "Other way round: this stroke goes down to the left. Try again."; wrong place "That is not stroke 3. Start at the red dot."; buttons "Hide guide" / "Show guide", "Start again"; readings card labels "On", "Kun", "In Verb Table"; footer "Stroke data: KanjiVG, CC BY-SA 3.0 · Readings: KANJIDIC2, CC BY-SA 4.0".

- [ ] **Step 1: Sheet chrome** — `NavigationStack` with toolbar: leading the kanji in `Font.headword(.title2)`, principal a segmented `Picker`, trailing a Done button (`checkmark`); `.presentationDetents([.large])`; content on `palette.paper`, `.themedRoot()` not repeated (the environment carries the palette).
- [ ] **Step 2: Watch** — 200 pt canvas (`min(200, width × 0.5)`) beside the 56 pt headword, first meaning list joined by ", ", and `strokeSummary`; controls row: previous / play-pause (ink-filled circle) / next, 48 pt, then "Stroke N of M" and the hint. Playback runs in `.task(id: isPlaying)` so dismissing cancels it; Next/Previous/frame taps stop playback. Frame strip: `LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))])` of 36 pt canvases (`lineWidth 6`, no numbers), the selected one outlined 2 pt ink. Readings `paperCard`: On/Kun rows (kun through `KanjiReading.display`, joined "・"), then "In Verb Table": up to 5 verbs whose `kanji` contains the character, each a row with `JapaneseText` of the verb's kanji spelling, its meaning in muted, `RowChevron`, `openRoute(.verb(id))`. The canvas is one accessibility element, label "食, stroke 4 of 9", with `accessibilityAdjustableAction` stepping strokes.
- [ ] **Step 3: Trace** — square canvas `min(width − 40, 350)`; `DragGesture(minimumDistance: 0)` collecting points converted to box units; on end, `StrokeMatcher.judge` then `session.submit`. Layers: faint guide (all strokes, toggleable), accepted strokes in ink, the live stroke in ink, a miss in mark dashed (3 2) plus the expected stroke thin mark at 0.6 opacity, the start dot and number when idle, a mark ring r 46 when finished. Marks row: a 30 pt cell per stroke, current outlined in ink, accepted ones ringed in mark. Buttons: `.paperSecondary` guide toggle, `.paper` Start again. VoiceOver: label "Tracing square for 食. Draw stroke 2 with your finger." and an accessibility action "Show this stroke" that switches to Watch at the current stroke.
- [ ] **Step 4:** iOS and macOS builds succeed. On the simulator, open the sheet from a temporary debug entry (or after Task 7) and check: Watch play/pause/step/frames, Trace accept/reverse/wrong place/tap, Hide guide, Start again; AX5 Dynamic Type and the smallest available iPhone (Review Focus 5); dark appearance; Reduce Motion. Screenshots into the scratchpad.
- [ ] **Step 5:** Commit — "Kanji sheet: watch the strokes and trace them".

### Task 7: Entry points, app wiring and docs

**Files:**
- Modify: `App/JPVerbConjugationApp.swift` (create, inject, start and refresh `KanjiStore`), `App/TextActions.swift`, `App/VerbDetailView.swift`, `App/WordBank/WordBankDetailView.swift`, `App/DataSyncSection.swift` (credit line under the rows), `App/SettingsView.swift` if Refresh data lists stores, `AGENTS.md` (`kanjiSheet`, `KanjiStrokeCanvas`, `Path(svg:)` rows), `docs/superpowers/specs/2026-11-06-paper-ink-redesign-design.md` (row 3 "(built)", status line)

**Interfaces:**
- Consumes: `KanjiStore.kanji(in:)` / `entry(for:)` (Task 3), `kanjiSheet(_:)` (Task 6).

- [ ] **Step 1: Wiring** — `KanjiStore` built like `FormCatalogueStore` in `JPVerbConjugationApp`, `.environment(kanjiStore)`, started with the other stores and refreshed by Settings' Refresh data.
- [ ] **Step 2: Text menus** — both `TextActions` and `TranslatableTextActions` read `@Environment(KanjiStore.self) private var kanji: KanjiStore?`; `let characters = kanji?.kanji(in: [text]) ?? []`. One character: "Stroke order of 食" (`paintbrush.pointed`) and "Practise writing it" (`pencil.and.scribble`). Two or more: a `Menu("Stroke order", systemImage: "paintbrush.pointed")` with one button per character (Watch). Placed after "Look up form". Both modifiers present `.kanjiSheet($kanjiRequest)` and clear it in `dismissOnLink`.
- [ ] **Step 3: Verb page** — after the tip card, a Kanji section when `kanji.kanji(in: [verb.kanji ?? ""])` is non-empty: `SectionHeader("Kanji", systemImage: "character.book.closed.ja", trailing: Text("Tap for stroke order"))`, a `WrappingFlowLayout` of 56 pt `paperCard` tiles with the character in `Font.headword(.title)`, accessibility label "食, stroke order".
- [ ] **Step 4: Word Bank chips** — tap opens the sheet when `kanji.entry(for:)` exists, else Jisho as today; caption "Tap a kanji for its stroke order." when any chip has data.
- [ ] **Step 5: Credit** — in Settings' data section footer: "Kanji stroke order from KanjiVG (CC BY-SA 3.0); readings and meanings from KANJIDIC2 (EDRDG, CC BY-SA 4.0)."
- [ ] **Step 6:** iOS and macOS builds succeed; on the simulator: long-press an example with one kanji and with several, the verb page Kanji section for 食べる, a Word Bank entry with a known and an unknown kanji, Settings shows the Kanji data row and the credit, airplane-mode first launch (bundled copy) still opens the sheet. `make test-swift` and `make test-py` PASS; `make data-check` and `make check-project` clean.
- [ ] **Step 7:** Docs (AGENTS.md rows, spec row 3 built). Commit — "Open the kanji sheet from text menus, the verb page and Word Bank chips".
