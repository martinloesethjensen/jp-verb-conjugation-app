# Grammar Courses (milestone 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lessons know where Genki I and II teach them. A learner keeps an on-device "My course", started from a textbook or from nothing, and browses grammar "By lesson". Each grammar card shows its course lesson, flagged "unreviewed" until a person has checked the mapping.

**Architecture:** `grammar.json` gains a top-level `books` list and per-lesson `taught_in` references, validated by `update_data.py`. The books are synced and persisted next to the grammar points. A pure `MyCourse` value in VerbKit holds the learner's edits over the base mapping and resolves them against the current data, so data updates still flow in. `CourseStore` persists it as JSON in the app-group `UserDefaults`. The app adds Settings › Grammar › My course, a By level / By lesson switch on the Grammar tab, and a lesson tag on cards.

**Tech Stack:** Python 3 (`scripts/update_data.py`, unittest), Swift 6, SwiftData, SwiftUI (iOS 26), XCTest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-06-grammar-building-blocks-design.md` (Decisions › Courses; Data › Textbook mappings; VerbKit › Milestone 3; App › Grammar tab, card item 7, My course; Testing).

## Global Constraints

- Only lesson numbers and our own pattern names are stored, never a book's text or examples (spec).
- Every mapping in this plan is `"reviewed": false`. A card shows "unreviewed" for an unreviewed mapping (spec).
- `update_data.py` checks that each `book` exists and each `lesson` is within range (spec).
- My course is on-device in its own store, not the synced data. It is not synced across devices (spec, Out of scope).
- Old grammar JSON without `books` and `taught_in` must still decode (spec testing rule for new fields).
- `data/` changes must be re-signed by the owner (`python3 scripts/sign_manifest.py sign`) before merge. Never sign yourself.
- Commit only after `cd Packages/VerbKit && swift test` exits 0. Data tasks also run `python3 -m unittest discover -s scripts` and `python3 scripts/update_data.py --check`. App tasks also build: `xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination "generic/platform=iOS Simulator" build -quiet`. The line `error: the following command failed with exit code 0…` is a known false alarm.
- New `App/` files need `./scripts/generate-project.sh`. The `.xcodeproj` is git-ignored.
- iPad and macOS screen checks stay parked, but macOS must compile. The macOS build's existing signing and `LSSupportsOpeningDocumentsInPlace` errors are unrelated.
- Commit trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Decisions this plan makes (the spec leaves them open)

- **Books:** `genki-1` ("Genki I", "3rd", lessons 1–12) and `genki-2` ("Genki II", "3rd", lessons 13–23). Genki II numbers its lessons from 13, so a book has an optional `first_lesson` (default 1), and `lessons` is its last lesson number.
- **A course's base is a list of books** (`baseBookIDs`), so "Genki I + II" is one course.
- **The card's lesson tag comes from My course only.** With no course, cards show no tag. A course started from a textbook shows that textbook's lessons.
- **Mappings** (all unreviewed). A lesson may list several refs, and the first is where it starts:

  | id | taught_in |
  |---|---|
  | n-desu, node, hou-ga-ii | genki-1 L12 |
  | sugiru | genki-1 L12, genki-2 L20 |
  | teiru | genki-1 L7, genki-2 L21 |
  | potential | genki-2 L13 |
  | temiru | genki-2 L13, genki-2 L18 |
  | appearance | genki-2 L13, genki-2 L17 |
  | certainty | genki-2 L14, genki-2 L19 |
  | teshimau | genki-2 L15, genki-2 L18 |
  | obligation, ppoi | (none) |

## Review Focus

1. **A data update removes a lesson that My course lists.** The course keeps working and the lesson simply disappears. Pinned in Task 3: `testIdsMissingFromTheDataAreDropped`.
2. **A data update adds a mapping to a new lesson number of a base book.** It appears at the end of the course; a lesson the learner deleted stays deleted. Pinned in Task 3: `testNewBaseLessonsAppearButDeletedOnesStayDeleted`.
3. **The stored course is corrupt or from a newer build.** The app shows "no course" instead of crashing. Pinned in Task 3: `testCorruptStoredCourseLoadsAsNone`.
4. **Grammar hasn't synced yet on first launch.** You can't start a course from a book with nothing to map, and "By lesson" shows an empty state. Pinned in Task 4 (create buttons disabled while `verbStore.grammarPoints` is empty) and checked in Task 6.
5. **The learner edits a base lesson and the base mapping later changes.** Their removals and additions survive; new base ids still appear. Pinned in Task 3: `testEditsSurviveABaseMappingChange`.

---

### Task 1: Textbook mappings in the data pipeline

**Files:**
- Modify: `scripts/update_data.py` (`validate_grammar`, plus a new `check_books`)
- Modify: `scripts/test_update_data.py`
- Modify: `data/grammar.json` (top-level `books`; `taught_in` per the table)
- Modify: `data/manifest.json`, regenerated by `python3 scripts/update_data.py` (the grammar hash and version bump)

**Interfaces:**
- Produces, in `grammar.json`:
  - top-level `"books": [{"id", "title", "edition", "first_lesson"?, "lessons"}]`;
  - per point, optional `"taught_in": [{"book", "lesson", "reviewed"}]`.

- [ ] **Step 1: Write failing tests** in `scripts/test_update_data.py`, using the file's existing minimal-grammar-doc helper. Each case below asserts `validate_grammar(doc)` returns exactly that problem string; the last asserts it returns no problems:
  - `test_books_must_have_unique_ids`: two books with id `genki-1` → `"books: duplicate id genki-1"`.
  - `test_book_needs_title_and_lesson_range`: a missing `title` → `"books: genki-1 title missing"`; `first_lesson` 13 with `lessons` 12 → `"books: genki-1 lessons must be >= first_lesson"`.
  - `test_taught_in_book_must_exist`: `{"book":"minna-1","lesson":1,"reviewed":false}` → `"p: taught_in book 'minna-1' does not exist"`.
  - `test_taught_in_lesson_in_range`: genki-2 (13–23) with lesson 12 → `"p: taught_in genki-2 lesson 12 is outside 13-23"`.
  - `test_taught_in_reviewed_is_bool`: `"reviewed": "no"` → `"p: taught_in reviewed must be true or false"`.
  - `test_taught_in_no_duplicates`: the same ref twice → `"p: taught_in lists genki-1 lesson 12 twice"`.
  - `test_books_and_taught_in_are_optional`: a doc without either key → no problems.

- [ ] **Step 2: Run** `python3 -m unittest scripts.test_update_data -v 2>&1 | tail -15`. Expected: the new tests FAIL.

- [ ] **Step 3: Implement** `check_books(doc) -> list[str]` and call it from `validate_grammar`. It produces exactly the messages above; `first_lesson` defaults to 1.

- [ ] **Step 4: Edit `data/grammar.json`.**
  - Add `books` after `description`.
  - Add `taught_in` to each point from the table, after `jlpt`, with `"reviewed": false`.
  - Keep the file's existing formatting: two-space indent; short objects on one line in the style the file already uses for `{jp, en}`.
  - Run `python3 scripts/update_data.py`, then `python3 scripts/update_data.py --check` (expected exit 0).
  - Check the diff touches only the added keys and the manifest's grammar entry: `git diff --stat data/`.

- [ ] **Step 5: Run** `python3 -m unittest discover -s scripts 2>&1 | tail -3` and `cd Packages/VerbKit && swift test 2>&1 | grep -E "Executed .* tests" | tail -1`. Expected: OK, 0 failures. The Swift real-data hash test must pass against the regenerated manifest.

- [ ] **Step 6: Commit** `scripts/ data/` as "Grammar: Genki I and II lesson mappings (unreviewed)". Note for the PR: the owner must re-sign `data/`.

---

### Task 2: Textbooks and lesson refs in VerbKit, synced and persisted

**Files:**
- Modify: `Packages/VerbKit/Sources/VerbKit/Models/GrammarPoint.swift` (`GrammarPoint.taughtIn`, `GrammarDataFile.books`)
- Create: `Packages/VerbKit/Sources/VerbKit/Models/Textbook.swift`
- Modify: `Packages/VerbKit/Sources/VerbKit/Data/GrammarSyncService.swift` (the `.updated` case carries books)
- Modify: `Packages/VerbKit/Sources/VerbKit/Persistence/GrammarPersisting.swift` and its SwiftData implementation
- Create: `Packages/VerbKit/Sources/VerbKit/Persistence/TextbookEntity.swift`
- Modify: `Packages/VerbKit/Sources/VerbKit/Persistence/VerbModelContainer.swift` (add `TextbookEntity` to `verbModels`)
- Modify: `Packages/VerbKit/Sources/VerbKit/Store/VerbStore.swift` (`textbooks`)
- Tests: `GrammarDecodingTests`, `GrammarSyncServiceTests`, `SwiftDataGrammarPersistingTests`, `VerbStoreGrammarTests`, `RealGrammarDataTests` (update fakes for the changed protocol)

**Interfaces:**
- Consumes: Task 1's JSON shape.
- Produces:
  - `public struct Textbook: Codable, Hashable, Sendable, Identifiable`, with `id`, `title`, `edition: String?`, `firstLesson: Int` (JSON `first_lesson`, default 1), `lessons: Int` (last lesson number) and `func contains(lesson: Int) -> Bool`.
  - `public struct LessonRef: Codable, Hashable, Sendable`, with `book: String`, `lesson: Int`, `reviewed: Bool`.
  - `GrammarPoint.taughtIn: [LessonRef]` (JSON `taught_in`, default `[]`), and `GrammarDataFile.books: [Textbook]` (default `[]`).
  - `GrammarSyncResult.updated(manifest:points:books:)`.
  - `GrammarPersisting`: `loadAllTextbooks() throws -> [Textbook]`, plus `replaceAllGrammar(points: [GrammarPoint], textbooks: [Textbook]) throws`, which replaces `replaceAllGrammarPoints(with:)` everywhere.
  - `VerbStore.textbooks: [Textbook]`, loaded from cache and replaced on sync exactly when `grammarPoints` is.

- [ ] **Step 1: Write failing tests.**
  - `testOldGrammarJSONWithoutBooksOrTaughtInDecodes`: `books == []`, `taughtIn == []`.
  - `testBooksAndTaughtInDecode`: `first_lesson` absent gives 1; genki-2 has `firstLesson 13`; `contains(lesson: 12) == false` and `contains(lesson: 13) == true`.
  - Sync: `.updated` carries the decoded books.
  - Persistence: a round-trip of points plus textbooks, and replacing them removes the old textbooks.
  - `VerbStore`: after a sync, `textbooks` equals the synced books; on start it loads the cached textbooks.
  - Real data: `testEveryLessonRefPointsAtAKnownBookAndLesson`. Every `taughtIn` ref's book exists in `books`, `contains(lesson:)` is true, and `Set(books.map(\.id)) == ["genki-1", "genki-2"]`.

- [ ] **Step 2: Run** `cd Packages/VerbKit && swift test 2>&1 | grep -E "error:" | head`. Expected: compile errors for the missing types and members.

- [ ] **Step 3: Implement.** `TextbookEntity` mirrors `GrammarEntity`: a unique `id`, a `sortOrder`, and a JSON `payload`. Follow `GrammarEntity`'s comment on why a payload avoids migrations. Keep the persist-then-confirm order in `VerbStore.syncGrammar`.

- [ ] **Step 4: Run** the full `swift test` and the iOS build. Expected: 0 failures, and no real `error:` lines.

- [ ] **Step 5: Commit** as "Grammar: sync and keep textbooks with lesson refs".

---

### Task 3: MyCourse and CourseStore (VerbKit)

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Courses/MyCourse.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Courses/CourseStore.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/MyCourseTests.swift` and `CourseStoreTests.swift`

