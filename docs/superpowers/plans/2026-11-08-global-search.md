# Global Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Search tab (`Tab(role: .search)`) that finds verbs, grammar, counters and Word Bank entries from one field, typed in romaji, kana, kanji, English or a conjugated form, with scope chips, recent searches and a hidden-levels row.

**Architecture:** One pure VerbKit function, `GlobalSearch.results`, runs the four existing searches (`matchesSearch`, `searched(for:)`, `searchCounters`, `WordBankSearchIndex.search`) under one scope and level setting and reports what the level setting hid and whether the query was read as romaji. App adds a `SearchTab` (empty state with chips, recents and a "Type it any way" card; results in sections) and wires it into `MainTabView`; results open through the existing `openRoute` and a new Word Bank opener.

**Tech Stack:** Swift 6 / SwiftUI (iOS 26, macOS 26), XCTest.

**Spec:** `docs/superpowers/specs/2026-11-06-paper-ink-redesign-design.md` (row 4) and the canvas boards "Search: before typing" (`project/SearchRecent.dc.html`) and "Search: romaji results" (`project/SearchResults.dc.html`) at https://claude.ai/artifact/7eCLPFjJnWRoGB2n85ocr2.

## Global Constraints

- VerbKit stays UI-free; wording (section titles, chip titles, messages) lives in App.
- Reuse, don't fork: the four searches above, `Romaji.toHiragana`, `LevelSettings`/`Leveled`, `LevelScope`, `RecentSearches`, `FormLookupStore.items(in:)`, `JapaneseText`, `TypeLabel`, `LevelBadge`, `paperCard`, `paperBackground`, `FilterChip`, `SectionHeader`, `RowChevron`.
- Liquid Glass on chrome only (the system search tab and field); results sit on `palette.paper` in `paperCard` sections with `rule` separators.
- Furigana on every kanji when on: Japanese text with kanji goes through `JapaneseText`.
- The existing per-tab searches stay as they are.
- Recent searches: the last ten, newest first, this device only (standard `UserDefaults`, key `search.recentQueries`), recorded on submit and when a result is opened; never exported.
- Hidden levels: per search, "Show" widens this search to all levels; clearing the field returns it to my levels (the `LevelScope` rule); the saved setting never changes.
- Copy (exact): title "Search" with `検索`; chips "Everything", "Verbs", "Grammar", "Counters", "Word Bank"; "Recent" / "Clear"; card "Type it any way" with rows Romaji `nomu → のむ`, Kana or kanji `飲む · のむ · ノム`, English `drink`, A form `のんだ → 飲む`; results line "Reading nomu as のむ · 4 results" (the "Reading … as …" part only when the query was read as romaji); hidden row "1 more in a hidden level (N3)" / "3 more in hidden levels (N2, N3)" with a "Show" button; no results "No results for “…”".

## Review Focus

1. A query that is both romaji and English ("make", "sake", "kite") — English matches still show, and "Reading … as …" appears only when the kana reading found something the plain text did not (Task 1, `testEnglishThatIsAlsoRomajiShowsReadingOnlyForKanaOnlyHits`).
2. Whitespace or punctuation only ("  ", "?") — the empty state, nothing recorded as recent, no crash (Task 1, `testBlankAndPunctuationAreEmpty`).
3. A kanji conjugated form (飲んだ) — finds 飲む through the form lookup without listing it twice (Task 1, `testExtraVerbsAreAddedOnce`).
4. A query whose only matches are in hidden levels — the hidden row, not "No results" (Task 1, `testOnlyHiddenMatchesReportsTheHiddenCount`).
5. AX5 text and a narrow width — chips scroll horizontally, rows wrap, nothing clips (Task 3, simulator check).

---

