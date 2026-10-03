# Overview Search, Filters and Toolbar Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the Verbs overview a compact bar (Quiz + ⋯ menu), an inline search field with a scrolled-away magnifier, and one chip row (Type menu chip + te-form chips); give the Grammar list the same bar and search.

**Architecture:** Pure SwiftUI view changes in `App/`. No VerbKit, data, widget or filtering logic changes. A new `inlineSearch` modifier centralises platform-specific search placement and focus; a new `TypeFilterChip` replaces the segmented Type control inside the existing chip row. The Settings sheet moves up to `RootView` so the Grammar tab can open it.

**Tech Stack:** SwiftUI (iOS 26 / macOS 26), XcodeGen, `searchable` + `searchFocused`, `onScrollGeometryChange`.

**Spec:** `docs/superpowers/specs/2026-10-02-overview-search-redesign-design.md`

## Global Constraints

- Top bar (Verbs): exactly **Quiz** (labelled; the current Random Quiz) and a **⋯ menu** with, in order: Progress, Guide, Settings, Report a problem. No separate search circle; no `.searchToolbarBehavior(.minimize)`.
- Search: inline field under the large title; pulling down reveals it; a magnifier appears in the bar once the field has scrolled away and, on tap, scrolls to top and focuses the field. Prompt is "Search verbs…" (Verbs) and "Search grammar…" (Grammar).
- Level scope bar (`levelScopeBar`) is unchanged.
- One chip row: **Type ▾** menu chip first (All, Irregular, Ru-verbs, U-verbs; shows its value and is highlighted when a type is chosen), then All + te-form chips. The segmented control section is removed.
- Subtitle (`filterSummary`), back-to-top button, empty states, and "Clear filters" (clears both filters) keep current behaviour.
- Grammar list: same bar and inline search, no chips; its ⋯ menu holds Settings and Report a problem.
- Verbs / Grammar tab bar unchanged. No VerbKit, data, widget, or search/filter logic changes.
- iOS-only SwiftUI APIs behind `#if os(iOS)`; macOS must compile (`CODE_SIGNING_ALLOWED=NO`).
- Build commands (after `xcodegen generate`): iOS `xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination 'id=4DB21AA8-1057-4014-A2C0-6D4968330CA5' -derivedDataPath .build-dd build`; macOS `-scheme JPVerbConjugation_macOS -destination 'platform=macOS' -derivedDataPath .build-dd-mac CODE_SIGNING_ALLOWED=NO`. Package tests: `swift test --package-path Packages/VerbKit` (369 must stay green). Never commit `.build-dd*/` or PNGs; `git add` explicit paths.
- The app has no UI test target; view changes are verified by builds plus on-screen simulator checks (pass the simulator id on every call; screenshots lag, so wait before capturing).

---

### Task 1: One chip row with a Type menu chip

**Files:**
- Create: `App/TypeFilterChip.swift`
- Modify: `App/TeFormFilter.swift`
- Modify: `App/VerbListView.swift` (filters section, `filterSummary`, empty-state "Clear filters" unchanged)

**Interfaces:**
- Produces: `extension VerbType { var filterTitle: String }` ("Irregular", "Ru-verbs", "U-verbs"); `struct TypeFilterChip: View { init(selection: Binding<VerbType?>) }`; `TeFormFilter(type: Binding<VerbType?>, selection: Binding<TeGroup?>)`; internal `View.chipBackground(_ accent: Color?)` (drop `private` in `TeFormFilter.swift`).

- [ ] **Step 1: Create the Type chip**

`App/TypeFilterChip.swift`:

```swift
import SwiftUI
import VerbKit

extension VerbType {
    /// How the type reads in the filter chip and the navigation subtitle.
    var filterTitle: String {
        switch self {
        case .irregular: "Irregular"
        case .ru: "Ru-verbs"
        case .u: "U-verbs"
        }
    }
}

/// First chip of the filter row: a menu that picks the verb type. Shows its value, and the
/// chosen outline, once a type is selected.
struct TypeFilterChip: View {
    @Binding var selection: VerbType?

    var body: some View {
        Menu {
            Picker("Type", selection: $selection) {
                Text("All").tag(VerbType?.none)
                ForEach([VerbType.irregular, .ru, .u], id: \.self) { type in
                    Text(type.filterTitle).tag(VerbType?.some(type))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selection?.filterTitle ?? "Type")
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
            .font(.callout.weight(selection == nil ? .semibold : .bold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .chipBackground(nil)
            .overlay { if selection != nil { Capsule().strokeBorder(Color.primary, lineWidth: 2) } }
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Host it in the chip row**

In `App/TeFormFilter.swift`: add `@Binding var type: VerbType?` above `selection`; update the doc comment to "Filter chips: a Type menu, then single-select て-form groups…"; at the start of the `HStack` (before the "All" chip) add `TypeFilterChip(selection: $type)`; remove `private` from `extension View { func chipBackground… }` (change `private extension View` to `extension View`).

- [ ] **Step 3: Use it in the list, remove the segmented section**

In `App/VerbListView.swift`: change `TeFormFilter(selection: $teFilter)` to `TeFormFilter(type: $typeFilter, selection: $teFilter)`; delete the whole second `Section { Picker("Type"…) .pickerStyle(.segmented) … }`; in `filterSummary` replace the `switch typeFilter` block with `if let typeFilter { parts.append(typeFilter.filterTitle) }`.

- [ ] **Step 4: Build both platforms**

Run `xcodegen generate`, then the iOS and macOS build commands from Global Constraints. Expected: both `** BUILD SUCCEEDED **`, no new warnings.

- [ ] **Step 5: Check on screen (iPhone simulator)**

Launch the built app. Confirm: one chip row with "Type ▾" first; choosing Ru-verbs shows "Ru-verbs ▾" outlined, filters the list and sets the subtitle; picking All resets; Type + a te-form chip combine; the empty state "Clear filters" clears both (e.g. Irregular + したいて combination with no match). Take a screenshot.

- [ ] **Step 6: Commit**

```bash
git add App/TypeFilterChip.swift App/TeFormFilter.swift App/VerbListView.swift
git commit -m "Merge the Type filter into the chip row as a menu chip

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Compact Verbs bar and inline search with magnifier