**Interfaces:**
- Consumes: `GrammarPoint.taughtIn`, `Textbook` (Task 2).
- Produces:
  - `public struct LessonKey: Codable, Hashable, Sendable`, with `book: String` and `lesson: Int`.
  - `public struct CourseLessonEdit: Codable, Hashable, Sendable, Identifiable`, with `id: UUID`, `name: String`, `base: LessonKey?`, `added: [String]`, `removed: [String]` and `order: [String]`.
  - `public struct CourseLesson: Equatable, Sendable, Identifiable`, with `id: UUID`, `name: String`, `base: LessonKey?`, `grammarIDs: [String]` and `unreviewed: Bool`.
  - `public struct MyCourse: Codable, Equatable, Sendable`, with `baseBookIDs: [String]`, `lessons: [CourseLessonEdit]` and `removedBaseLessons: [LessonKey]`, plus:
    - `static func starting(from bookIDs: [String], points: [GrammarPoint], textbooks: [Textbook]) -> MyCourse`. It materialises one edit per base lesson that has mapped points, ordered by book, then lesson number, and named `"<book title> · Lesson <n>"`. Empty `bookIDs` gives an empty course.
    - `func resolved(points: [GrammarPoint], textbooks: [Textbook]) -> [CourseLesson]`
    - `func lessonTag(for grammarID: String, points: [GrammarPoint], textbooks: [Textbook]) -> CourseLesson?`: the first resolved lesson containing the id.
    - mutating `addLesson(named: String) -> UUID`, `rename(_ id: UUID, to name: String)`, `deleteLesson(_ id: UUID)`, `add(_ grammarID: String, to lesson: UUID)`, `remove(_ grammarID: String, from lesson: UUID, points: [GrammarPoint])`, and `setOrder(_ ids: [String], in lesson: UUID)`.
  - `@Observable @MainActor public final class CourseStore`, with `init(defaults: UserDefaults)`, `course: MyCourse?`, `start(from bookIDs: [String], points:textbooks:)`, `edit(_ change: (inout MyCourse) -> Void)`, `clear()` and `static let defaultsKey = "myCourse"`.