### Task 1: GlobalSearch (VerbKit)

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Search/GlobalSearch.swift`, `Packages/VerbKit/Tests/VerbKitTests/GlobalSearchTests.swift`

**Interfaces:**
- Produces:
  - `public enum SearchScope: String, CaseIterable, Sendable { case everything, verbs, grammar, counters, wordBank }`
  - `public struct GlobalSearchResults: Sendable { verbs: [Verb]; grammar: [GrammarPoint]; counters: CounterSearchResults; wordBank: [WordBankMatch]; hiddenCount: Int; hiddenLevels: [JLPTLevel] /* ascending N5…N1 order as JLPTLevel sorts */; readingAs: String?; var isEmpty: Bool; var count: Int /* verbs + grammar + counter groups/counters/forms/things + wordBank */; static let empty }`
  - `public enum GlobalSearch { static let recentsKey = "search.recentQueries"; static func results(for query: String, scope: SearchScope, levels: LevelSettings, verbs: [Verb], grammar: [GrammarPoint], counters: [Counter], groups: [CounterGroup], wordBank: WordBankSearchIndex?, furigana: FuriganaDictionary?, extraVerbs: [Verb] = []) -> GlobalSearchResults }`
- Rules:
  - Trimmed query empty, or with no letter, kana or kanji (`?`, `…`) → `.empty`.
  - A section outside `scope` is empty and adds nothing to `hiddenCount`.
  - Verbs: `matchesSearch` in data order, then `extraVerbs` not already listed (by `id`). Grammar: `searched(for:furigana:)`. Counters: `searchCounters`. Word Bank: `index.search(WordBankQuery(text: query))`, no level filter.
  - Levels: verbs, grammar points (`isVisible(in:)`) and counters (counters and form matches by their counter) not visible under `levels` are left out; `hiddenCount` counts them, `hiddenLevels` collects their levels (`levelsTaught`), distinct, sorted.
  - `readingAs` = `Romaji.toHiragana(query)` (spaces removed) when it exists and the kana search finds at least one verb, grammar point or counter result (any level) that the raw-text search does not.
  - Recents reuse `RecentSearches` storing `WordBankQuery(text:)` under `recentsKey`.

- [ ] **Step 1: Write the failing tests** in `GlobalSearchTests`, using the bundled data (`BundledData<VerbDataFile>.load(named: "verbs")`, `"grammar"`, `"counters"`) so real ids are asserted:
  - `testRomajiFindsTheVerbAndReportsTheReading`: "nomu" → verbs contain id `のむ`; `readingAs == "のむ"`.
  - `testEnglishFindsVerbsGrammarAndCountersWithoutAReading`: "drink" → verbs contain `のむ`; `readingAs == nil`.
  - `testEnglishThatIsAlsoRomajiShowsReadingOnlyForKanaOnlyHits`: a query whose kana reading finds nothing extra (pick "make" or another word checked against the data while writing the test) → `readingAs == nil` while English hits are present.
  - `testScopeLimitsSections`: "nomu" with `.grammar` → verbs, counters and wordBank empty.
  - `testHiddenLevelsAreCountedNotShown`: hide N5 → `のむ` absent, `hiddenCount >= 1`, `hiddenLevels.contains(.n5)`; with `LevelSettings()` it is listed and `hiddenCount == 0`.
  - `testOnlyHiddenMatchesReportsTheHiddenCount`: a query matching only N5 items with N5 hidden → `isEmpty == true` for the shown sections, `hiddenCount > 0`.
  - `testBlankAndPunctuationAreEmpty`: "", "   ", "?" → `count == 0`, `hiddenCount == 0`, `readingAs == nil`.
  - `testExtraVerbsAreAddedOnce`: `extraVerbs: [のむ]` with query "飲んだ" → `のむ` listed exactly once; with query "nomu" (already matched) still once.
  - `testWordBankMatchesAreIncludedAndIgnoreLevels`: an index over one entry "飲み会" (meaning "drinking party") → "nomi" or "飲み" finds it with every level hidden.
  - `testRecentsKeyIsSeparateFromTheWordBanks`: `GlobalSearch.recentsKey != RecentSearches.defaultsKey`.
- [ ] **Step 2:** `cd Packages/VerbKit && swift test --filter GlobalSearchTests` → FAIL to compile.
- [ ] **Step 3: Implement** `GlobalSearch.swift` per the rules.
- [ ] **Step 4:** filtered tests PASS; `make test-swift` all PASS.
- [ ] **Step 5:** AGENTS.md row for `GlobalSearch`, `SearchScope`. Commit — "VerbKit: one search over verbs, grammar, counters and the Word Bank".

### Task 2: The Search tab (App)

**Files:**
- Create: `App/Search/SearchTab.swift`, `App/Search/SearchEmptyState.swift`, `App/Search/SearchResultsList.swift`, `App/Search/SearchDisplay.swift`

**Interfaces:**
- Consumes: `GlobalSearch`, `SearchScope`, `GlobalSearchResults` (Task 1); `VerbStore` (verbs, grammarPoints), `CountersStore` (counters, groups), `WordBankStore.searchIndex(readingKey:derivedReading:)`, `FuriganaStore` (dictionary), `FormLookupStore.items(in:)` (known readings' verbs as `extraVerbs`).
- Produces:
  - `struct SearchTab: View { let openWordBankEntry: (UUID) -> Void }` — `NavigationStack` with `.searchable(text:prompt: "Search everything")`; state `query`, `scope: SearchScope = .everything`, `levelScope: LevelScope = .mine` (back to `.mine` when `query` is cleared), recents from `@AppStorage(GlobalSearch.recentsKey)` via `RecentSearches`.
  - `SearchDisplay`: `title(_ scope: SearchScope) -> String`, `resultsLine(query:readingAs:count:) -> String`, `hiddenLine(count:levels:) -> String`, `noResults(_ query:) -> String`.

- [ ] **Step 1: Empty state** (`SearchEmptyState`): header `Text("Search")` large title with `JapaneseText("検索")` beside it (the navigation title stays "Search" for VoiceOver, its display hidden on iOS); a horizontal `ScrollView` of `FilterChip`s for the five scopes; "Recent" with "Clear" and the recents as chips with a `clock` glyph (tap fills the field); the "Type it any way" `paperCard` with the four rows (Japanese through `JapaneseText`). The chips also show above results.
- [ ] **Step 2: Results** (`SearchResultsList`): the results line, then one section per non-empty kind with `SectionHeader` titles "Verbs", "Grammar", "Counters", "Word Bank", each a `paperCard` of rows separated by `rule` hairlines:
  - Verb: `JapaneseText(verb.kanji ?? verb.dict)` in `Font.headword(.title3)`, meaning in muted, `TypeLabel`, `LevelBadge(level: verb.jlpt)`; opens `.verb(verb.id)`.
  - Grammar: title in `Font.headword(.body)`, summary in muted (one line), `LevelBadge(level: point.levelRange?.lowerBound)`; opens `.grammar(point.id)`.
  - Counter: groups, counters, forms and things flattened in that order; a counter row shows its counter large, its meaning and group summary, `LevelBadge`; a form row shows the written form and reading; a thing row shows the thing and its first counter; all open `.counter(id)` (a group opens `.counterGroup(id)`).
  - Word Bank: `JapaneseText(entry.text)` with its first meaning, and "Folder: …" when filed; opens `openWordBankEntry(entry.id)`.
  - Hidden row: dashed `rule` outline, `SearchDisplay.hiddenLine`, a "Show" button setting `levelScope = .all`.
  - Opening a result records the query in recents.
  - No results and nothing hidden: `ContentUnavailableView.search(text:)` with `SearchDisplay.noResults`.
- [ ] **Step 3:** `.onSubmit(of: .search)` records the query; blank queries are not recorded (`RecentSearches.record` already ignores them).
- [ ] **Step 4:** iOS and macOS builds succeed. Commit — "Search tab: one field for verbs, grammar, counters and the Word Bank".

### Task 3: Wiring, docs and checks

**Files:**
- Modify: `App/MainTabView.swift` (`AppTab.search`; `Tab(value: AppTab.search, role: .search) { SearchTab(openWordBankEntry:) }` after Word Bank; the opener sets `wordBankSelection`, `wordBankColumn = .detail`, `tab = .wordBank`), `AGENTS.md` (`SearchTab` row), `docs/superpowers/specs/2026-11-06-paper-ink-redesign-design.md` (row 4 "(built)")

- [ ] **Step 1:** Add the tab and the opener. `openRoute` already switches tabs for verb, grammar and counter results.
- [ ] **Step 2:** iOS and macOS builds succeed; `make test-swift` PASS; `make check-project` clean.
- [ ] **Step 3: Simulator** (iPhone 18 Pro): the search button sits apart in the tab bar; empty state shows chips, recents and the card; "nomu" shows "Reading nomu as のむ", 飲む, a grammar lesson and 杯; "drink" shows no reading line; a scope chip narrows sections; hide N5 in Settings and search "nomu" → the hidden row, "Show" lists them, clearing the field resets; tapping each kind of result lands on its page (Word Bank with a test entry); "飲んだ" finds 飲む; AX5 and dark appearance (Review Focus 5). Screenshots into the scratchpad.
- [ ] **Step 4:** Docs; commit — "Add the Search tab".