**Files:**
- Create: `App/InlineSearch.swift`
- Modify: `App/VerbListView.swift` (search, toolbar, scroll tracking, focus)

**Interfaces:**
- Consumes: `VerbListView` from Task 1 (`filtersOffscreen`, `Self.filtersID`, `proxy`).
- Produces: `View.inlineSearch(text: Binding<String>, prompt: LocalizedStringKey, focused: FocusState<Bool>.Binding) -> some View` used by Task 3.

- [ ] **Step 1: Create the search modifier**

`App/InlineSearch.swift`:

```swift
import SwiftUI

extension View {
    /// Search field under the large title (iOS) or in the toolbar (macOS). On iOS it hides when
    /// the list scrolls and returns on pull-down; `focused` lets a toolbar button bring it back.
    @ViewBuilder func inlineSearch(
        text: Binding<String>,
        prompt: LocalizedStringKey,
        focused: FocusState<Bool>.Binding
    ) -> some View {
        #if os(iOS)
        searchable(text: text, placement: .navigationBarDrawer(displayMode: .automatic), prompt: prompt)
            .searchFocused(focused)
        #else
        searchable(text: text, prompt: prompt)
            .searchFocused(focused)
        #endif
    }
}
```

- [ ] **Step 2: Wire search, scroll tracking and focus into the list**

In `App/VerbListView.swift`:
- Add `@FocusState private var searchFocused: Bool` and `@State private var scrolledAwayFromTop = false`.
- Replace `.searchable(text: $search, prompt: "Search hiragana, kanji, romaji, or English…")` with `.inlineSearch(text: $search, prompt: "Search verbs…", focused: $searchFocused)`.
- Delete `.searchToolbarBehavior(.minimize)` and its two-line comment (keep `.listSectionSpacing(.compact)` inside `#if os(iOS)`).
- On the `List`, add (iOS only, next to `.listSectionSpacing`):

```swift
.onScrollGeometryChange(for: Bool.self) { geometry in
    geometry.contentOffset.y + geometry.contentInsets.top > 44
} action: { _, scrolled in
    scrolledAwayFromTop = scrolled
}
```

(44 pt is the height of the search drawer; tune on screen so the magnifier appears exactly when the field has gone.)

- [ ] **Step 3: Replace the toolbar**

Replace the whole `.toolbar { … }` with:

```swift
.toolbar {
    #if os(iOS)
    if scrolledAwayFromTop {
        ToolbarItem(placement: .primaryAction) {
            Button("Search", systemImage: "magnifyingglass") {
                scrollToTop?()
                searchFocused = true
            }
        }
    }
    #endif
    ToolbarItem(placement: .primaryAction) {
        Button(action: onRandomQuiz) {
            Label("Quiz", systemImage: "gamecontroller")
                .labelStyle(.titleAndIcon)
        }
    }
    ToolbarItem(placement: .primaryAction) {
        Menu("More", systemImage: "ellipsis") {
            Button("Progress", systemImage: "chart.bar", action: onProgress)
            Button("Guide", systemImage: "info.circle") { showGuide = true }
            Button("Settings", systemImage: "gearshape", action: onSettings)
            ReportProblemButton(item: "")
        }
    }
}
```

The toolbar sits outside the `ScrollViewReader`, so the magnifier cannot reach `proxy`. Make it reachable: add `@State private var scrollToTop: (() -> Void)?`, and on the `List` inside the `ScrollViewReader` closure add `.onAppear { scrollToTop = { withAnimation { proxy.scrollTo(Self.filtersID, anchor: .top) } } }`.

- [ ] **Step 4: Build both platforms**

