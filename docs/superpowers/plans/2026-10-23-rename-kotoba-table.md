# Rename to Kotoba Table Implementation Plan

> **For agentic workers:** Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the app from "Verb Table" / "JP Verb Conjugation" to **Kotoba Table**, with a new bundle id, and rename the GitHub repo to match. The app now covers verbs, counters, grammar, a quiz, a word bank and a deconjugator, so a verb-only name no longer fits.

**Architecture:** A mechanical rename in one PR, then the GitHub repo rename. No behaviour changes. The app has never shipped (no TestFlight or App Store build), so nothing needs migrating: the bundle id, App Group, UTI and URL scheme all change outright.

**Tech Stack:** XcodeGen (`project.yml`), Swift / SwiftUI, VerbKit (`swift test`), Python scripts, GitHub.

## Names

| Thing | Old | New |
|---|---|---|
| Display name (`CFBundleDisplayName`, widget gallery, in-app text) | Verb Table | Kotoba Table |
| `PRODUCT_NAME` | JP Verb Conjugation | Kotoba Table |
| Xcode project, app target | JPVerbConjugation | KotobaTable |
| Widget extension target | VerbTableWidgets | KotobaTableWidgets |
| Bundle id | `dev.martinloeseth.jpverbconjugation` | `dev.martinloeseth.kotobatable` |
| Widget bundle id | `….jpverbconjugation.widgets` | `dev.martinloeseth.kotobatable.widgets` |
| App Group | `group.dev.martinloeseth.jpverbconjugation` | `group.dev.martinloeseth.kotobatable` |
| Word Bank UTI | `….jpverbconjugation.wordbank` | `dev.martinloeseth.kotobatable.wordbank` |
| URL scheme | `verbtable://` | `kotobatable://` |
| Logger subsystem | `dev.martinloeseth.jpverbconjugation` | `dev.martinloeseth.kotobatable` |
| Signing key path / env var | `~/.config/verbtable/…`, `$VERBTABLE_SIGNING_KEY` | `~/.config/kotobatable/…`, `$KOTOBATABLE_SIGNING_KEY` |
| GitHub repo | `martinloesethjensen/jp-verb-conjugation-app` | `martinloesethjensen/kotoba-table` |

`VerbKit` (the package and module) keeps its name: it is internal, and renaming it touches every import for no user-visible gain. Say so in the PR so it is a decision, not an omission.

## Global Constraints

- No behaviour change. The diff is renames only, plus the README note on the new key path.
- Do not touch `data/` content other than the description string in `data/grammar.json`. Changing that string changes the file hash, so `manifest.json` must be regenerated and re-signed by the owner (`make data`, then `make sign-commit`). Do not sign or push data yourself.
- Do not rewrite the history docs (`docs/superpowers/plans/*`, `specs/*`) wholesale: they record what was true when written. Only fix paths and commands a reader would still copy. Add a one-line note to the README that earlier docs use the old names.
- The URL scheme, bundle id and App Group are each used in several files and must change together, or deep links, widgets and the shared store break silently (the widget would read an empty App Group).

## Review Focus

- App Group string identical in: `App/…entitlements`, `Widgets/…entitlements`, `App/UserDefaults+AppGroup.swift`, `VerbModelContainer.appGroupIdentifier`. A mismatch gives the widgets an empty store with no crash.
- URL scheme identical in: `project.yml`, `App/Info.plist` (generated, but check), `Route+URL.swift`, and the tests. `QuizLink` and `DailyReminder` build links from `Route`, so they follow.
- UTI identical in: `project.yml`, `App/Info.plist`, `WordBankFileType.swift`.
- The widget `kind` string `"VerbTableWidget"` stays or is renamed together with the struct. It only matters to installed widgets, so there is no migration cost, but pick one and keep the struct and kind consistent.
- `GitHubVerbFetcher.githubMain` and `IssueReportURL.repository` point at the new repo name. This is how the app fetches its data, so it is the one rename with a runtime effect. Task 3 covers the order.

## Task 1: Rename in the repo

**Files:** `project.yml`, `App/`, `Widgets/`, `Packages/VerbKit/`, `scripts/`, `README.md`, `.github/`, `data/grammar.json`

- [ ] **Step 1: Rename files and types with `git mv`** (keeps history)
  - `App/JPVerbConjugation.entitlements` → `App/KotobaTable.entitlements`
  - `App/JPVerbConjugationApp.swift` → `App/KotobaTableApp.swift`, and `struct JPVerbConjugationApp` → `KotobaTableApp`
  - `Widgets/VerbTableWidgets.entitlements` → `Widgets/KotobaTableWidgets.entitlements`
  - `Widgets/VerbTableWidgets.swift` → `Widgets/KotobaTableWidgets.swift`, and `VerbTableWidgets` → `KotobaTableWidgets`
  - `VerbTableWidget` (in `VerbWidget.swift` and its previews in `VerbWidgetViews.swift`) → `KotobaTableWidget`, with `kind` to match
  - `VerbTableShortcuts` (`App/Intents/VerbIntents.swift`) → `KotobaTableShortcuts`
