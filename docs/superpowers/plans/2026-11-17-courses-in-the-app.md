# Courses in the iOS App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Learners can pick a course written by a teacher or native speaker (or Genki, or nothing) in My course, follow its lessons of verbs, words, grammar, counters and examples, mark lessons done, and keep their edits and progress through course updates and withdrawals.

**Architecture:** `data/courses.json` becomes the eighth signed, bundled, synced data file, with its own concrete `CoursesSyncService` and a `CourseCatalogueStore` (VerbKit, UI-free). My course (`MyCourse`, already "edits over a linked lesson") grows from grammar ids to typed `ItemRef`s and from textbook links to textbook *or* course links, with done marks and the last-seen copy of each started course kept in the same on-device JSON. The App gets the picker, overview, start sheet, lesson screen, update and withdrawal surfaces, built from the existing paper components.

**Tech Stack:** Swift 6 / SwiftUI (iOS 26), SwiftData, XCTest in `Packages/VerbKit`, Python 3 stdlib tooling in `scripts/`, JSON Schema in `schema/`.

**Spec:** `docs/superpowers/specs/2026-11-08-review-site-polish-design.md` § Courses › "App design (step 8)" (approved 2026-11-17), with the file format in `docs/superpowers/specs/2026-11-17-courses-data-design.md`. Boards: canvas section "Courses in the app (iOS)" (`App…` boards). Read `AGENTS.md` before any task.

## Global Constraints

- iPhone only. iPad, macOS, watchOS and Android stay parked; keep shared code compiling for macOS but don't design for it.
- VerbKit stays UI-free; all wording lives in `App/` (a `CourseWording.swift` beside `GrammarDisplay.swift`).
- Stores are injected with `.environment(...)`; previews and tests build their own.
- Persist before confirming: the store saves the synced file, then calls `confirmSynced(_:)`.
- `CoursesSyncService` is a new concrete service using `SyncVerification` (U12). No generic sync service.
- `courses.json` is a cross-platform contract: no Apple-only assumptions; changes go in the docs spec.
- Copies are independent of their original; courses carry no textbook text; furigana on every kanji (`JapaneseText` for all Japanese).
- Feature PRs never touch `data/manifest.sig`. Any `data/` change is regenerated with `make data` and committed with everything it writes. Never run `make data-release`, `make sign-commit` or `make review-pull`.
- Use the existing components: `paperCard`, `FilterChip`, `LevelBadge`, `TypeLabel`, `VerbExampleCard`, `PaperButtonStyle`, `SectionHeader`, `RowChevron`, `PaperEmptyState`, `JapaneseText`, `speakOnTap`, `textActions`, `openRoute`.
- Notices are calm: no red (`palette.mark` is for marks only), no error or retry button in the picker; sync failures show only in Settings › Data.
- No TestFlight or App Store; nothing in this plan ships a build.

## Agreement with step 7 (checked against `feb67fd`, `claude/review-step7-2c2bf6`)

- **Shape agrees.** Step 7's approval snapshot is `{id, title, summary, levels, copied_from, follows, lessons:[{id,title,goal,note,textbook_lesson,items:[{kind,id,in?}]}]}`; its pull adds `revision`, `since`, `author` and `withdrawn`. That is the data draft's shape exactly. Item kinds map one-to-one (`example` with `in` = `verbs | grammar | counters`). `levels` is computed from items, which the app only reads.
- **Ids agree.** Course and lesson ids are 6 characters from a subset of `[a-z0-9]`, never reused; reordering keeps lesson ids; a copy gets fresh ids. The schema pattern `^[a-z0-9]{6}$` covers both.
- **Decided 2026-11-19 by the owner: step 8 PR 8.1 creates the file, schema and checks; step 7's PR 7E drops task E2 and its pull updates the existing file.**
- **The disagreement that was — when the file first appears.** Step 7 decision 14 says "the file and its manifest entry appear only with the first pull that has a course; no feature PR creates `data/courses.json`", and its PR 7E (task E2) writes the schema and `update_data.py` checks "when present". This plan needs the file **before** any course exists: the app's empty state ("No courses yet … They arrive with a data update") and offline-first launch both need a bundled, signed file; without one the app can only show "Getting courses…" forever, and the sync can't tell "nothing published" from "not fetched". **Proposal:** PR 8.1 creates an empty `data/courses.json` (+ schema, checks, manifest entry, bundled copy) and takes over step 7's task E2; step 7's pull (E3) then updates an existing file. This answers step 7's own open question 5 ("Step 7 or 8 for the file?") as "the schema and checks move to step 8's first PR". The owner decides; if they keep step 7's order instead, PR 8.1 shrinks to the app side and the app shows "No courses yet" when the manifest has no `courses` entry (Task 2 handles both).

## Owner decisions (2026-11-19)

- **courses.json timing:** "Empty file first, in PR 8.1". PR 8.1 adds the empty file, schema, checks, manifest entry and bundled copy, and takes over step 7's schema-and-checks task (PR 7E's task E2).
- **The six open questions:** "Keep all six". The recommendations below stand.
- **Building:** "Later, subagent-driven", except "build PR 8.1 in a separate session" now. PRs 8.2–8.6 wait until the owner says so.

## Open questions for the owner (boards' default in brackets; recommendation after) — decided: all six kept

