# Kotoba Table visual identity Implementation Plan

> **For agentic workers:** Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Kotoba Table a new visual identity: an app icon, a launch screen and a design signature (colour, type, shape, motion) that the whole app follows. The current look says "verb conjugation tool" and nothing else.

**Depends on:** `2026-10-23-rename-kotoba-table.md`. Do the rename first, so the new art, wordmark and strings are written once under the final name.

**Tech Stack:** SwiftUI (iOS 26 / macOS 26, Liquid Glass), asset catalog, `scripts/generate-icon.swift` (CoreGraphics), widgets.

## What exists today

- **Icon:** a dark violet / teal / pink aurora with a frosted glass tile carrying **活** (from 活用, "conjugation"). It is drawn by `scripts/generate-icon.swift` (260 lines) into `AppIcon.appiconset`: light, dark and tinted 1024 px iOS variants plus the macOS sizes.
- **Launch screen:** `LaunchImage` (1x/2x/3x PNGs) on `LaunchBackground` (a near-black navy, `#0B1026`). The image is baked: the glass tile, the aurora blobs, **早見表** and "VERB CONJUGATION" in letter-spaced caps. `DataLoadingView` reuses the same image, so the first-run screen matches the launch screen.
- **Colour:** per-verb-type pastels (`irregular` coral, `ru` sky, `u` amber) and per-て-group pastels in `App/VerbColors.swift`, with black labels on Liquid Glass capsules (`accentPill`). 46 call sites use tints or accent colours, and 18 files use `glassEffect`.
- **Type:** system fonts (273 `.font` calls) with `.rounded` only on the big counter readings.
- **No app accent colour:** there is no `AccentColor` asset.

The problem: the icon's one idea (活) is the old name, and the baked-in launch text ("早見表", "VERB CONJUGATION") is wrong for the new name and for the app's wider scope. Both need redoing, not patching.

## Global Constraints