**Resolution rules** (the algorithm the signatures leave open):
- **A base-linked lesson's ids:**
  - Start from the points whose `taughtIn` contains its key, in grammar-file order.
  - Remove `removed`, then append `added` ids not already present.
  - Reorder: the ids in `order` come first, in that order; the rest keep their order.
  - Drop ids that are not in `points`.
- **A custom lesson** (`base == nil`): `added` with `order` applied, dropping unknown ids.
- **`unreviewed`** is true when any included id is there because of an unreviewed base ref for that key.
- **Lesson order:**
  - First, `lessons` in stored order.
  - Then base lessons of `baseBookIDs` that have mapped points, no edit, and are not in `removedBaseLessons`. These come by book order, then lesson number, with a default name and a stable id derived from the key (UUID v5-style hash of `"book:lesson"`, or any deterministic scheme).
- **Editing:**
  - `deleteLesson` on a base-linked edit also appends its key to `removedBaseLessons`.
  - `remove` of a base id records it in `removed`; for an added id it deletes it from `added`.
  - Editing a not-yet-materialised base lesson (one that arrived with a data update) first materialises its edit in place: it is appended to `lessons` at the position it resolved to.

- [ ] **Step 1: Write failing tests.** Use small fixture points with `taughtIn`, and one fixture textbook pair `genki-1` (1–12) and `genki-2` (13–23).
  - `testStartingFromABookMakesOneLessonPerMappedLessonInOrder`: genki-1 with points at L7 and L12 gives names `["Genki I · Lesson 7", "Genki I · Lesson 12"]`; all are `unreviewed`.
  - `testStartingEmptyHasNoLessons`.
  - `testAddRenameDeleteCustomLesson`.
  - `testRemovingABaseIdAndAddingAnother`: L12 base `[node, hou]`; remove `node` and add `teiru` → `[hou, teiru]`.
  - `testSetOrderReorders`.
  - `testIdsMissingFromTheDataAreDropped`: resolving against points without `hou` drops it, with no crash.
  - `testNewBaseLessonsAppearButDeletedOnesStayDeleted`: start from genki-1 with L12 only; delete L12; new data maps a point to L7 → resolved names `["Genki I · Lesson 7"]`.
  - `testEditsSurviveABaseMappingChange`: remove `node` from L12; new data adds `sugiru` to L12 → `[hou, sugiru]` (node stays removed).
  - `testLessonTagIsTheFirstLessonContainingThePoint`.
  - `testCourseRoundTripsThroughJSON`.
  - CourseStore, with a throwaway suite `UserDefaults(suiteName:)`:
    - `testStartEditClearPersist`: a new store on the same defaults sees the edits; `clear` removes the key.
    - `testCorruptStoredCourseLoadsAsNone`: write `Data("x".utf8)` under the key → `course == nil`.