`xcodegen generate` then both build commands. Expected: `** BUILD SUCCEEDED **`. If `.labelStyle(.titleAndIcon)` or `.searchFocused` is unavailable on macOS, wrap the offending line in `#if os(iOS)`.

- [ ] **Step 5: Check on screen**

Confirm on iPhone: the bar shows only "Quiz" (with its text) and ⋯; the ⋯ menu lists Progress, Guide, Settings, Report a problem and each opens the right sheet/link; the search field sits under the title; typing, romaji and the My levels/All levels scope bar still work (hide a level in Settings first); scrolling down hides the field and shows the magnifier; tapping the magnifier scrolls to the top and focuses search with the keyboard up; cancelling search does not refocus. If the field does not reappear after the scroll, make the magnifier action scroll with `proxy.scrollTo(Self.filtersID, anchor: .top)` first and set `searchFocused = true` on the next run loop (`DispatchQueue.main.async`). Take screenshots of the top of the list and the scrolled state.

- [ ] **Step 6: Commit**

```bash
git add App/InlineSearch.swift App/VerbListView.swift
git commit -m "Compact Verbs bar with inline search and a scrolled-away magnifier

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Grammar bar and search, Settings from either tab

**Files:**
- Modify: `App/GrammarListView.swift`, `App/MainTabView.swift`, `App/RootView.swift`

**Interfaces:**
- Consumes: `inlineSearch(text:prompt:focused:)` from Task 2.
- Produces: `GrammarListView(selection:onSettings:)`, `GrammarTab(selection:preferredColumn:onSettings:)`, `MainTabView(verbSelection:incomingRoute:onSettings:verbsTab:)`.

- [ ] **Step 1: Grammar list search and menu**

In `App/GrammarListView.swift`: add `var onSettings: () -> Void` after `selection`, and `@FocusState private var searchFocused: Bool`; replace `.searchable(text: $search, prompt: "Search grammar…")` with `.inlineSearch(text: $search, prompt: "Search grammar…", focused: $searchFocused)`; replace the toolbar content with:

```swift
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Menu("More", systemImage: "ellipsis") {
            Button("Settings", systemImage: "gearshape", action: onSettings)
            ReportProblemButton(item: "")
        }
    }
}
```

- [ ] **Step 2: Thread `onSettings` through the tabs**

In `App/MainTabView.swift`: add `let onSettings: () -> Void` to `MainTabView` with a matching `init` parameter (`onSettings: @escaping () -> Void`, placed before the `verbsTab` builder), `onSettings: () -> Void` to `GrammarTab`, pass `onSettings` into `GrammarTab(...)` and `GrammarListView(selection: $selection, onSettings: onSettings)`.

In `App/RootView.swift`: pass `onSettings: { showingSettings = true }` to `MainTabView(...)`.

- [ ] **Step 3: Present Settings from the root**

The Settings sheet is attached to the Verbs tab's `NavigationSplitView`, which does not present from the Grammar tab. Move the whole `.sheet(isPresented: $showingSettings) { NavigationStack { SettingsView() … } }` block out of `verbsTab` and attach it to the `Group` in `body`, right after `.onOpenURL { … }`'s closing brace (keep the contents identical).

- [ ] **Step 4: Build and run all checks**

`xcodegen generate`; both builds (`BUILD SUCCEEDED`); `swift test --package-path Packages/VerbKit` (369 pass); `python3 scripts/update_data.py --check` ("data is up to date").

- [ ] **Step 5: Check on screen**

Grammar tab: ⋯ menu shows Settings and Report a problem; Settings opens as a sheet from Grammar and from Verbs and its Done closes it; inline search under "Grammar" works with the scope bar; magnifier is not expected here. Re-check Verbs. Open a widget link (`xcrun simctl openurl 4DB21AA8-1057-4014-A2C0-6D4968330CA5 verbtable://verb/<an id from data/verbs.json>`) with Settings open: the sheet closes and the verb opens. Take screenshots of Grammar and Verbs.

- [ ] **Step 6: Commit**

```bash
git add App/GrammarListView.swift App/MainTabView.swift App/RootView.swift
git commit -m "Give the Grammar list the compact bar and inline search, Settings from either tab

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Self-Review

- **Spec coverage:** top bar (Task 2); inline search, magnifier, shorter prompt (Task 2); one chip row, Type chip value/highlight, segmented section removed, subtitle/back-to-top/Clear filters kept (Task 1); Grammar bar and search, Settings in Grammar menu (Task 3); `TypeFilterChip` + `TeFormFilter` shared styling (Task 1); platforms and testing (all tasks' builds and on-screen steps). Spec did not name the Settings-sheet move or the `onSettings` threading; they are required for "Settings from the Grammar tab" (Task 3).
- **Placeholders:** none; Task 2 Step 3 states the final magnifier action explicitly.
- **Type consistency:** `filterTitle`, `TypeFilterChip(selection:)`, `TeFormFilter(type:selection:)`, `inlineSearch(text:prompt:focused:)`, `onSettings` match across tasks.