1. Move My course out of the Grammar tab [stays; the Grammar tab's My course mode shows each lesson's grammar] — **keep the default.** The picker and lesson screens push from Settings › My course and from the Grammar tab's My course mode; a tab move can follow later without touching the model.
2. "Practise this lesson": one mixed quiz, or the existing quizzes limited to the lesson [one button] — **one button that opens the existing quizzes limited to the lesson.** The app has five separate quiz models and screens (verb forms, particles, connections, counters, verb pairs), each with its own question type, results and history tags; a mixed quiz is a new quiz engine. The button builds the options the lesson supports (`LessonPractice`, Task 9): with one, it opens that quiz directly; with several, a small dialog lists them ("Verb forms · 3 verbs", "Particles · 2 grammar", "Counters · 1 counter"). A mixed quiz can come later on top of `LessonPractice`.
3. Keep a withdrawn course's goals and notes [dropped] — **keep the default** (the file's own rule; the author's words leave with the course).
4. Is "done" wanted [yes] — **yes.**
5. Courses outside the learner's studied levels [all listed] — **all listed**, with `LevelBadge`s so the level is visible; no hidden-match row.
6. Must an example's verb or word be in the same lesson [no] — **no.** The example row links to its verb's page anyway.

Two smaller decisions this plan makes (tell me if you disagree):
- **Words have no page today** (Search covers verbs, grammar, counters and the Word Bank). A word item in a lesson is a row with its reading and meaning that speaks on tap and has the `textActions` menu; it isn't a link. A word page is a separate piece of work.
- **The picker's footnote** "Courses from the 10 November data" uses the newest `since` among the listed courses (the file carries no release date); it's hidden when there are no courses.

## Review Focus

1. **A course update arrives while a lesson or quiz is open** → nothing on screen moves; the change shows when the learner leaves (Task 10 freezes the resolved lesson on appear; quizzes already build their questions up front).
2. **A newer app's `courses.json` adds an item kind or credit role this build doesn't know** → the file still loads; unknown items are skipped and an unknown role reads "A reviewer" (Task 2 test `unknownKindAndRoleDecode`).
3. **An item leaves the data** (a verb id removed, an example dropped) → it disappears quietly from every lesson, and lesson counts match what's shown (Task 5 test `missingItemsAreSkipped`).
4. **The author removes a whole lesson** (course still offered) → the learner's lesson isn't lost: if they edited it or marked it done it becomes their own lesson, otherwise it disappears (Task 11 test `removedCourseLessonWithEditsBecomesOwn`).
5. **Old My course data from today's build** (grammar strings, `base` key, `removedBaseLessons`) → loads unchanged after the update, including renamed and reordered Genki lessons (Task 5 fixture test).

---

## PR split

| PR | Branch suffix | Tasks | Tests |
|---|---|---|---|
| 8.1 Contract | `courses-contract` | 1 | `make test-py`, `make data-check`, `make check` |
| 8.2 Sync and catalogue | `courses-sync` | 2–4 | `make test-swift`, `make check-project` |
| 8.3 My course model | `courses-my-course-model` | 5–6 | `make test-swift` |
| 8.4 Picker, overview, start | `courses-picker` | 7–8 | `make test-swift`, simulator check |
| 8.5 Lesson and practise | `courses-lesson` | 9–10 | `make test-swift`, simulator check |
| 8.6 Updates and withdrawals | `courses-updates` | 11–12 | `make test-swift`, simulator check |

Each PR builds, passes its tests and is reviewed on its own. 8.1 is a data PR (unsigned; the owner signs the batch later). 8.2 and 8.3 have no visible UI except the Settings › Data row. 8.4–8.6 are UI on top. Empty, offline and first-sync states are part of 8.4 (they're the picker's section states).

---

## PR 8.1 — Contract

### Task 1: `data/courses.json`, schema, checks, manifest entry, bundled copy, docs

**Files:**
- Create: `data/courses.json`, `schema/courses.schema.json`, `schema/fixtures/courses/` (valid and invalid fixtures, following the existing fixture layout), `docs/superpowers/specs/2026-11-17-courses-data-design.md` (status line and "As built" note only)
- Modify: `scripts/update_data.py` (docstring item 12, `build_manifest`, bundle writing), `scripts/test_update_data.py`, `scripts/test_schemas.py`, `schema/README.md`, `Packages/VerbKit/Package.swift` (`.copy("Resources/courses.json"), .copy("Resources/courses.manifest.json")`)
- Generated by `make data`: `data/manifest.json`, `Packages/VerbKit/Sources/VerbKit/Resources/courses.json`, `…/Resources/courses.manifest.json`

**Interfaces:**
- Produces: `data/courses.json` = `{"version": "1.0.0", "description": "Courses written by teachers and native speakers, approved on the review site.", "courses": [], "withdrawn": []}`; a `courses` manifest entry via `optional_entry(existing, "courses", courses_bytes, courses_version, ref)`; a bundled copy plus sidecar like `kanji`.
- Python: `check_courses(courses_doc, docs, books, published_doc) -> list[str]` where `docs` holds the loaded verbs, words, grammar and counters documents and `books` is grammar's `books`.