- [ ] **Step 2: Run** `swift test --filter "MyCourseTests|CourseStoreTests"`. Expected: compile errors.

- [ ] **Step 3: Implement** to the rules above.

- [ ] **Step 4: Run** the full `swift test`. Expected: 0 failures.

- [ ] **Step 5: Commit** as "Courses: My course as edits over textbook lessons".

---

### Task 4: Settings › Grammar › My course (App)

**Files:**
- Create: `App/Grammar/MyCourseView.swift` (the course editor), `App/Grammar/GrammarPointPicker.swift` (a sheet that picks grammar points to add)
- Modify: `App/SettingsView.swift` (a new `Section("Grammar")` with a `NavigationLink("My course")`)
- Modify: `App/JPVerbConjugationApp.swift` (create `CourseStore(defaults: .appGroup)` and inject it with `.environment` everywhere `verbStore` is injected, both scenes)

**Interfaces:**
- Consumes: `CourseStore`, `MyCourse`, `CourseLesson` (Task 3), `VerbStore.grammarPoints` and `.textbooks` (Task 2), `JapaneseText`.
- Produces: `struct MyCourseView: View` (no parameters; reads its environment).

- [ ] **Step 1: Build `MyCourseView`.**
  - **With no course:**
    - A "Start from" section with one toggle row per textbook. Selecting both makes "Genki I + II".
    - A "Create course" button, disabled while `verbStore.grammarPoints` is empty or no book is selected.
    - A "Start empty" button.
    - Footer: "Textbook lessons are matched by us and marked unreviewed until checked."
  - **With a course:**
    - **Lessons:** one `Section` per resolved lesson, headed by its name plus an "unreviewed" caption when `unreviewed`. It lists the points (`JapaneseText(point.title)`) with `.onDelete` (→ `remove`) and `.onMove` (→ `setOrder`).
    - **Lesson actions** (in the section header menu): "Add grammar…" (opens `GrammarPointPicker`, multi-select, → `add`), "Rename…" (an alert with a text field) and "Delete lesson" (`role: .destructive`).
    - **Toolbar:** `EditButton` and "Add lesson" (an alert with a name field).
    - **A last section:** "Reset course" (destructive, with a confirmation dialog "Reset My course? Your lessons and edits will be removed.", → `clear()`).
  - Empty lessons show a row "No grammar yet".