- **Design direction is approved before anything is built** (Task 1 is a gate). The sweep touches most screens, so a wrong direction is expensive to undo.
- **The verb-type and て-group colours keep their meaning.** Users learn "coral is irregular". The overhaul may retune them, but not reassign them, and they must keep working as pairs with the new signature.
- **All colours come from named tokens** (a `Theme` / asset-catalog colour set with light, dark and high-contrast values). No new literal `Color(red:…)` in views. Existing literals move into the tokens as part of Task 3.
- **Accessibility:** text contrast at least 4.5:1 (3:1 for large text and icons) in light, dark and Increase Contrast; Dynamic Type through accessibility sizes; Reduce Motion and Reduce Transparency respected (Liquid Glass falls back to solid fills); VoiceOver labels unchanged.
- **Japanese typography is part of the signature, not an afterthought:** use system Japanese fonts (Hiragino) by default. Any bundled font needs a licence check and a size check, and must cover the kanji the data uses.
- **The launch screen must be static** (Apple's rule: it is a snapshot, not an animation). Any motion goes in `DataLoadingView` after launch.
- **Widgets follow the same tokens**, and the widget extension compiles `VerbColors.swift` directly. Shared tokens must live in a file both targets can compile (or in VerbKit if they stay UI-free).
- iPad and macOS are not redesigned beyond the icon (macOS needs its own icon sizes); they must keep compiling.
- Each stage is its own PR, so the icon and launch screen can ship without waiting for the full sweep.

## Review Focus

- A token change that quietly breaks contrast on one type pill (the amber `u` and sky `ru` pastels are the risky ones against any new background).
- Tinted and dark icon variants: tinted must be a grayscale-friendly silhouette, not the colour art desaturated.
- The launch screen matches the first frame of the app in light and dark mode, so there is no flash when it hands over.
- The icon survives at 29 pt and in the macOS 16 px slot: the mark must still read when tiny.
- No screen is left on the old look (the sweep's grep and screenshot checklist in Task 4).

## Task 1: Define the signature (design gate)

Output: a one-page spec, `docs/superpowers/specs/2026-10-23-kotoba-table-identity-design.md`, with mockups for the owner to approve. Nothing in Tasks 2 to 5 starts until this is approved.

- [ ] **Step 1: Pick the mark.** The name is 言葉 (words), and the current mark 活 is tied to the old name. Candidates to mock, each at 1024, 60 and 16 px:
  - **言** alone, as the mark. It is the kotoba radical and reads as "language", not "verbs".
  - **言** in a **table grid** (a 2×2 or 3×3 cell layout), tying the mark to the name's "Table" and to the app's core screen (the forms grid).
  - A **wordmark-first** icon: かな / 言葉 on a plain field, with no tile.
- [ ] **Step 2: Pick the palette.** Decide whether the aurora (violet / teal / pink) stays as the brand or gives way to something calmer. Recommend one primary brand colour as the new `AccentColor`, plus the existing type colours as the secondary system. Mock light and dark.
- [ ] **Step 3: Pick the type.** Keep system fonts and define a scale of 6 to 8 text styles (title, heading, body, caption, the large reading, the furigana line) with weights and design (`.rounded` or default) per style. Optionally one display face for the wordmark only.
- [ ] **Step 4: Pick shape and surface rules.** Corner radii, card versus list, when Liquid Glass is used (controls and floating chrome) and when it is not (reading surfaces, where it hurts legibility), and spacing steps.
- [ ] **Step 5: Pick motion rules.** The few places that animate (the form flip, quiz feedback, the launch hand-off), their durations, and the Reduce Motion fallback.
- [ ] **Step 6: Mock three key screens** with the proposed signature: the verb list, a verb's forms table, and a quiz question. Include the icon (light, dark, tinted), the launch screen and one widget.
- [ ] **Step 7: Approval.** Present to the owner. Record the decision and the final token values in the spec.

## Task 2: App icon

**Files:** `scripts/generate-icon.swift`, `App/Assets.xcassets/AppIcon.appiconset/*`

- [ ] **Step 1:** Rewrite `generate-icon.swift` for the approved mark. Keep the script (it keeps the icon reproducible without a design tool), and update the header comment, which currently explains 活. If the approved art is beyond what CoreGraphics does well, a design-tool export replaces the script, and the script and its mention are deleted rather than left stale.
- [ ] **Step 2:** Render the three iOS variants: light, dark, and tinted (a grayscale silhouette on a dark ground, as the tinted style expects), plus the macOS sizes (16 to 512 @1x/@2x). Use full-bleed square art for iOS (the system applies the mask), and the macOS squircle with its margin and shadow rules.
- [ ] **Step 3:** Add an icon preview step to the generator (a contact sheet at 1024, 180, 120, 60, 40, 29 and 16 px) so small-size legibility is checked every time.
- [ ] **Step 4:** `make project` and check the icon on the Home Screen in light, dark and tinted modes and in Settings and Spotlight (simulator), and in the macOS Dock and Finder.

## Task 3: Design tokens and the shared theme

**Files:** new `App/Theme/` (colours, type, spacing, radii), `App/VerbColors.swift`, `App/Assets.xcassets` (new `AccentColor`, colour sets), `project.yml`

- [ ] **Step 1:** Add the colour sets (brand, surfaces, text levels, plus the verb-type and て-group colours as asset-catalog colours with light, dark and high-contrast values). Set `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor` in `project.yml` for both targets.
- [ ] **Step 2:** Add typed accessors (`Theme.Color`, `Theme.Font` text styles, `Theme.Spacing`, `Theme.Radius`). `VerbColors.swift` forwards to them, so the 46 colour call sites need no change in this step.
- [ ] **Step 3:** Make the tokens available to the widget extension (add the file to its `sources`, as `VerbColors.swift` already is, or move them to VerbKit if UI-free).
- [ ] **Step 4:** A test (VerbKit or app target) that checks every token pair used as text on a background meets the contrast target in each appearance. This is the guard against the pastel problem.

## Task 4: Apply the signature across the app

Work screen by screen, in this order, as separate commits inside one PR (or a PR per group if large): shared components first (`accentPill`, cards, `FormCell`, `TypeFilterChip`, quiz buttons), then the verb list and detail, counters, grammar, quiz, word bank, settings.

- [ ] **Step 1:** Replace literal colours, ad-hoc `.font(.system(size:…))` and magic numbers with tokens, screen by screen. Keep layout and behaviour unchanged unless the approved spec says otherwise.
- [ ] **Step 2:** Apply the surface and Liquid Glass rules from Task 1 (remove glass from reading surfaces where the spec says so).
- [ ] **Step 3:** Motion: apply the agreed animations, with Reduce Motion fallbacks.
- [ ] **Step 4:** Sweep: `git grep -n -E "Color\(red:|\.font\(\.system\(size:"` outside `Theme/` must return only the cases the spec allows (for example the large reading), each with a comment.
- [ ] **Step 5:** Screenshot checklist, light and dark, default and largest accessibility text size, Increase Contrast on: verb list, verb detail, forms table, counters home, a counter page, grammar list and lesson, quiz question, quiz results, word bank, settings.

## Task 5: Launch screen and first-run screen

**Files:** `App/Assets.xcassets/LaunchImage.imageset/*`, `LaunchBackground.colorset`, `App/DataLoadingView.swift`, `project.yml` (`UILaunchScreen`)

- [ ] **Step 1:** Extend the generator (or the design export) to render the launch art at 1x/2x/3x. **Drop the baked-in text** ("早見表", "VERB CONJUGATION"). Show the mark only, and draw any wordmark as live SwiftUI text in `DataLoadingView` so it localises, scales and never goes stale again.
- [ ] **Step 2:** Update `LaunchBackground` to the approved ground colour, with light and dark values (it is currently the same navy in both).
- [ ] **Step 3:** In `DataLoadingView`, keep the first frame identical to the launch screen, then animate in the wordmark and the loading or error state (with the Reduce Motion fallback). Update its copy to the new name (the rename plan covers the string).
- [ ] **Step 4:** Check the hand-off on a cold launch (simulator, delete the app first, and launch on the smallest and largest iPhones) in light and dark, plus the macOS window.

## Task 6: Widgets, store and docs

- [ ] **Step 1:** Update the widget gallery previews, backgrounds and text styles to the tokens, and check all three widgets (verb, counter, grammar) in the sizes they offer, in light, dark and tinted (Home Screen tint) modes.
- [ ] **Step 2:** Add an "Identity" section to the README (or a short `docs/design.md`) that names the tokens, the icon generator command and the rules, so the next feature follows the signature instead of re-inventing colours.
- [ ] **Step 3 (when shipping):** App Store screenshots and the store icon (the same 1024 art) follow the final look.

## Delivery

1. After the rename PR: **Task 1**, a spec-only PR with the mockups. This is the design gate.
2. **Tasks 2 and 5** next, as one small PR (icon and launch screen), since they are self-contained and visible immediately.
3. **Task 3**, the token layer, with no visible change except the accent colour.
4. **Task 4**, the sweep, in reviewable chunks.
5. **Task 6**, the widgets and docs.