- [ ] **Step 1: Write failing tests** in `scripts/test_update_data.py`:
  - `test_empty_courses_file_is_valid` — the empty document gives no problems.
  - `test_course_item_must_exist` — an item `{"kind":"verb","id":"nosuchverb"}` gives a problem naming the course id, lesson id and item.
  - `test_example_needs_in_and_must_live_there` — an example without `in`, or with an id that is in `verbs` but `in: "grammar"`, is a problem.
  - `test_duplicate_item_in_lesson`, `test_empty_lesson`, `test_course_without_lessons`.
  - `test_ids_unique` — duplicate course ids (across `courses` and `withdrawn`) and duplicate lesson ids within a course are problems.
  - `test_withdrawn_never_returns` and `test_revision_never_decreases` — against a `published_doc`; `None` published skips both.
  - `test_textbook_lesson_needs_follows_and_range` — `textbook_lesson` without `follows`, or outside `first_lesson..lessons` of `genki-1`, is a problem.
  - `test_courses_manifest_entry_and_bundle` — `build_manifest` with `courses_bytes` adds `"courses": {"version", "sha256"}`; the bundle step writes `courses.json` byte for byte and `courses.manifest.json`.
  - In `scripts/test_schemas.py`: the valid fixture passes, an id of 5 characters and a role `"admin"` fail.
- [ ] **Step 2:** `make test-py` → the new tests FAIL.
- [ ] **Step 3: Implement.** Schema from the data draft's Fields table (`id`/lesson id `^[a-z0-9]{6}$`, `revision` integer ≥ 1, `since` date pattern, `levels` enum `N5`–`N1`, `author.role` enum `teacher|native|owner`, `kind` enum, `in` enum, `lessons` and `items` `minItems: 1`, `additionalProperties: false` everywhere except the top level's `description`). `check_courses` implements the draft's "Checks" list; wire it into the run after the other files load, with the published copy read the way `published_verbs_doc` reads verbs. Treat `data/courses.json` as required from now on (the file exists). Add the docstring item and a `schema/README.md` row.
- [ ] **Step 4:** `make data`, then `make test-py`, `make data-check`, `make check` → all PASS. `git status` shows no change to `data/manifest.sig`.
- [ ] **Step 5:** Docs: set the data draft's status to "File, schema and checks built (step 8, PR 8.1); export pending (step 7)" and note that the file starts empty. Commit: `data: add an empty courses.json with its schema and checks`.

---

## PR 8.2 — Sync and catalogue (VerbKit)