- [ ] **Step 2: `project.yml`.** Project name, both target names, the dependency `VerbTableWidgets_${platform}`, entitlement paths, both comments that say "change both together", `bundleIdPrefix` (unchanged), `CFBundleURLName`, URL scheme, UTI and its `LSItemContentTypes`, both `PRODUCT_BUNDLE_IDENTIFIER`s, both `PRODUCT_NAME`s, both `CFBundleDisplayName`s.
- [ ] **Step 3: Swift strings.** The App Group in `UserDefaults+AppGroup.swift` and `VerbModelContainer.swift`; the three logger subsystems (`JPVerbConjugationApp.swift`, `OnDeviceEntrySuggester.swift`, `DataSyncStatus.swift`); the UTI in `WordBankFileType.swift`; `Route.urlScheme` and the doc comments in `Route+URL.swift`, `QuizLink.swift`, `DailyReminder.swift`, `SpotlightIndexer.swift`, `VerbIntents.swift`.
- [ ] **Step 4: User-visible text.** "Verb Table" → "Kotoba Table" in the widget descriptions and display names (`GrammarWidget`, `CounterWidget`, `VerbWidget`, the three `…WidgetViews`), and "JP Verb Conjugation needs to download…" in `DataLoadingView.swift`. Check `App/Info.plist` and `Widgets/Info.plist` are regenerated from `project.yml` rather than hand-edited (`make project`).
- [ ] **Step 5: Tests.** Update the scheme strings in `RouteURLTests.swift` and `QuizLinkTests.swift`. Include the uppercase case (`VERBTABLE://VERB/x` → `KOTOBATABLE://VERB/x`).
- [ ] **Step 6: Signing key path.** In `scripts/sign_manifest.py` and `scripts/sign_and_commit.sh`, `README.md` and `docs/security/data-signing.md`: `~/.config/verbtable` → `~/.config/kotobatable` and `VERBTABLE_SIGNING_KEY` → `KOTOBATABLE_SIGNING_KEY`. Keep the old path and env var as a fallback in `sign_manifest.py` for now, with a "remove after the key is moved" comment, so the owner is not locked out mid-rename. The owner moves the key file themselves; it is outside the repo and must never be committed.
- [ ] **Step 7: Data description.** `data/grammar.json` "for the JP Verb Conjugation app" → "for the Kotoba Table app". Then `make data` and flag in the PR that `manifest.json` needs re-signing.
- [ ] **Step 8: README.** Title, the "Verb Table" mention, and a one-line note that older plans and specs under `docs/superpowers/` use the previous names.
- [ ] **Step 9: Sweep.** `git grep -n -i -E "jpverbconjugation|jp-verb-conjugation|verb ?table|verbtable"` outside `docs/superpowers/` must return nothing except the intentional fallback in Step 6 and `VerbKit`.

**Verify:** `make check`, `make test-py`, `make test-swift` (macOS), `make project`, then build and run both platforms. Check by hand that a widget shows data (App Group), that a `kotobatable://verb/<id>` link opens the verb, that Spotlight results open, and that a `.wordbank` file opens in the app.

## Task 2: Point the app at the renamed repo

Do this in the same PR as Task 1 so the code and the repo name stay in step.

- [ ] `GitHubVerbFetcher.githubMain`: `root` → `https://raw.githubusercontent.com/martinloesethjensen/kotoba-table/`.
- [ ] `IssueReportURL.repository` → `martinloesethjensen/kotoba-table`, and the expectations in `IssueReportURLTests.swift` and `FormLookupTests.swift`.
- [ ] Check `.github/workflows/*.yml` and the issue templates for hard-coded repo names (the grep found none, so this should be a no-op).

## Task 3: Rename the GitHub repo (owner action)

The repo rename needs admin rights, so the owner does it. I cannot do it from here. The order below avoids a window where the app fetches from a name that does not exist yet.

- [ ] **Step 1:** Merge the Task 1 and 2 PR first. While the old repo name still exists, nothing the app does is broken, and no installed build points at the new name yet (the app has never shipped).
- [ ] **Step 2:** Rename on GitHub: Settings → General → Repository name → `kotoba-table`. GitHub redirects the old web, git and `raw.githubusercontent.com` URLs, so existing clones and links keep working, but do not rely on that: a new repo created under the old name would break the redirect.
- [ ] **Step 3:** Update local clones: `git remote set-url origin https://github.com/martinloesethjensen/kotoba-table`.
- [ ] **Step 4:** Check Settings → Pages, webhooks, branch protection and any release or tag protection (the signing doc says it is still to do) carry over. Check the Actions secrets are still present.
- [ ] **Step 5:** Open `https://raw.githubusercontent.com/martinloesethjensen/kotoba-table/main/data/manifest.json` and confirm it loads, then run `make verify`. The signature covers the manifest, not the URL, so it should still pass.
- [ ] **Step 6:** Update the repo description, and any external links (profile README, notes).

## Task 4: Apple Developer setup (owner action)

Needed before a device or TestFlight build, and not needed for the simulator.

- [ ] Register the App IDs `dev.martinloeseth.kotobatable` and `….widgets`, and the App Group `group.dev.martinloeseth.kotobatable`, in the developer portal. With `CODE_SIGN_STYLE: Automatic` and the team already set, Xcode can do this on first build.
- [ ] Delete the old simulator and device installs of the previous bundle id; they are separate apps and will not be updated.
- [ ] Create the App Store Connect record under the new name only when it is time to ship. The name "Kotoba Table" is not reserved until then, so check it is free.

## Delivery

1. One PR: Tasks 1 and 2 (a pure rename, easy to review).
2. The owner re-signs `data/manifest.json` (Step 7) before merge.
3. After the merge, the owner does Tasks 3 and 4.