- [ ] **Step 2:** Add the Settings section and the environment injection. Run `./scripts/generate-project.sh`, then build iOS, then the macOS compile check.

- [ ] **Step 3: Commit** as "Courses: My course editor in Settings".

---

### Task 5: By lesson view and lesson tags (App)

**Files:**
- Modify: `App/GrammarListView.swift`: a segmented `Picker` with "By level" / "By lesson", persisted with `@AppStorage("grammarListMode", store: .appGroup)`.
- Modify: `App/GrammarDetailView.swift`: the lesson tag in the header.

**Interfaces:**
- Consumes: `CourseStore`, `MyCourse.resolved` and `lessonTag` (Task 3), `MyCourseView` (Task 4).

- [ ] **Step 1: By lesson.**
  - Show one section per resolved lesson, with the same row view the level list uses, so navigation is unchanged.
  - Search filters within the sections.
  - The level setting still hides points of hidden levels.
  - With no course, show `ContentUnavailableView("No course yet", systemImage: "books.vertical", description: Text("Set up My course to see grammar by lesson."))` with a button that opens `MyCourseView` in a sheet (not a pushed link; the split view's sidebar would push into the detail column).
  - "By level" is unchanged.

- [ ] **Step 2: Card tag.**
  - In `GrammarDetailView`'s header, when `lessonTag` returns a lesson, show a capsule with the lesson name and, if `unreviewed`, a second caption "unreviewed".
  - No course, or no lesson containing the point → nothing.

- [ ] **Step 3:** Build iOS, run the macOS compile check and `swift test`.

- [ ] **Step 4: Commit** as "Courses: grammar by lesson, and lesson tags on cards".

---

### Task 6: Simulator check, spec notes, PR

**Files:**
- Modify: the spec (Milestones: "3. **Courses (done <date>).**" plus an "As built (milestone 3)" list recording the Decisions section above).

- [ ] **Step 1: Check on the iPhone 17 simulator** (`F8A1F047-9215-4C1F-8202-661A87975FB9`; always pass `device`). The app syncs grammar from the published data on `main`, which has no books until this branch is signed and merged. So before merge, check steps 1, 3 (with "Start empty" and custom lessons) and 5. The textbook steps (2 and 4) are covered by the unit tests, and the owner checks them on device once the signed data is live.
  1. Grammar tab › By lesson with no course → the empty state; its button opens My course.
  2. Settings › Grammar › My course → select Genki I + II → Create → lessons appear ("Genki I · Lesson 7", "Genki I · Lesson 12", …), each "unreviewed".
  3. Remove ので from Lesson 12, add っぽい, reorder, rename. Kill and relaunch the app → the edits are still there.
  4. By lesson shows the course; the 〜ので card's tag is gone after removing it, and the んです card shows "Genki I · Lesson 12 · unreviewed".
  5. Reset course → By lesson returns to the empty state.

- [ ] **Step 2:** Update the spec and commit as "Docs: grammar milestone 3 as built".

- [ ] **Step 3:** Push the branch and open a PR. The body says `data/` changed and must be re-signed by the owner before merge, and that every Genki mapping is unreviewed.