### Task 2: Course models

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Courses/CourseCatalogue.swift`, `…/Courses/ItemRef.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/CourseCatalogueTests.swift` (fixtures inline as JSON strings)

**Interfaces:**
- Produces:
  - `enum ItemKind: String, Codable, Sendable, CaseIterable { case verb, word, grammar, counter, example }`
  - `enum ExampleSource: String, Codable, Sendable { case verbs, grammar, counters }`
  - `struct ItemRef: Codable, Hashable, Sendable { var kind: ItemKind; var id: String; var source: ExampleSource? }` — JSON keys `kind`, `id`, `in`.
  - `struct CourseCredit: Codable, Hashable, Sendable { var name: String?; var role: CreditRole }`, `enum CreditRole: String { case teacher, native, owner, other }` — an unknown string decodes as `.other`.
  - `struct CopiedFrom: Codable, Hashable, Sendable { var title: String; var author: CourseCredit }`
  - `struct CatalogueLesson: Codable, Hashable, Sendable, Identifiable { id, title, goal: String; note: String?; textbookLesson: Int?; items: [ItemRef] }`
  - `struct CatalogueCourse: Codable, Hashable, Sendable, Identifiable { id: String; revision: Int; since: String; title, summary: String; levels: [JLPTLevel]; author: CourseCredit; copiedFrom: CopiedFrom?; follows: String? /* book id */; lessons: [CatalogueLesson] }` plus `func count(of kind: ItemKind) -> Int`.
  - `struct CoursesDataFile: Codable, Equatable, Sendable { var version: String; var courses: [CatalogueCourse]; var withdrawn: [String] }`

- [ ] **Step 1: Failing tests:** `decodesDraftExample` (the data draft's sample decodes; `follows` `{"book":"genki-1"}` → `"genki-1"`; the example item has `source == .verbs`); `emptyFileDecodes`; `unknownKindAndRoleDecode` (an item `{"kind":"phrase","id":"x"}` is dropped, the lesson keeps its other items; role `"editor"` → `.other`); `countsItemsByKind`; `encodesRoundTrip` (encode → decode equals, `in` key written only for examples).
- [ ] **Step 2:** `make test-swift` → FAIL (types missing).
- [ ] **Step 3:** Implement. Unknown kinds are skipped with a lossy item array decode in `CatalogueLesson.init(from:)`; a lesson left with no items is still kept (it shows "No items").
- [ ] **Step 4:** `make test-swift` → PASS. Commit: `VerbKit: courses.json models`.

### Task 3: Manifest, fetcher, sync service, persistence

**Files:**
- Create: `…/Data/CoursesManifest.swift`, `…/Data/CoursesSyncService.swift`, `…/Persistence/CoursesPersisting.swift`, `…/Persistence/CoursesEntity.swift`, `…/Persistence/SwiftDataCoursesPersisting.swift`
- Modify: `…/Data/VerbDataFetching.swift`, `…/Data/GitHubVerbFetcher.swift` (`ManifestFile` key `courses`, `coursesRef`), `…/Data/SyncStateStoring.swift`, `…/Data/UserDefaultsSyncStateStore.swift`, `…/Data/DataSyncStatus.swift` (`DataFile.courses`, title "Courses"), `…/Data/SyncVerification.swift` (doc comment: eight services), `…/Persistence/VerbModelContainer.swift` (`CoursesEntity.self` in `verbModels`), every test double conforming to `VerbDataFetching` / `SyncStateStoring`
- Test: `…/Tests/VerbKitTests/CoursesSyncServiceTests.swift`, `SwiftDataCoursesPersistingTests.swift`

**Interfaces:**
- Produces: `struct CoursesManifest { version, sha256 }`; `enum CoursesSyncResult { case upToDate, notPublished, updated(manifest: CoursesManifest, file: CoursesDataFile) }`; `struct CoursesSyncService { init(fetcher:syncState:); func sync() async throws -> CoursesSyncResult; func confirmSynced(_:); func acceptedVersion() -> String? }`; `protocol CoursesPersisting { func loadCourses() throws -> CoursesDataFile?; func replaceCourses(with: CoursesDataFile) throws }` (`@MainActor`); `CoursesEntity` stores the file as JSON in one row like `CountersEntity`.
- `notPublished` = the manifest has no `courses` entry (only possible if the owner keeps step 7's order; see "Agreement with step 7").

- [ ] **Step 1: Failing tests** mirroring `CountersSyncService`'s: `returnsNotPublishedWithoutEntry`, `rejectsRollback` (throws `VerbSyncError.untrusted`), `upToDateWhenSameManifest`, `rejectsHashMismatch` (`.malformedData`), `decodesAndRecordsNothing` (sync state unchanged until `confirmSynced`), `confirmRecordsManifestAndVersion`; persistence round trip in memory (`VerbModelContainer.makeInMemory()`).
- [ ] **Step 2:** `make test-swift` → FAIL.
- [ ] **Step 3:** Implement following `CountersSyncService` and `SwiftDataCountersPersisting` line for line; decode with `SyncVerification.decode`.
- [ ] **Step 4:** `make test-swift` → PASS. Commit: `VerbKit: courses sync service and persistence`.

### Task 4: `CourseCatalogueStore`, app wiring, Settings › Data row

**Files:**
- Create: `…/Store/CourseCatalogueStore.swift`
- Modify: `App/JPVerbConjugationApp.swift` (create, `installBundled()`, `start()` with the others, add to `refreshHandler`, `.environment`)
- Test: `…/Tests/VerbKitTests/CourseCatalogueStoreTests.swift`

**Interfaces:**
- Produces:
  ```swift
  @MainActor @Observable public final class CourseCatalogueStore {
      public enum Availability: Equatable { case loading, offlineWithoutFile, ready }
      public private(set) var courses: [CatalogueCourse]   // file order
      public private(set) var withdrawn: Set<String>
      public private(set) var availability: Availability
      public var latestRelease: String? { get }             // max `since`, for the picker footnote
      public init(syncService: CoursesSyncService, persisting: CoursesPersisting,
                  syncStatus: DataSyncStatus? = nil, bundled: BundledData<CoursesDataFile>? = nil,
                  isOnline: @escaping @MainActor () -> Bool = { true })
      public func installBundled()
      public func start() async
      public func refresh() async
      public func course(id: String) -> CatalogueCourse?
      public func isWithdrawn(_ id: String) -> Bool
  }
  ```
- `availability`: `.ready` once any file (bundled, cached or synced) is applied, or after a `notPublished` sync; before that `.loading` while a sync runs and online, `.offlineWithoutFile` when offline or a sync failed.

- [ ] **Step 1: Failing tests:** `installsBundledWhenNewer`, `bundledNotReinstalledWhenOlder`, `syncPersistsBeforeConfirm` (a persisting double that throws → sync state unchanged, `courses` unchanged, status records `couldNotSave`), `availabilityStates` (no bundle + failing fetch + offline → `.offlineWithoutFile`; then a successful sync → `.ready`), `notPublishedIsReadyAndEmpty`, `latestReleaseIsNewestSince`.
- [ ] **Step 2:** `make test-swift` → FAIL.
- [ ] **Step 3:** Implement on `DataFileSync.run` like `CountersStore`. Wire into the app; `BundledData<CoursesDataFile>.load(named: "courses")`; `isOnline` from `NetworkMonitor`.
- [ ] **Step 4:** `make test-swift`, `make check-project` → PASS; build the app for an iPhone simulator; Settings › Data lists "Courses" with the bundled version. Commit: `Courses: catalogue store and Settings › Data row`. Open PR 8.2.

---

## PR 8.3 — My course holds all five kinds

### Task 5: Typed items, course links and the migration

**Files:**
- Modify: `Packages/VerbKit/Sources/VerbKit/Courses/MyCourse.swift`, `…/Courses/CourseStore.swift`
- Create: `…/Courses/KnownItems.swift`, `…/Courses/CourseContext.swift`
- Test: `…/Tests/VerbKitTests/MyCourseTests.swift` (update), `MyCourseMigrationTests.swift` (new), fixture `…/Tests/VerbKitTests/Fixtures/myCourse-v1.json` (listed in the test target's `resources` in `Package.swift`; copy today's encoding: two Genki lessons, one renamed, one with `added`, `removed` and `order`, a custom lesson, one `removedBaseLessons` key)

**Interfaces:**
- Produces:
  - `struct CourseLessonKey: Codable, Hashable, Sendable { var course: String; var lesson: String }`
  - `enum LessonSource: Codable, Hashable, Sendable { case textbook(LessonKey); case course(CourseLessonKey) }`
  - `CourseLessonEdit`: `source: LessonSource?` (replaces `base`), `name: String?` (nil = follow the source's title; custom lessons always set it), `added/removed/order: [ItemRef]`.
  - `MyCourse`: `format: Int` (= 2), `baseBookIDs`, `courseIDs: [String]` (started courses, in start order), `lessons`, `removedSources: [LessonSource]` (replaces `removedBaseLessons`), `done: Set<DoneKey>`, `seen: [String: CatalogueCourse]` (last-seen copy per started course; used in Task 11).
  - `enum DoneKey: Codable, Hashable, Sendable { case source(LessonSource); case own(UUID) }`
  - `struct KnownItems: Sendable { init(verbs: [Verb], words: [Word], grammar: [GrammarPoint], counters: [Counter]); func contains(_ ref: ItemRef) -> Bool }` — example ids per source file.
  - `struct CourseContext: Sendable { var points: [GrammarPoint]; var textbooks: [Textbook]; var catalogue: [CatalogueCourse]; var known: KnownItems }`
  - Resolved `CourseLesson`: `id: UUID`, `name: String`, `source: LessonSource?`, `items: [ItemRef]`, `var grammarIDs: [String]` (computed), `unreviewed: Bool`, `goal: String?`, `note: String?` (course lessons whose course is offered), `isDone: Bool`.
  - Every `MyCourse` method that took `points:textbooks:` now takes `in context: CourseContext`; `add`/`remove`/`setOrder` take `ItemRef`s.
  - `lessonTag(for grammarID:in:)` keeps its meaning (first lesson holding that grammar point).
- Course lessons resolve like textbook lessons: (catalogue lesson items − `removed`) + `added`, then `order`, then filtered by `known`. Lesson ids for course lessons with no edit are derived like `lessonID(for:)` from `"course:<course>:<lesson>"`. Pending course lessons (in a started course, no edit, not in `removedSources`) come after the stored lessons, in course order.

- [ ] **Step 1: Failing migration tests** (`MyCourseMigrationTests`): `decodesV1Fixture` — every lesson, name, order, added and removed id comes back as `.grammar` `ItemRef`s, `base` → `.textbook`, `removedBaseLessons` → `removedSources`, `done` empty, `courseIDs` empty; `v1ResolvesIdentically` — the resolved grammar ids per lesson equal what today's code resolves for the same fixture and data (record the expected arrays in the test); `writesV2AndRereads` — encode → decode is equal and the JSON has `"format":2` and no `base` key; `unreadableStaysNil` — garbage under `myCourse` still loads as no course (today's behaviour).
- [ ] **Step 2: Failing model tests** (`MyCourseTests`, extending today's): `courseLessonFollowsCourse` (an added catalogue item appears without an edit); `learnerEditsSurviveUpdate` (removed item stays removed, added item stays, order kept); `authorRemovedItemStaysIfLearnerAdded`; `deletedCourseLessonStaysDeleted`; `missingItemsAreSkipped` (an `ItemRef` not in `known` disappears from `items` and from counts); `renameOverridesThenFollowsNil`; `pendingCourseLessonsAfterStored`.
- [ ] **Step 3:** `make test-swift` → FAIL.
- [ ] **Step 4:** Implement. `MyCourse.init(from:)` reads either format: if `format` is absent it is v1 (strings, `base`, `removedBaseLessons`). Encoding writes only v2. `CourseStore` keeps the `myCourse` key and re-saves after loading a v1 value so the conversion happens once.
- [ ] **Step 5:** Update every App caller (`MyCourseView`, `GrammarListView`, `GrammarDetailView`) to build a `CourseContext` (a small `@MainActor` helper `CourseContext.current(verbStore:wordsStore:countersStore:catalogue:)` in `App/Grammar/`) and to use `lesson.grammarIDs` where they showed grammar. The Grammar tab's My course mode still shows only each lesson's grammar (open question 1's default).
- [ ] **Step 6:** `make test-swift` → PASS; build the app; existing My course looks the same. Commit: `My course: typed items and course lessons, with the v1 migration`.

### Task 6: Starting, adding and done marks

**Files:**
- Modify: `…/Courses/MyCourse.swift`, `…/Courses/CourseStore.swift`
- Test: `MyCourseTests.swift`

**Interfaces:**
- Produces on `MyCourse`: `static func starting(course: CatalogueCourse) -> MyCourse`; `mutating func addCourse(_ course: CatalogueCourse)` (appends an edit per lesson after the current lessons, records `courseIDs`, stores `seen[course.id]`); `mutating func addBook(_ id: String, in: CourseContext)`; `mutating func setDone(_ done: Bool, lesson: UUID, in: CourseContext)`; `func progress(in: CourseContext) -> (done: Int, total: Int)` and the same per source group; `func nextLesson(in:) -> CourseLesson?` (first not done).
- `CourseStore`: `start(course:)`, `startOver(with course:)`, `add(course:)`, `add(book:)`, `setDone(_:lesson:)` — all save via `edit`.

- [ ] **Step 1: Failing tests:** `startingCourseMaterialisesLessons`; `addCourseKeepsExisting` ("Add after your lessons": the 12 Genki lessons and their edits are unchanged and come first); `startOverReplaces` (lessons, edits and done marks gone; quiz history isn't part of `MyCourse`, assert nothing else is touched in defaults); `doneKeyedBySource` (done for a Genki lesson is `.source(.textbook)`; for a custom lesson `.own(id)`); `doneSurvivesCourseUpdate` (the catalogue lesson gains an item → still done); `progressCounts`.
- [ ] **Step 2:** `make test-swift` → FAIL. **Step 3:** implement. **Step 4:** `make test-swift` → PASS. Commit: `My course: start from a course, add after, done marks`. Open PR 8.3.

---

## PR 8.4 — Picker, overview, start sheet, and their states

### Task 7: "Choose a course" picker with its section states

**Files:**
- Create: `App/Courses/CoursePickerView.swift`, `App/Courses/CourseCard.swift`, `App/Courses/CourseWording.swift`, `Packages/VerbKit/Sources/VerbKit/Courses/OpenedCourses.swift`
- Modify: `App/Grammar/MyCourseView.swift` (the no-course state becomes the picker; a "Add lessons from a course" row opens it when a course exists), `App/JPVerbConjugationApp.swift` (inject `CourseCatalogueStore`)
- Test: `…/Tests/VerbKitTests/OpenedCoursesTests.swift`

**Interfaces:**
- Consumes: `CourseCatalogueStore.courses/availability/latestRelease`, `VerbStore.textbooks`.
- Produces: `struct OpenedCourses { init(defaults: UserDefaults); func isNew(_ id: String) -> Bool; mutating func markOpened(_ id: String) }` (App Group key `courses.opened`); `enum CourseWording { static func credit(_: CourseCredit) -> String /* "Kenji · Teacher", "A teacher", "Yumi · Native speaker", "A native speaker"; owner reads "{name} · Owner" */; static func copied(_: CopiedFrom) -> String /* Copied from “…” by … */ }`; `CourseCard(course:isNew:)`.
- Copy (exact, from the boards): title "Choose a course"; intro "Pick where My course starts. You can rename, reorder and edit every lesson afterwards."; sections "Textbooks", "From teachers and native speakers" (sub: "Each one is checked by a second teacher and arrives with the app's data."), "Your own" with `.paperSecondary` "Start empty" and "Make your own lessons from scratch."; Genki rows "Lessons 1–12 · Grammar by lesson number" from `firstLesson…lessons`; textbook footnote "Lesson numbers only, never the book's text. We match the grammar ourselves and mark a lesson unreviewed until it is checked."; credit footnote "Credited the way each author chose: a public name with their role, or the role alone."; data footnote "Courses from the {d MMMM} data." from `latestRelease`.
- Section states (dashed card, `role` status, no button): `.loading` → "Getting courses…" / "The textbooks work in the meantime."; `.offlineWithoutFile` → "Courses download with the app's data" / "They'll appear here next time you're online. Nothing to do."; `.ready` with no courses → "No courses yet" / "Teachers and native speakers are writing the first ones. They arrive with a data update."; offline with courses → footnote "Offline. Courses from the {date} data; new ones come with the next update."
- Withdrawn courses never appear (they aren't in `courses`).

- [ ] **Step 1: Failing tests:** `OpenedCoursesTests.newUntilOpened`, `persistsAcrossInstances`. Add a `CourseWording` unit check by building it in a `#Preview` with every role (App has no test target; keep wording logic trivial).
- [ ] **Step 2:** `make test-swift` → FAIL. **Step 3:** implement; previews for the four section states with an in-memory catalogue store.
- [ ] **Step 4:** `make test-swift` PASS; run on an iPhone simulator, open Settings › My course with no course: the picker shows Genki I/II, "No courses yet" (the shipped file is empty) and "Start empty"; screenshot light and dark. Commit: `Courses: Choose a course picker`.

