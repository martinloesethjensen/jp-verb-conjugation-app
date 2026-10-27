# Counters: a bundled fallback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Counters tab works on a first launch with no network, by shipping a copy of `counters.json` in the app and preferring a synced copy only when it is newer.

**Architecture:** Mirrors `forms.json` (#156): `update_data.py` writes a byte-for-byte copy of `data/counters.json` and a `counters.manifest.json` (version and hash) into the VerbKit resources and `--check` fails on drift. `CountersStore` starts on the bundled file, switches to the cached or synced one only when its version is not older than the bundled version, and the sync service never replaces the bundled file with an older one. Counters are plain data, so none of the forms catalogue's schema machinery is needed.

**Tech Stack:** Python (unittest), Swift 6, VerbKit (XCTest).

**Spec:** requested by the owner on 2026-10-27 ("the fallback would be appropriate"); modelled on the forms change in commit e448ef0.

## Global Constraints

- The bundled copy is generated, never hand-edited: `make data` writes it and `make data-check` fails if it differs from `data/counters.json`.
- A synced copy is used only if its signed manifest version is not older than the bundled version; a bad or older copy never replaces a good one and never stops the app.
- No UI change: a first launch shows the bundled counters, and the "Counters Not Downloaded Yet" screen is left for a broken bundle only.
- The bundle adds the size of `counters.json` (about 190 KB) to the app.

## Review Focus

- A cache older than the bundled version (after an app update) is ignored in favour of the bundle. Task 3.
- A remote manifest older than the bundled version is ignored, and one equal to it downloads nothing. Task 3.
- A missing or unreadable bundled resource gives an empty store, not a crash. Task 2.
- The bundled copy cannot drift from `data/counters.json`. Task 1 and Task 2.
- A first launch with the network down shows the bundled counters. Task 3.

---

### Task 1: The pipeline writes the bundled copy

**Files:**
- Modify: `scripts/update_data.py` (`run`, a `DEFAULT_BUNDLED_COUNTERS_PATH`, `--bundled-counters-path`)
- Modify: `scripts/test_update_data.py`

**Interfaces:**
- Produces: `run(..., bundled_counters_path=None)` writes and checks `<dir>/counters.json` and `<dir>/counters.manifest.json` (`{"version", "sha256"}` of the manifest's `counters` entry, no `ref`); `--check` reports "the bundled counters.json" when either differs; `None` leaves them alone.

- [ ] **Step 1: Write failing tests** next to the existing bundled-forms tests: after a run with `bundled_counters_path=tmp/counters.json` both files exist, the copy equals `data/counters.json` byte for byte and the manifest holds the current counters version and hash; a `check=True` run passes; editing the copy makes `check=True` fail with "the bundled counters.json"; with `None` nothing is written.
- [ ] **Step 2: Run** `cd scripts && python3 -m unittest test_update_data`; expect the new tests to fail.
- [ ] **Step 3: Implement** it beside the forms handling in `run` (same `differs` helper and message style), default path `Packages/VerbKit/Sources/VerbKit/Resources/counters.json`.
- [ ] **Step 4: Run** `make data`, then `make test-py` and `make data-check`; expect PASS, and two new files under `Resources/`.
- [ ] **Step 5: Commit** `"Counters: the pipeline writes a bundled copy"`.

### Task 2: Bundle it and read it

**Files:**
- Modify: `Packages/VerbKit/Package.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Data/BundledCounters.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/RealCountersDataTests.swift`, new `BundledCountersTests.swift`

**Interfaces:**
- Produces: `public struct BundledCounters: Equatable, Sendable { public var file: CountersDataFile; public var manifest: CountersManifest; public static func load(bundle: Bundle = .module) -> BundledCounters? }`; `nil` when a resource is missing or unreadable, never a crash.

- [ ] **Step 1: Write failing tests:** `BundledCountersTests.testTheBundledCopyLoads` (28 or more counters, a non-empty manifest version); `testAMissingResourceIsNil` (an empty temporary bundle); `testAnUnreadableFileIsNil`; in `RealCountersDataTests`, `testTheBundledCopyEqualsTheDataFile` (the resource bytes equal `data/counters.json`, and the manifest's version and hash equal the `counters` entry of `data/manifest.json`).
- [ ] **Step 2: Run** `swift test --filter "BundledCounters|RealCountersData"`; expect failures.
- [ ] **Step 3: Implement** `BundledCounters.load` and add `.copy("Resources/counters.json"), .copy("Resources/counters.manifest.json")` to the target's resources; load by decoding both with `JSONDecoder`.
- [ ] **Step 4: Run** the same command; expect PASS.
- [ ] **Step 5: Commit** `"VerbKit: bundle a copy of the counters"`.

### Task 3: The store and the sync rules

**Files:**
- Modify: `Packages/VerbKit/Sources/VerbKit/Data/CountersSyncService.swift`, `Store/CountersStore.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/CountersStoreTests.swift`, `CountersSyncTests.swift`

**Interfaces:**
- Consumes: `BundledCounters`, `DataVersion.isOlder(_:than:)`, `syncState.lastSyncedCountersManifest()`.
- Produces: `CountersSyncService.init(fetcher:syncState:bundled: CountersManifest? = nil)`; with a bundled manifest, `sync()` returns `.upToDate` for a remote manifest equal to it or older than it. `CountersStore.init(syncService:persisting:syncStatus:bundled: BundledCounters? = nil)`; `start()` applies the bundled file first, then the cached file only if the last synced manifest version is not older than the bundled version, then syncs.

- [ ] **Step 1: Write failing tests:** (a) `testAFirstLaunchWithoutNetworkShowsTheBundledCounters` (empty cache, a fetcher that fails: `store.counters` is the bundled list); (b) `testANewerCacheWinsOverTheBundle`; (c) `testACacheOlderThanTheBundleIsIgnored` (last synced version below bundled: bundled counters shown, and the stale cache is not applied); (d) `testASyncNewerThanTheBundleReplacesIt`; (e) in `CountersSyncTests`, `testARemoteEqualToTheBundleDownloadsNothing` (the fetcher's data call is never made) and `testARemoteOlderThanTheBundleIsIgnored`; (f) `testWithoutABundleNothingChanges` (existing tests keep passing with `bundled: nil`).
- [ ] **Step 2: Run** `swift test --filter "CountersStore|CountersSync"`; expect failures.
- [ ] **Step 3: Implement** the rules above; a failed cache load or sync leaves the bundled (or already applied) counters, as today.
- [ ] **Step 4: Run** the filter, then `make test-swift`; expect PASS.
- [ ] **Step 5: Commit** `"VerbKit: counters start on the bundled copy"`.

### Task 4: Wire it up and document it

**Files:**
- Modify: `App/JPVerbConjugationApp.swift` (and the macOS and widget entry points if they build a `CountersStore`), `README.md`

- [ ] **Step 1: Pass `BundledCounters.load()`** to both the `CountersSyncService` (its manifest) and the `CountersStore` wherever they are built.
- [ ] **Step 2: Build** the iOS app, and run `make test`, `make data-check`, `make check-project`; expect all green.
- [ ] **Step 3: Verify in the simulator:** delete the app, reinstall, open Counters straight away: the list is there before any sync could have finished.
- [ ] **Step 4: README:** a line in the data section saying counters ship with a bundled copy that `make data` keeps current.
- [ ] **Step 5: Commit** `"Counters: use the bundled copy in the app"`.

---

## As built

Built as planned: the pipeline writes `counters.json` and `counters.manifest.json` into the VerbKit resources
(`make data` keeps them current, `make data-check` fails on drift), `BundledCounters.load()` reads them and
rejects a copy that does not match its manifest, `CountersStore` starts on the bundle and uses a cached copy
only when its recorded version is not older, and `CountersSyncService` downloads nothing for a remote equal to
the bundle and ignores one older than it. 1035 Swift tests and the Python suite pass.

**What it does not do.** A first launch with no network still stops at "Can't Reach the Server": the app
waits for the verb data, which has no bundled copy, before it shows any tab. I checked this with a throwaway
build pointed at an unreachable host. So the Counters fallback helps the cases after the verbs are
downloaded: counters not yet fetched (installed before counters were published, or the counters sync failed),
a cache older than a newer app build, and any future screen that opens before the sync finishes. A real
offline first launch would also need verbs, grammar, furigana and words bundled (about 400 KB more).

Not checked on screen: the bundled counters showing while the counters sync fails with the verbs cached; that
state is covered by the store tests only.
