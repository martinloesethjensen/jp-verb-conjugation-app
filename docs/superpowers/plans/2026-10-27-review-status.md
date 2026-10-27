# Review status for counters and grammar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A learner sees whether a counter or grammar point has been reviewed, and the owner can mark entries reviewed with a signed data change that un-reviews itself when the text is edited.

**Architecture:** An entry may carry `review: {by, on, sha256}`. The pipeline hashes the entry's own content (without generated fields and without the stamp), fails on a stale stamp, and `scripts/mark_reviewed.py` writes stamps. VerbKit decodes the optional field. The app shows a quiet capsule on the entry page, one count line under the lists, and a Settings > Data row with a switch.

**Tech Stack:** Python (unittest), Swift 6, SwiftUI, VerbKit (XCTest).

**Spec:** `docs/superpowers/specs/2026-10-27-review-status-design.md`. The owner chose all four recommendations on 2026-10-27: scope counters and grammar; a hash in the stamp; wording "Not yet reviewed" / "Reviewed"; reviewers `owner` and `teacher` only. iOS only.

## Global Constraints

- No `review` means unreviewed; the pipeline never writes a stamp itself.
- `sha256` is the SHA-256 of the entry's canonical JSON (`sort_keys=True`, compact separators, `ensure_ascii=False`) with `review` and, for a counter, the generated fields `readings`, `changed` and `distractors` removed. It must not depend on field order or on regeneration.
- `by` is `"owner"` or `"teacher"`; `on` is an ISO date (`YYYY-MM-DD`).
- Old builds and old caches keep working: `review` is optional everywhere.
- Every `data/` change, including stamps, is re-signed by the owner. This plan changes no stamps (the owner's first review pass is after it).
- The stage 2 and 3 "unreviewed" label on numbers above 10 stays as it is; it is about generated number readings, not an entry's prose.
- The app does not hash anything: `isReviewed` means a stamp is present, and the pipeline guarantees it is current.

## Review Focus

- Regenerating counters (`make data`) keeps a valid stamp valid, and editing an example sentence invalidates it with a message naming the entry. Task 1.
- A grammar point with no `review` and one with a stamp both decode; an unknown reviewer or a bad date is rejected by the pipeline. Task 1, Task 2.
- A list with nothing reviewed says "0 of N reviewed", not a blank. Task 3.
- The Show review status switch off hides the capsule and the list line but never the numbers label. Task 3.
- Hidden-by-level counters are not counted in "x of N counters reviewed". Task 3.

---

### Task 1: The pipeline

**Files:**
- Create: `scripts/mark_reviewed.py`, `scripts/test_mark_reviewed.py`
- Modify: `scripts/update_data.py`, `scripts/test_update_data.py`

**Interfaces:**
- Produces: in `update_data.py`: `REVIEWERS = ("owner", "teacher")`, `review_hash(entry, generated=())` -> hex string, `check_reviews(entries, kind, generated)` -> problems (shape, stale stamp, message `"<id> was edited after review on <date>: re-review it, or run scripts/mark_reviewed.py again"`), called from `run` for grammar and counters before anything is written. In `mark_reviewed.py`: `stamp_counters(doc, ids, by, on)` (mutates a counters doc) and `stamp_grammar_text(text, ids, by, on)` -> new file text (inserts or replaces a `"review": {...},` line right after the entry's `"id"` line, so the hand-formatted file keeps its layout), and a CLI `mark_reviewed.py <counters|grammar> <id>... --by teacher --on 2026-10-24` that writes the file and tells the owner to run `make data` and sign.

- [ ] **Step 1: Write failing tests.** In `test_update_data.py`: `test_review_hash_ignores_generated_fields_and_key_order`; `test_a_valid_stamp_passes`; `test_an_edit_after_review_is_reported` (message names the id and date); `test_bad_reviewer_or_date_is_reported`; `test_regenerating_counters_keeps_the_stamp_valid` (a `run` over a temp data dir with a stamped counter twice, outputs identical and no problems). In `test_mark_reviewed.py`: `test_stamp_counters_sets_a_valid_stamp`; `test_stamp_grammar_text_inserts_after_the_id_line_and_keeps_the_rest_byte_for_byte`; `test_restamping_replaces_the_line`; `test_unknown_id_is_an_error`.
- [ ] **Step 2: Run** `cd scripts && python3 -m unittest test_update_data test_mark_reviewed`; expect the new tests to fail.
- [ ] **Step 3: Implement** both files. Counters are rewritten with `dump_counters`.
- [ ] **Step 4: Run** `make test-py` and `make data-check`; expect PASS and no data change.
- [ ] **Step 5: Commit** `"Pipeline: per-entry review stamps"`.

### Task 2: VerbKit decodes the stamp

**Files:**
- Modify: `Packages/VerbKit/Sources/VerbKit/Models/Counter.swift`, `Models/GrammarPoint.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Models/ReviewStamp.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/ReviewStampTests.swift`

**Interfaces:**
- Produces: `public struct ReviewStamp: Codable, Hashable, Sendable { public var by: Reviewer; public var on: String; public var sha256: String }`, `public enum Reviewer: String, Codable, Sendable { case owner, teacher; public var displayName: String }` ("the owner", "a teacher"), `Counter.review: ReviewStamp?`, `GrammarPoint.review: ReviewStamp?` (both decoded with `decodeIfPresent`, default nil, init parameter default nil), `public protocol Reviewable { var review: ReviewStamp? { get } }` with `isReviewed`, and `public struct ReviewSummary: Equatable, Sendable { reviewed: Int; total: Int; latest: String? }` built by `ReviewSummary(_ items: [some Reviewable])` (latest = the greatest `on`).

- [ ] **Step 1: Write failing tests:** a counter and a grammar point decode without and with `review`; an unknown reviewer fails to decode; `ReviewSummary` over 3 items with 1 stamped gives 1 of 3 and that date, over none gives 0 of 0 and nil, over unstamped gives 0 of N and nil; `latest` is the greatest date.
- [ ] **Step 2: Run** `swift test --filter ReviewStamp`; expect failures.
- [ ] **Step 3: Implement** the types and conformances (`extension Counter: Reviewable`, same for `GrammarPoint`).
- [ ] **Step 4: Run** the filter, then `make test-swift`; expect PASS.
- [ ] **Step 5: Commit** `"VerbKit: counters and grammar points carry a review stamp"`.

### Task 3: The capsule, the sheet, the list line and the Settings row

**Files:**
- Create: `App/ReviewStatusPill.swift` (the capsule and its sheet), `App/ReviewSummaryLine.swift`
- Modify: `App/Counters/CounterDetailView.swift`, `App/GrammarDetailView.swift`, `App/Counters/CountersHomeView.swift`, `App/GrammarListView.swift`, `App/DataSyncSection.swift` (or `App/SettingsView.swift` if the section belongs there)

**Interfaces:**
- Consumes: `Reviewable`, `ReviewSummary`, `ReportProblemButton`.
- Produces: `@AppStorage("showReviewStatus", store: .appGroup) var showReviewStatus = true`; `ReviewStatusPill(item: String, review: ReviewStamp?, checked: [String], unchecked: [String])` (outlined amber capsule "Not yet reviewed", or a capsule with a check "Reviewed"; tapping opens a sheet saying what the pipeline checks automatically, what no one has checked, who reviewed it and when, and a Report a problem button); `ReviewSummaryLine(noun: String, summary: ReviewSummary)` ("12 of 30 counters reviewed"; "Not yet reviewed" when 0); Settings rows "Counters" and "Grammar" with the counts and the latest date, and a "Show review status" switch.

- [ ] **Step 1: Implement** the views and place the capsule next to the JLPT capsule on both pages (hidden when the switch is off), the line under the Counters directory and the Grammar list (counting only counters or points visible under the level settings), and the Settings rows.
- [ ] **Step 2: Build** the iOS app (`make project` first).
- [ ] **Step 3: Verify in the simulator:** a counter page shows "Not yet reviewed" and the sheet opens and closes; the Counters list says "0 of N counters reviewed"; Settings shows the rows; the switch off hides the capsule and the line.
- [ ] **Step 4: Commit** `"App: show whether a counter or grammar point has been reviewed"`.

### Task 4: Docs

**Files:**
- Modify: `docs/superpowers/specs/2026-10-27-review-status-design.md`, `docs/security/data-signing.md`, `README.md` (the data section, if it lists scripts)

- [ ] **Step 1:** Record the four decisions in the design, add an "As built" section and the owner's workflow (read the entries, `python3 scripts/mark_reviewed.py counters hon --by teacher --on <date>`, `make data`, `make sign-commit`).
- [ ] **Step 2: Run** `make test`, `make data-check`, `make check-project`; expect green.
- [ ] **Step 3: Commit** `"Review status: notes"`.