### Task 8: Overview and start sheet

**Files:**
- Create: `App/Courses/CourseOverviewView.swift`, `App/Courses/StartCourseSheet.swift`, `App/Courses/TextbookOverviewView.swift`
- Modify: `Packages/VerbKit/Sources/VerbKit/Navigation/Route.swift`, `Route+URL.swift` (`case course(String)`, `verbtable://course/<id>`), `App/OpenRouteAction.swift` / `RootView.swift` route handling, the route scheme docs (add the `course` route where `verbtable://counter` is documented in `docs/`)
- Test: `…/Tests/VerbKitTests/RouteURLTests.swift` (add `courseRouteRoundTrip`)

**Interfaces:**
- Consumes: `CourseStore.start(course:)/add(course:)/startOver(with:)/add(book:)`, `OpenedCourses.markOpened`.
- Overview copy: kicker "Course", title, credit line with `LevelBadge`s and "{n} lessons", summary; a five-cell count card (verbs, words, grammar, counters, examples; zero cells shown as 0); "Lessons" `SectionHeader` with trailing "in teaching order"; numbered lesson rows with goal and item count, each opening a read-only lesson preview (Task 10's view in preview mode); footnote "Open a lesson to look before you start. Nothing is added to My course until you tap Start."; about footnote "Written by {name or role}. Checked by a second teacher before it shipped." and "In the app since {since} · updated with the app's data."; pinned `.paper` "Start this course" with "Its {n} lessons go into My course, where you can edit them." For a course already started the button reads "Open in My course".
- Genki overview: the book's lessons that have mapped grammar, "{n} grammar" per lesson, same pinned button.
- Start sheet (only when My course exists): "You already have My course, with {n} lessons from {sources}. What should happen to them?" — options "Add after your lessons" (default; "The course's {m} lessons come after your {n}. Nothing you have changes.") and "Start over with this course" ("Your {n} lessons and your edits to them are removed. Quiz history, favourites and the Word Bank stay."); button "Add {m} lessons" or "Start over…", the latter confirmed once more with a destructive confirmation dialog.
- A `course(id)` route for a withdrawn or unknown id opens "No longer offered" (`PaperEmptyState`, "{title} isn't in the app any more. If you started it, its lessons are in My course." using `seen[id]?.title`, else "This course"), with "Open My course".

- [ ] **Step 1: Failing test** `courseRouteRoundTrip`. **Step 2:** FAIL. **Step 3:** implement. **Step 4:** `make test-swift` PASS; simulator: with a local test `courses.json` injected through a preview catalogue, open overview → Start with and without an existing course; screenshots. Commit: `Courses: overview, start sheet and course links`. Open PR 8.4.

---

## PR 8.5 — Lesson and practise

### Task 9: `LessonPractice`

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Courses/LessonPractice.swift`
- Test: `…/Tests/VerbKitTests/LessonPracticeTests.swift`

**Interfaces:**
- Produces: `enum LessonPracticeOption: Hashable, Sendable { case verbForms(verbIDs: [String]); case particles(grammarIDs: [String], verbIDs: [String]); case connections(grammarIDs: [String]); case counters(counterIDs: [String]) }` and `static func options(for items: [ItemRef], verbs: [Verb], grammar: [GrammarPoint], counters: [Counter]) -> [LessonPracticeOption]` — an option only when its builder (`buildQuestions(verbs:topics:count:)`, `buildParticleQuestions(grammar:verbs:count:)`, the connection questions `GrammarDetailView` builds, `buildCounterQuestions(counters:groups:kind:count:)`) returns at least one question for those items. Verbs of example items count toward `verbForms` only if the verb is itself in the lesson (open question 6). Words make no option.

- [ ] **Step 1: Failing tests:** `verbsOnlyGivesVerbForms`; `grammarWithBlanksGivesParticles`; `grammarWithoutConnectionsGivesNoConnections`; `wordsOnlyGivesNothing`; `orderIsVerbsParticlesConnectionsCounters`. **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS. Commit: `VerbKit: lesson practice options`.

### Task 10: Lesson screen

**Files:**
- Create: `App/Courses/CourseLessonView.swift`, `App/Courses/LessonItemRow.swift`
- Modify: `App/RootView.swift` (an environment action `startPractice(_ option: LessonPracticeOption)` that sets the existing quiz presentations — `pendingQuiz`, `particleQuestions`, `connectionQuestions` — and the counter quiz cover the Counters tab uses, moved up or duplicated in `RootView`), `App/Grammar/MyCourseView.swift` (lessons open `CourseLessonView`; rows show per-kind counts like "3 verbs · 1 word · 2 examples", "Edited" when the lesson has edits, `unreviewed` as today)

**Interfaces:**
- Consumes: `CourseLesson` (Task 5), `LessonPractice.options` (Task 9), `CourseStore.setDone`.
- `CourseLessonView(lessonID: UUID, mode: .myCourse | .preview(CatalogueCourse, lessonIndex: Int))`. On appear it resolves and **keeps** its `CourseLesson` in `@State`; it re-resolves on disappear/reappear only (Review Focus 1).
- Layout: nav title "Lesson {n} of {m}" with next/previous lesson buttons; course title (muted), lesson name, goal card "After this lesson you can" + goal; the note as a dashed card headed "{name or role}'s note"; `SectionHeader("In this lesson", trailing: "in teaching order")`; `FilterChip`s All, Verbs, Words, Grammar, Counters, Examples with counts (a chip with 0 hidden); items numbered in teaching order in one `paperCard` (verbs with `TypeLabel`, words, grammar with title, counters), examples in a ruled `paperCard` with the form underlined (`VerbExampleRow` for verb examples; grammar and counter examples use their existing example rows) and `speakOnTap`. Verb, grammar and counter rows `openRoute`; word rows aren't links (decision above). Footnote "Each item opens its own page: the verb table, the word, the grammar lesson or the counter. Examples speak on tap." — drop "the word," while words have no page.
- Bottom bar (glass bar like `quizAdvanceBar`): `.paper` "Practise this lesson" (one option → start it; several → `confirmationDialog` listing them with counts; none → disabled with footnote "Nothing to practise in this lesson yet.") and `.paperSecondaryInline` "Mark done" / "Done" (checkmark; `palette.good` when done). Preview mode hides the bar.

- [ ] **Step 1:** Build previews for a lesson with all five kinds, light and dark, furigana on and off. **Step 2:** `make test-swift` PASS (no VerbKit change here beyond Task 9). **Step 3:** simulator: start the test course, open lesson 1, filter by each chip, open a verb and a grammar point, speak an example, practise (single and multiple options), mark done and see My course's progress bar move; screenshots. Commit: `Courses: lesson screen with practise and done`. Open PR 8.5.

---

## PR 8.6 — Updates and withdrawals

### Task 11: Diff, acknowledge, withdraw (VerbKit)

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Courses/CourseChanges.swift`
- Modify: `…/Courses/MyCourse.swift`, `…/Courses/CourseStore.swift`
- Test: `…/Tests/VerbKitTests/CourseChangesTests.swift`, `MyCourseTests.swift`

**Interfaces:**
- Produces:
  - `struct LessonChange: Equatable, Sendable { var lessonID: String; var title: String; var added: [ItemRef]; var removed: [ItemRef]; var renamed: Bool }`
  - `struct CourseChanges: Equatable, Sendable { var newLessons: [CatalogueLesson]; var changed: [LessonChange]; var removedLessons: [CatalogueLesson]; var isEmpty: Bool; static func between(seen: CatalogueCourse, current: CatalogueCourse) -> CourseChanges }`
  - On `MyCourse`: `func pendingUpdates(in: CourseContext) -> [(course: CatalogueCourse, changes: CourseChanges)]` (started, offered, `current.revision > seen.revision`, changes not empty); `mutating func acknowledge(_ courseID: String, in:)` (sets `seen` to the current copy); `func withdrawnToConvert(in:) -> [String]`; `mutating func convertWithdrawn(in:) -> [String]` (returns titles for the one-time notice); `mutating func convertRemovedLessons(in:)`.
  - Lesson-level markers for the UI: `func marker(for lesson: CourseLesson, in:) -> LessonMarker?` with `enum LessonMarker { case new, updated(addedSinceDone: Int, addedCount: Int, learnerKeptRemoved: Int) }`.
- Conversion (withdrawal, and an author-removed lesson the learner edited or marked done): each affected edit becomes a custom lesson — `source = nil`, `name = override ?? seen title`, items = the resolution against the `seen` copy (so nothing silently drops), goal and note dropped, a `.source(...)` done mark re-keyed to `.own(id)`; `courseIDs` and `seen` drop the course once all its lessons are converted. An unedited, not-done removed lesson simply disappears.

- [ ] **Step 1: Failing tests:** `diffFindsAddedRemovedRenamedAndNewLessons` (the board's example: lesson 1 +顔を洗う, lesson 3 +勉強する +宿題, lesson 5 −売る, lesson 11 new); `sameRevisionNoUpdate`; `acknowledgeClearsNotice`; `doneLessonCountsNewSinceDone`; `withdrawnCourseBecomesOwnLessons` (names, items and done marks kept; goals gone; `courseIDs` no longer lists it); `withdrawnWithoutSeenCopyKeepsEditsOnly` (defensive: no `seen` → lessons keep only learner-added items); `removedCourseLessonWithEditsBecomesOwn`; `removedCourseLessonUntouchedDisappears`; `conversionRunsOnce`.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** `make test-swift` PASS. Commit: `My course: course updates, What changed and withdrawals`.

### Task 12: Notices and "What changed"

**Files:**
- Create: `App/Courses/CourseUpdateNotice.swift`, `App/Courses/WhatChangedSheet.swift`, `App/Courses/WithdrawnNotice.swift`
- Modify: `App/Grammar/MyCourseView.swift` (notices on top; groups under "Started from" by source with per-group "{d} of {n} done"; markers on lesson rows), `App/Courses/CourseOverviewView.swift` (the same update notice), `App/JPVerbConjugationApp.swift` or `RootView` (run `convertWithdrawn` / `convertRemovedLessons` after the catalogue applies a file, never while a lesson or quiz is presented — gate on the existing quiz presentation state and a `isLessonOpen` flag set by `CourseLessonView`)

**Interfaces:**
- Consumes: Task 11.
- Copy: update card "{course} was updated" / "{author} added a lesson and changed three. Your edits and done marks are kept." (sentence built from `CourseChanges` counts in `CourseWording`), buttons `.paperSecondaryInline` "See what changed" and "OK" (both acknowledge). Row markers: "New" pill (new lesson, "Lesson {n} · {k} items"), "Updated" pill with "1 new since you finished it" / "{k} new items" / "1 taken out by {author}; your copy stays". What changed sheet: title "What changed", sub "{course}, with the {date} data. Since you started it on {date}.", one block per lesson with `+`/`−` item rows (`JapaneseText` with readings), notes "Still marked done. Open it if you want to look at the new item." and "{author} took it out. You had added it yourself, so it stays in your lesson.", footer "Updates never touch your quiz history, favourites or Word Bank. A lesson you deleted from My course stays deleted." Withdrawn card "{course} is no longer offered" / "Its {n} lessons stay in My course as your own, with everything you marked done. They won't get updates." with "OK"; the converted group header reads "From {course}, by {credit}" under "Your lessons". No red anywhere.
- "Since you started it on {date}": store the start date — add `startedOn: [String: String]` (yyyy-MM-dd via `WordBankDates.day`) to `MyCourse` in this task, with a test that it's set by `starting(course:)`/`addCourse` and survives encoding.

- [ ] **Step 1:** Previews for each notice and the sheet, light and dark. **Step 2:** `make test-swift` PASS. **Step 3:** simulator: install a test catalogue at revision 1, start it, swap in revision 2 with the board's changes, check notice once, sheet contents, markers, then a file with the course in `withdrawn`: one notice, lessons converted, picker no longer lists it, `verbtable://course/<id>` opens "No longer offered". Screenshots. Commit: `Courses: update notice, What changed and withdrawal`. Open PR 8.6.

---

## Self-review notes

- Spec coverage: picker (T7), overview and per-kind counts (T8), lesson with chips, TypeLabel, ruled examples, speak, item links, practise, done (T9–T10), My course all five kinds and grouping (T5, T10, T12), start sheet both choices with second confirmation (T8), done marks and progress (T6), update notice, pills, What changed, author-removed-but-learner-added, deleted-stays-deleted, nothing moves (T5, T11, T12, Review Focus 1), withdrawal and old links (T8, T11, T12), bundled file, offline, first sync, empty (T1, T4, T7), Settings › Data failures (T4). Data draft: shape (T2), checks (T1), manifest and bundle (T1), concrete sync (T3), on-device keeping (T5, T6, T11).
- Known gaps, called out above: words have no page; the step 7 file-timing disagreement.
